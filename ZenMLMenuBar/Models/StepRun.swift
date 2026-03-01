import Foundation

struct StepRun: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let status: RunStatus
    let startTime: Date?
    let endTime: Date?

    var duration: TimeInterval? {
        guard let startTime, let endTime else {
            return nil
        }
        return max(0, endTime.timeIntervalSince(startTime))
    }

    var durationText: String {
        guard let duration else {
            return ""
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
