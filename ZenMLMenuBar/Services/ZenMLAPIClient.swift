import Foundation

enum APIClientError: LocalizedError {
    case notConfigured(String)
    case unauthorized(String)
    case serverError(Int)
    case httpError(Int, String)
    case decodingFailed(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return message
        case .unauthorized(let message):
            return message
        case .serverError(let statusCode):
            return "ZenML server returned HTTP \(statusCode)."
        case .httpError(let statusCode, let body):
            return "ZenML request failed with HTTP \(statusCode): \(body)"
        case .decodingFailed(let message):
            return "Failed to decode ZenML response: \(message)"
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}

struct CurrentUserDTO: Decodable, Sendable {
    let id: UUID?
    let name: String?
    let email: String?
    let body: Body?

    struct Body: Decodable, Sendable {
        let name: String?
        let fullName: String?
        let email: String?

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case email
        }
    }
}

actor ZenMLAPIClient {
    private let configManager: ZenMLConfigManager
    private let session: URLSession
    private let decoder: JSONDecoder

    private var tokenRefreshTask: Task<APIToken, Error>?

    init(configManager: ZenMLConfigManager, session: URLSession = .shared) {
        self.configManager = configManager
        self.session = session
        self.decoder = ZenMLAPIClient.makeDecoder()
    }

    func fetchCurrentUser() async throws -> CurrentUserDTO {
        let data = try await authenticatedData(
            path: "current-user",
            queryItems: [],
            allowRetryOnUnauthorized: true
        )

        do {
            return try decoder.decode(CurrentUserDTO.self, from: data)
        } catch {
            throw APIClientError.decodingFailed(error.localizedDescription)
        }
    }

    func fetchRuns(projectID: UUID?, limit: Int = 20) async throws -> [PipelineRun] {
        var queryItems: [URLQueryItem] = [
            .init(name: "sort_by", value: "desc:created"),
            .init(name: "size", value: String(limit)),
            .init(name: "hydrate", value: "false")
        ]

        if let projectID {
            queryItems.append(.init(name: "project", value: projectID.uuidString.lowercased()))
        }

        let data = try await authenticatedData(
            path: "runs",
            queryItems: queryItems,
            allowRetryOnUnauthorized: true
        )

        do {
            let page = try decoder.decode(PageDTO<RunDTO>.self, from: data)
            let mappedRuns = page.items.map(mapRun)
            return mappedRuns.sorted { lhs, rhs in
                let lhsWeight = sectionSortWeight(for: lhs)
                let rhsWeight = sectionSortWeight(for: rhs)
                if lhsWeight != rhsWeight {
                    return lhsWeight < rhsWeight
                }

                let lhsDate = lhs.startTime ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.startTime ?? rhs.createdAt ?? .distantPast
                return lhsDate > rhsDate
            }
        } catch {
            throw APIClientError.decodingFailed(error.localizedDescription)
        }
    }

    func fetchProjectName(projectID: UUID) async throws -> String? {
        let data = try await authenticatedData(
            path: "projects",
            queryItems: [
                .init(name: "size", value: "200"),
                .init(name: "hydrate", value: "false")
            ],
            allowRetryOnUnauthorized: true
        )

        do {
            let page = try decoder.decode(PageDTO<ProjectDTO>.self, from: data)
            if let project = page.items.first(where: { $0.id == projectID }) {
                return project.resolvedName
            }
        } catch {
            throw APIClientError.decodingFailed(error.localizedDescription)
        }

        do {
            let direct = try await authenticatedData(
                path: "projects/\(projectID.uuidString.lowercased())",
                queryItems: [],
                allowRetryOnUnauthorized: true
            )
            let project = try decoder.decode(ProjectDTO.self, from: direct)
            return project.resolvedName
        } catch {
            return nil
        }
    }

    private func authenticatedData(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        allowRetryOnUnauthorized: Bool
    ) async throws -> Data {
        let snapshot = try configManager.loadSnapshot()

        guard let serverURL = snapshot.activeServerURL else {
            throw APIClientError.notConfigured("No active ZenML server configured.")
        }

        guard let accessToken = snapshot.activeServerCredentials?.apiToken?.accessToken,
              !accessToken.isEmpty else {
            throw APIClientError.notConfigured("No workspace access token found. Run `zenml login` first.")
        }

        let endpointURL = try makeEndpointURL(
            baseURL: serverURL,
            path: "api/v1/\(path)",
            queryItems: queryItems
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIClientError.transport("Unexpected non-HTTP response.")
            }

            if httpResponse.statusCode == 401 {
                guard allowRetryOnUnauthorized else {
                    throw APIClientError.unauthorized("Authentication failed. Please run `zenml login` again.")
                }
                _ = try await refreshTokenWithGate()
                return try await authenticatedData(
                    path: path,
                    queryItems: queryItems,
                    method: method,
                    body: body,
                    headers: headers,
                    allowRetryOnUnauthorized: false
                )
            }

            if (500...599).contains(httpResponse.statusCode) {
                throw APIClientError.serverError(httpResponse.statusCode)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<empty body>"
                throw APIClientError.httpError(httpResponse.statusCode, responseBody)
            }

            return data
        } catch let error as APIClientError {
            throw error
        } catch let error as URLError {
            throw APIClientError.transport(error.localizedDescription)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
    }

    private func refreshTokenWithGate() async throws -> APIToken {
        if let tokenRefreshTask {
            return try await tokenRefreshTask.value
        }

        let task = Task {
            try await configManager.refreshWorkspaceTokenIfPossible()
        }
        tokenRefreshTask = task

        defer {
            tokenRefreshTask = nil
        }

        return try await task.value
    }

    private func makeEndpointURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        var resolvedURL = baseURL
        for component in path.split(separator: "/") {
            resolvedURL.appendPathComponent(String(component), isDirectory: false)
        }

        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.transport("Could not construct endpoint URL.")
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let finalURL = components.url else {
            throw APIClientError.transport("Could not finalize endpoint URL.")
        }

        return finalURL
    }

    private func mapRun(_ dto: RunDTO) -> PipelineRun {
        let body = dto.body
        let metadata = body?.metadata ?? dto.metadata

        let statusRaw = body?.status ?? dto.status ?? "unknown"
        let status = RunStatus(rawValue: statusRaw)
        let inProgress = body?.inProgress ?? dto.inProgress ?? status.isInProgressStatus

        let resolvedPipelineName = body?.pipeline?.name
            ?? dto.pipeline?.name
            ?? dto.resources?.pipeline?.name
            ?? body?.pipelineName

        let resolvedName = body?.name
            ?? dto.name
            ?? resolvedPipelineName
            ?? "Run \(dto.id.uuidString.prefix(8))"

        let projectID = body?.project?.id
            ?? dto.project?.id
            ?? body?.projectID
            ?? dto.resources?.project?.id
        let projectName = body?.project?.name
            ?? dto.project?.name
            ?? dto.resources?.project?.name

        return PipelineRun(
            id: dto.id,
            name: resolvedName,
            pipelineName: resolvedPipelineName,
            status: status,
            inProgress: inProgress,
            createdAt: body?.created ?? dto.created ?? metadata?.created,
            startTime: body?.startTime ?? dto.startTime ?? metadata?.startTime,
            endTime: body?.endTime ?? dto.endTime ?? metadata?.endTime,
            projectID: projectID,
            projectName: projectName
        )
    }

    private func sectionSortWeight(for run: PipelineRun) -> Int {
        if run.inProgress { return 0 }
        if run.status == .failed { return 1 }
        return 2
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            if let date = parseServerDate(raw) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(raw)"
            )
        }
        return decoder
    }

    private static func parseServerDate(_ raw: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: raw) {
            return date
        }
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        if let date = localTimestampFormatterWithFractional.date(from: raw) {
            return date
        }
        if let date = localTimestampFormatter.date(from: raw) {
            return date
        }
        return nil
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

    private static let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let localTimestampFormatterWithFractional: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()
}

