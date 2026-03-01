import Dispatch
import Foundation
import Darwin

struct ZenMLPaths: Sendable {
    let configDirectory: URL
    let configYAML: URL
    let credentialsYAML: URL

    static func resolve(fileManager: FileManager = .default) -> ZenMLPaths {
        let env = ProcessInfo.processInfo.environment["ZENML_CONFIG_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDirectory: URL

        if let env, !env.isEmpty {
            baseDirectory = URL(fileURLWithPath: env).standardizedFileURL
        } else {
            baseDirectory = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("zenml", isDirectory: true)
        }

        return ZenMLPaths(
            configDirectory: baseDirectory,
            configYAML: baseDirectory.appendingPathComponent("config.yaml"),
            credentialsYAML: baseDirectory.appendingPathComponent("credentials.yaml")
        )
    }
}

struct APIToken: Equatable, Sendable {
    var accessToken: String
    var expiresAt: Date?
    var expiresIn: Int?
    var leeway: Int?

    var expiresAtWithLeeway: Date? {
        guard let expiresAt else {
            return nil
        }
        let leewaySeconds = TimeInterval(leeway ?? 0)
        return expiresAt.addingTimeInterval(-leewaySeconds)
    }

    var isExpired: Bool {
        guard let expiresAtWithLeeway else {
            return false
        }
        return Date() >= expiresAtWithLeeway
    }
}

struct ServerCredentials: Equatable, Sendable {
    var url: URL
    var apiToken: APIToken?
    var serverName: String?
    var workspaceName: String?
    var proAPIURL: URL?
    var proDashboardURL: URL?
}

struct ActiveConfigSnapshot: Equatable, Sendable {
    var activeServerURL: URL?
    var activeProjectID: UUID?
    var activeServerCredentials: ServerCredentials?
    var proAPICredentials: ServerCredentials?
    var configError: String?

    static let empty = ActiveConfigSnapshot(
        activeServerURL: nil,
        activeProjectID: nil,
        activeServerCredentials: nil,
        proAPICredentials: nil,
        configError: nil
    )

    var activeServerName: String {
        activeServerCredentials?.serverName ?? activeServerURL?.host ?? "No server configured"
    }

    var activeWorkspaceName: String? {
        activeServerCredentials?.workspaceName
    }

    var normalizedActiveServerKey: String? {
        guard let activeServerURL else {
            return nil
        }
        return ZenMLConfigManager.normalizedURLString(from: activeServerURL)
    }
}

enum ConfigManagerError: LocalizedError {
    case missingConfigFile(String)
    case malformedConfig(String)
    case missingActiveServer
    case missingProToken
    case tokenRefreshRejected(String)
    case tokenRefreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfigFile(let path):
            return "Missing ZenML config file at \(path)."
        case .malformedConfig(let reason):
            return "Malformed ZenML configuration: \(reason)"
        case .missingActiveServer:
            return "No active server configured in ZenML config.yaml."
        case .missingProToken:
            return "Could not find a Pro API token in credentials.yaml for token refresh."
        case .tokenRefreshRejected(let reason):
            return "Token refresh was rejected: \(reason)"
        case .tokenRefreshFailed(let reason):
            return "Token refresh failed: \(reason)"
        }
    }
}

final class ZenMLConfigManager {
    let paths: ZenMLPaths

    private let fileManager: FileManager
    private let urlSession: URLSession
    private let watchQueue = DispatchQueue(label: "io.zenml.menubar.config-watch")
    private let lock = NSLock()

    private var onChange: ((ActiveConfigSnapshot) -> Void)?
    private var directoryFileDescriptor: CInt = -1
    private var watcherSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastEmittedSnapshot: ActiveConfigSnapshot?

    private var inMemoryWorkspaceToken: (serverKey: String, token: APIToken)?

    init(fileManager: FileManager = .default, urlSession: URLSession = .shared) {
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.paths = ZenMLPaths.resolve(fileManager: fileManager)
    }

