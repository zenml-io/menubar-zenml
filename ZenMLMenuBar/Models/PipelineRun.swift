import Foundation

struct PipelineRun: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let pipelineName: String?
    let status: RunStatus
    let inProgress: Bool
    let createdAt: Date?
    let startTime: Date?
    let endTime: Date?
    let projectID: UUID?
    let projectName: String?

    var title: String {
        if let pipelineName, !pipelineName.isEmpty {
            return pipelineName
        }
        return name
    }

    var isFailed: Bool {
        status == .failed
    }

    var ageText: String {
        guard let referenceDate = startTime ?? createdAt else {
            return "Just now"
        }
        return PipelineRun.relativeFormatter.localizedString(for: referenceDate, relativeTo: Date())
    }

    var durationText: String {
        guard let startTime else {
            return "—"
        }
        let end = endTime ?? Date()
        let duration = max(0, end.timeIntervalSince(startTime))

        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
