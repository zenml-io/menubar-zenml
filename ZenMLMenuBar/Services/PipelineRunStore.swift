import AppKit
import Foundation
import Observation

enum ConnectionState: Equatable, Sendable {
    case loading
    case connected
    case staleRefreshing
    case empty
    case disconnected(reason: String, retryAfter: TimeInterval)
    case serverError(reason: String, retryAfter: TimeInterval)
}

@MainActor
@Observable
final class PipelineRunStore {
    var connectionState: ConnectionState = .loading
    var runs: [PipelineRun] = []
    var cachedRuns: [PipelineRun] = []
    var lastRefreshedAt: Date?

    var serverName: String = "No server configured"
    var projectName: String = "No project"
    var workspaceName: String?

    var isRefreshing: Bool = false

    var unacknowledgedFailedRunIDs: Set<UUID> = []
    var hasUnacknowledgedFailures: Bool {
        !unacknowledgedFailedRunIDs.isEmpty
    }

    var displayedRuns: [PipelineRun] {
        runs.isEmpty ? cachedRuns : runs
    }

    var inProgressRuns: [PipelineRun] {
        displayedRuns.filter { $0.inProgress }
    }

    var failedRuns: [PipelineRun] {
        displayedRuns.filter { !$0.inProgress && $0.status == .failed }
    }

    var recentRuns: [PipelineRun] {
        displayedRuns.filter { !$0.inProgress && $0.status != .failed }
    }

    var shouldDimRunList: Bool {
        switch connectionState {
        case .staleRefreshing, .disconnected:
            return true
        default:
            return false
        }
    }

    var isDisconnected: Bool {
        switch connectionState {
        case .disconnected:
            return true
        default:
            return false
        }
    }

    var isServerError: Bool {
        switch connectionState {
        case .serverError:
            return true
        default:
            return false
        }
    }

    var connectionReason: String? {
        switch connectionState {
        case .disconnected(let reason, _), .serverError(let reason, _):
            return reason
        default:
            return nil
        }
    }

    var shouldShowRefreshingOverlay: Bool {
        connectionState == .staleRefreshing
    }

    var bannerText: String? {
        switch connectionState {
        case .disconnected(_, let retryAfter):
            return "Disconnected — retrying in \(Int(retryAfter))s..."
        default:
            return nil
        }
    }

    var footerText: String {
        switch connectionState {
        case .staleRefreshing:
            return "Refreshing..."
        case .disconnected:
            return "Disconnected"
        case .serverError:
            return "Error — retrying..."
        case .loading:
            return "Loading..."
        case .connected, .empty:
            guard let lastRefreshedAt else {
                return "Waiting for first refresh..."
            }
            return "Last refreshed \(Self.relativeFormatter.localizedString(for: lastRefreshedAt, relativeTo: Date()))"
        }
    }

    private let configManager: ZenMLConfigManager
    private let apiClient: ZenMLAPIClient
    private let notificationManager: NotificationManager

    private var started = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pollingTask: Task<Void, Never>?

    private var knownFailedRunIDs: Set<UUID> = []
    private var previousHadInProgressRuns = false
    private var pendingFastPollAt: Date?
    private var nextPollInterval: TimeInterval = 180

    private var currentSnapshot: ActiveConfigSnapshot?
    private var lastResolvedProjectID: UUID?

    init(
        configManager: ZenMLConfigManager = ZenMLConfigManager(),
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.configManager = configManager
        self.notificationManager = notificationManager
        self.apiClient = ZenMLAPIClient(configManager: configManager)
    }

    func startIfNeeded() {
        guard !started else {
            return
        }
        started = true

        Task {
            await notificationManager.requestAuthorizationIfNeeded()
        }

        beginWatchingConfig()

        Task {
            await refreshNow(trigger: .initial)
        }

        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }

    func acknowledgeFailures() {
        unacknowledgedFailedRunIDs.removeAll()
    }

    func openRunInDashboard(_ run: PipelineRun) {
        guard let url = dashboardURL(for: run) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func dashboardURL(for run: PipelineRun) -> URL? {
        guard let snapshot = currentSnapshot else {
            return nil
        }

        let runID = run.id.uuidString.lowercased()
        let projectID = run.projectID?.uuidString.lowercased()
            ?? snapshot.activeProjectID?.uuidString.lowercased()

        if let proDashboardURL = snapshot.activeServerCredentials?.proDashboardURL {
            if let workspaceName = snapshot.activeServerCredentials?.workspaceName,
               let projectID {
                return proDashboardURL
                    .appendingPathComponent("workspaces", isDirectory: true)
                    .appendingPathComponent(workspaceName, isDirectory: true)
                    .appendingPathComponent("projects", isDirectory: true)
                    .appendingPathComponent(projectID, isDirectory: true)
                    .appendingPathComponent("runs", isDirectory: true)
                    .appendingPathComponent(runID, isDirectory: false)
            }

            if let projectID {
                return proDashboardURL
                    .appendingPathComponent("projects", isDirectory: true)
                    .appendingPathComponent(projectID, isDirectory: true)
                    .appendingPathComponent("runs", isDirectory: true)
                    .appendingPathComponent(runID, isDirectory: false)
            }
        }

        guard let serverURL = snapshot.activeServerURL else {
            return nil
        }

        guard let fallbackProjectName = run.projectName,
              !fallbackProjectName.isEmpty else {
            return nil
        }

        return serverURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(fallbackProjectName, isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: false)
    }

    private func beginWatchingConfig() {
        configManager.startWatching { [weak self] snapshot in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.applySnapshot(snapshot)
                await self.refreshNow(trigger: .configChanged)
            }
        }

        if let snapshot = try? configManager.loadSnapshot() {
            applySnapshot(snapshot)
        }
    }