    deinit {
        stopWatching()
    }

    func loadSnapshot() throws -> ActiveConfigSnapshot {
        guard fileManager.fileExists(atPath: paths.configYAML.path) else {
            throw ConfigManagerError.missingConfigFile(paths.configYAML.path)
        }

        let configYAML = try SimpleYAML.parseFile(at: paths.configYAML)
        let activeServerURL: URL?
        if let serverURLString = SimpleYAML.string(configYAML, path: ["store", "url"]) {
            activeServerURL = URL(string: serverURLString)
        } else {
            activeServerURL = nil
        }

        let activeProjectID: UUID?
        if let projectIDString = SimpleYAML.string(configYAML, path: ["active_project_id"]) {
            activeProjectID = UUID(uuidString: projectIDString)
        } else {
            activeProjectID = nil
        }

        var activeCredentials: ServerCredentials?
        var proCredentials: ServerCredentials?

        if fileManager.fileExists(atPath: paths.credentialsYAML.path) {
            let credentialsYAML = try SimpleYAML.parseFile(at: paths.credentialsYAML)
            let parsedCredentials = parseCredentials(credentialsYAML, activeServerURL: activeServerURL)
            activeCredentials = parsedCredentials.active
            proCredentials = parsedCredentials.pro
        }

        if let activeServerURL,
           let memoryToken = inMemoryToken(for: activeServerURL) {
            if activeCredentials == nil {
                activeCredentials = ServerCredentials(
                    url: activeServerURL,
                    apiToken: memoryToken,
                    serverName: activeServerURL.host,
                    workspaceName: nil,
                    proAPIURL: nil,
                    proDashboardURL: nil
                )
            } else {
                activeCredentials?.apiToken = choosePreferredToken(
                    fileToken: activeCredentials?.apiToken,
                    memoryToken: memoryToken
                )
            }
        }

        return ActiveConfigSnapshot(
            activeServerURL: activeServerURL,
            activeProjectID: activeProjectID,
            activeServerCredentials: activeCredentials,
            proAPICredentials: proCredentials,
            configError: nil
        )
    }

