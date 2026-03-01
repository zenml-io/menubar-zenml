import Foundation
import UserNotifications

actor NotificationManager {
    private let center: UNUserNotificationCenter
    private var didRequestAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else {
            return
        }
        didRequestAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyRunFailed(
        run: PipelineRun,
        serverName: String?,
        projectName: String?,
        failedStepName: String?
    ) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "ZenML pipeline failed"

        let trimmedFailedStepName = failedStepName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureLead = if let trimmedFailedStepName, !trimmedFailedStepName.isEmpty {
            "\(run.title) failed at step '\(trimmedFailedStepName)'"
        } else {
            "\(run.title) failed"
        }

        var pieces = [failureLead]
        if let projectName, !projectName.isEmpty {
            pieces.append("Project: \(projectName)")
        }
        if let serverName, !serverName.isEmpty {
            pieces.append("Server: \(serverName)")
        }
        content.body = pieces.joined(separator: " • ")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "zenml-run-failed-\(run.id.uuidString)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}