    private func applySnapshot(_ snapshot: ActiveConfigSnapshot) {
        currentSnapshot = snapshot
        serverName = snapshot.activeServerName
        workspaceName = snapshot.activeWorkspaceName

        if let activeProjectID = snapshot.activeProjectID {
            if lastResolvedProjectID != activeProjectID {
                projectName = "Project \(activeProjectID.uuidString.prefix(8))"
            }
        } else {
            projectName = "All projects"
            lastResolvedProjectID = nil
        }

        if let configError = snapshot.configError {
            connectionState = .disconnected(reason: configError, retryAfter: 30)
        }
    }

    private func pollingLoop() async {
        while !Task.isCancelled {
            let sleepDuration = computeSleepDuration()
            if sleepDuration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
            }
            await refreshNow(trigger: .poll)
        }
    }

    private func computeSleepDuration() -> TimeInterval {
        if let pendingFastPollAt {
            let remaining = pendingFastPollAt.timeIntervalSinceNow
            if remaining <= 0 {
                self.pendingFastPollAt = nil
                return nextPollInterval
            }
            return min(nextPollInterval, remaining)
        }
        return nextPollInterval
    }

    private enum RefreshTrigger {
        case initial
        case poll
        case configChanged
        case queued
    }

    private func refreshNow(trigger: RefreshTrigger) async {
        if refreshInFlight {
            pendingRefresh = true
            return
        }

        refreshInFlight = true
        defer {
            refreshInFlight = false
            if pendingRefresh {
                pendingRefresh = false
                Task { @MainActor [weak self] in
                    await self?.refreshNow(trigger: .queued)
                }
            }
        }

        if !displayedRuns.isEmpty {
            cachedRuns = displayedRuns
            switch connectionState {
            case .connected, .empty, .loading, .staleRefreshing:
                connectionState = .staleRefreshing
            case .disconnected, .serverError:
                break
            }
        }
        isRefreshing = true

        defer {
            isRefreshing = false
        }

        do {
            let snapshot = try configManager.loadSnapshot()
            applySnapshot(snapshot)

            guard snapshot.activeServerURL != nil else {
                connectionState = .disconnected(reason: "No active ZenML server configured.", retryAfter: 30)
                nextPollInterval = 30
                return
            }

            guard let token = snapshot.activeServerCredentials?.apiToken,
                  !token.accessToken.isEmpty else {
                connectionState = .disconnected(reason: "No access token found. Run `zenml login`.", retryAfter: 30)
                nextPollInterval = 30
                return
            }
            _ = try await apiClient.fetchCurrentUser()
            let refreshedRuns = try await apiClient.fetchRuns(projectID: snapshot.activeProjectID, limit: 20)

            if let activeProjectID = snapshot.activeProjectID,
               lastResolvedProjectID != activeProjectID,
               let resolvedProjectName = try? await apiClient.fetchProjectName(projectID: activeProjectID),
               !resolvedProjectName.isEmpty {
                projectName = resolvedProjectName
                lastResolvedProjectID = activeProjectID
            }

            processFailureTransitions(using: refreshedRuns)

            runs = refreshedRuns
            cachedRuns = refreshedRuns
            lastRefreshedAt = Date()
            connectionState = refreshedRuns.isEmpty ? .empty : .connected

            let hasActiveRuns = refreshedRuns.contains { $0.inProgress }
            if previousHadInProgressRuns && !hasActiveRuns {
                pendingFastPollAt = Date().addingTimeInterval(5)
            }
            previousHadInProgressRuns = hasActiveRuns
            nextPollInterval = hasActiveRuns ? 15 : 180
        } catch let error as APIClientError {
            switch error {
            case .serverError(let code):
                connectionState = .serverError(reason: "HTTP \(code)", retryAfter: 30)
                nextPollInterval = 30
            case .transport(let message):
                connectionState = .disconnected(reason: message, retryAfter: 30)
                nextPollInterval = 30
            case .unauthorized(let message), .notConfigured(let message):
                connectionState = .disconnected(reason: message, retryAfter: 30)
                nextPollInterval = 30
            case .httpError(let code, let body):
                connectionState = .serverError(reason: "HTTP \(code): \(body)", retryAfter: 30)
                nextPollInterval = 30
            case .decodingFailed(let message):
                connectionState = .serverError(reason: message, retryAfter: 30)
                nextPollInterval = 30
            }
        } catch {
            connectionState = .disconnected(reason: error.localizedDescription, retryAfter: 30)
            nextPollInterval = 30
        }
    }

    private func processFailureTransitions(using refreshedRuns: [PipelineRun]) {
        let runIDs = Set(refreshedRuns.map(\.id))
        knownFailedRunIDs.formIntersection(runIDs)
        unacknowledgedFailedRunIDs.formIntersection(runIDs)

        for run in refreshedRuns where run.isFailed {
            guard !knownFailedRunIDs.contains(run.id) else {
                continue
            }

            knownFailedRunIDs.insert(run.id)
            unacknowledgedFailedRunIDs.insert(run.id)

            Task {
                await notificationManager.notifyRunFailed(
                    run: run,
                    serverName: serverName,
                    projectName: projectName
                )
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