    func startWatching(onChange: @escaping (ActiveConfigSnapshot) -> Void) {
        watchQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.onChange = onChange

            if self.watcherSource != nil {
                self.scheduleReload(delay: 0)
                return
            }

            guard self.fileManager.fileExists(atPath: self.paths.configDirectory.path) else {
                let empty = ActiveConfigSnapshot.empty
                DispatchQueue.main.async {
                    onChange(empty)
                }
                return
            }

            self.directoryFileDescriptor = open(self.paths.configDirectory.path, O_EVTONLY)
            guard self.directoryFileDescriptor >= 0 else {
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: self.directoryFileDescriptor,
                eventMask: [.write, .rename, .delete, .attrib, .extend],
                queue: self.watchQueue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleReload(delay: 0.35)
            }

            source.setCancelHandler { [weak self] in
                guard let self else {
                    return
                }
                if self.directoryFileDescriptor >= 0 {
                    close(self.directoryFileDescriptor)
                    self.directoryFileDescriptor = -1
                }
            }

            self.watcherSource = source
            source.resume()
            self.scheduleReload(delay: 0)
        }
    }

    func stopWatching() {
        watchQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.watcherSource?.cancel()
            self.watcherSource = nil
            self.onChange = nil
            self.lastEmittedSnapshot = nil
        }
    }

    func refreshWorkspaceTokenIfPossible() async throws -> APIToken {
        let snapshot = try loadSnapshot()
        guard let serverURL = snapshot.activeServerURL else {
            throw ConfigManagerError.missingActiveServer
        }

        let defaultProURL = URL(string: "https://cloudapi.zenml.io")
        let proAPIURL = snapshot.activeServerCredentials?.proAPIURL
            ?? snapshot.proAPICredentials?.url
            ?? defaultProURL

        guard let proAPIURL else {
            throw ConfigManagerError.missingProToken
        }

        let proCredentials = snapshot.proAPICredentials
            ?? credentialsForServerURL(from: paths.credentialsYAML, serverURL: proAPIURL)

        guard let proToken = proCredentials?.apiToken?.accessToken, !proToken.isEmpty else {
            throw ConfigManagerError.missingProToken
        }

        let loginURL = serverURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("login", isDirectory: false)

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(proToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=zenml-external".data(using: .utf8)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConfigManagerError.tokenRefreshFailed("Server response was not HTTP.")
            }

            if (200...299).contains(httpResponse.statusCode) {
                let token = try parseTokenExchangeResponse(data)
                cacheInMemoryToken(token, for: serverURL)
                return token
            }

            let body = String(data: data, encoding: .utf8) ?? "<empty body>"
            throw ConfigManagerError.tokenRefreshRejected("HTTP \(httpResponse.statusCode): \(body)")
        } catch let error as ConfigManagerError {
            throw error
        } catch {
            throw ConfigManagerError.tokenRefreshFailed(error.localizedDescription)
        }
    }

    static func normalizedURLString(from url: URL) -> String {
        var absolute = url.absoluteString
        while absolute.hasSuffix("/") {
            absolute.removeLast()
        }
        return absolute.lowercased()
    }

    private func scheduleReload(delay: TimeInterval) {
        debounceWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.reloadSnapshotAndNotify()
        }
        debounceWorkItem = item

        if delay <= 0 {
            watchQueue.async(execute: item)
        } else {
            watchQueue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func reloadSnapshotAndNotify() {
        let snapshot: ActiveConfigSnapshot
        do {
            snapshot = try loadSnapshot()
        } catch {
            snapshot = ActiveConfigSnapshot(
                activeServerURL: nil,
                activeProjectID: nil,
                activeServerCredentials: nil,
                proAPICredentials: nil,
                configError: error.localizedDescription
            )
        }

        guard snapshot != lastEmittedSnapshot else {
            return
        }
        lastEmittedSnapshot = snapshot

        guard let onChange else {
            return
        }

        DispatchQueue.main.async {
            onChange(snapshot)
        }
    }

    private func parseCredentials(_ yaml: [String: Any], activeServerURL: URL?) -> (active: ServerCredentials?, pro: ServerCredentials?) {
        let activeServerKey = activeServerURL.map(Self.normalizedURLString)

        var parsedByKey: [String: ServerCredentials] = [:]
        for (rawKey, rawValue) in yaml {
            guard let entry = rawValue as? [String: Any],
                  let credentials = parseCredentialEntry(rawKey: rawKey, value: entry) else {
                continue
            }
            parsedByKey[Self.normalizedURLString(from: credentials.url)] = credentials
        }

        let active = activeServerKey.flatMap { parsedByKey[$0] }

        let defaultProAPIURL = URL(string: "https://cloudapi.zenml.io")
        let targetProURL = active?.proAPIURL ?? defaultProAPIURL
        let pro: ServerCredentials?
        if let targetProURL {
            pro = parsedByKey[Self.normalizedURLString(from: targetProURL)]
                ?? credentialsForServerURL(from: paths.credentialsYAML, serverURL: targetProURL)
        } else {
            pro = nil
        }

        return (active, pro)
    }

    private func credentialsForServerURL(from path: URL, serverURL: URL) -> ServerCredentials? {
        guard fileManager.fileExists(atPath: path.path),
              let yaml = try? SimpleYAML.parseFile(at: path) else {
            return nil
        }

        let target = Self.normalizedURLString(from: serverURL)
        for (rawKey, rawValue) in yaml {
            guard let entry = rawValue as? [String: Any],
                  let credentials = parseCredentialEntry(rawKey: rawKey, value: entry) else {
                continue
            }
            if Self.normalizedURLString(from: credentials.url) == target {
                return credentials
            }
        }
        return nil
    }

    private func parseCredentialEntry(rawKey: String, value: [String: Any]) -> ServerCredentials? {
        let urlString = (value["url"] as? String) ?? rawKey
        guard let url = URL(string: urlString) else {
            return nil
        }

        let token = parseAPIToken(value["api_token"])
        let serverName = value["server_name"] as? String
        let workspaceName = value["workspace_name"] as? String
        let proAPIURL = (value["pro_api_url"] as? String).flatMap(URL.init(string:))
        let proDashboardURL = (value["pro_dashboard_url"] as? String).flatMap(URL.init(string:))

        return ServerCredentials(
            url: url,
            apiToken: token,
            serverName: serverName,
            workspaceName: workspaceName,
            proAPIURL: proAPIURL,
            proDashboardURL: proDashboardURL
        )
    }

    private func parseAPIToken(_ rawValue: Any?) -> APIToken? {
        guard let tokenMap = rawValue as? [String: Any],
              let accessToken = tokenMap["access_token"] as? String,
              !accessToken.isEmpty else {
            return nil
        }

        let expiresAt = parseISO8601Date(tokenMap["expires_at"] as? String)
        let expiresIn = parseInt(tokenMap["expires_in"])
        let leeway = parseInt(tokenMap["leeway"])

        return APIToken(
            accessToken: accessToken,
            expiresAt: expiresAt,
            expiresIn: expiresIn,
            leeway: leeway
        )
    }

    private func parseTokenExchangeResponse(_ data: Data) throws -> APIToken {
        let decoder = JSONDecoder()
        let response = try decoder.decode(TokenExchangeResponse.self, from: data)

        if let accessToken = response.accessToken, !accessToken.isEmpty {
            let expiresAt: Date?
            if let expiresAtString = response.expiresAt {
                expiresAt = parseISO8601Date(expiresAtString)
            } else if let expiresIn = response.expiresIn {
                expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            } else {
                expiresAt = nil
            }

            return APIToken(
                accessToken: accessToken,
                expiresAt: expiresAt,
                expiresIn: response.expiresIn,
                leeway: response.leeway
            )
        }

        if response.authorizationURL != nil || response.loginURI != nil || response.authURI != nil {
            throw ConfigManagerError.tokenRefreshRejected("Interactive login required. Please run `zenml login` in your terminal.")
        }

        throw ConfigManagerError.tokenRefreshFailed("Token exchange succeeded but no access_token was returned.")
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if let parsed = Self.isoFormatterWithFractional.date(from: value) {
            return parsed
        }
        return Self.isoFormatter.date(from: value)
    }

    private func parseInt(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double {
            return Int(value)
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private func choosePreferredToken(fileToken: APIToken?, memoryToken: APIToken) -> APIToken {
        guard let fileToken else {
            return memoryToken
        }

        if fileToken.isExpired && !memoryToken.isExpired {
            return memoryToken
        }

        switch (fileToken.expiresAt, memoryToken.expiresAt) {
        case (.some(let fileDate), .some(let memoryDate)):
            return memoryDate > fileDate ? memoryToken : fileToken
        case (.none, .some):
            return memoryToken
        default:
            return fileToken
        }
    }

    private func cacheInMemoryToken(_ token: APIToken, for serverURL: URL) {
        let key = Self.normalizedURLString(from: serverURL)
        lock.lock()
        defer { lock.unlock() }
        inMemoryWorkspaceToken = (serverKey: key, token: token)
    }

    private func inMemoryToken(for serverURL: URL) -> APIToken? {
        lock.lock()
        defer { lock.unlock() }

        let key = Self.normalizedURLString(from: serverURL)
        guard let cached = inMemoryWorkspaceToken, cached.serverKey == key else {
            return nil
        }
        return cached.token
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct TokenExchangeResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let expiresAt: String?
    let leeway: Int?
    let loginURI: String?
    let authURI: String?
    let authorizationURL: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case leeway
        case loginURI = "login_uri"
        case authURI = "auth_uri"
        case authorizationURL = "authorization_url"
    }
}