private struct PageDTO<Item: Decodable>: Decodable {
    let items: [Item]
}

private struct RunDTO: Decodable {
    let id: UUID
    let name: String?
    let status: String?
    let inProgress: Bool?
    let created: Date?
    let startTime: Date?
    let endTime: Date?
    let pipeline: NamedEntityDTO?
    let project: NamedEntityDTO?
    let resources: RunResourcesDTO?
    let metadata: RunMetadataDTO?
    let body: RunBodyDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case inProgress = "in_progress"
        case created
        case startTime = "start_time"
        case endTime = "end_time"
        case pipeline
        case project
        case resources
        case metadata
        case body
    }
}

private struct RunBodyDTO: Decodable {
    let name: String?
    let status: String?
    let inProgress: Bool?
    let created: Date?
    let startTime: Date?
    let endTime: Date?
    let pipeline: NamedEntityDTO?
    let project: NamedEntityDTO?
    let projectID: UUID?
    let metadata: RunMetadataDTO?
    let pipelineName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case inProgress = "in_progress"
        case created
        case startTime = "start_time"
        case endTime = "end_time"
        case pipeline
        case project
        case projectID = "project_id"
        case metadata
        case pipelineName = "pipeline_name"
    }
}

private struct RunResourcesDTO: Decodable {
    let pipeline: NamedEntityDTO?
    let project: NamedEntityDTO?
}

private struct RunMetadataDTO: Decodable {
    let created: Date?
    let startTime: Date?
    let endTime: Date?

    enum CodingKeys: String, CodingKey {
        case created
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

private struct NamedEntityDTO: Decodable {
    let id: UUID?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let raw = try? singleValueContainer.decode(String.self) {
            self.id = UUID(uuidString: raw)
            self.name = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

private struct ProjectDTO: Decodable {
    let id: UUID
    let name: String?
    let body: Body?

    struct Body: Decodable {
        let name: String?
    }

    var resolvedName: String? {
        body?.name ?? name
    }
}
