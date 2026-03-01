import Foundation

enum RunStatus: Hashable, Codable, Sendable {
    case initializing
    case provisioning
    case running
    case failed
    case completed
    case cached
    case retrying
    case retried
    case stopped
    case stopping
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "initializing": self = .initializing
        case "provisioning": self = .provisioning
        case "running": self = .running
        case "failed": self = .failed
        case "completed": self = .completed
        case "cached": self = .cached
        case "retrying": self = .retrying
        case "retried": self = .retried
        case "stopped": self = .stopped
        case "stopping": self = .stopping
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .initializing: return "initializing"
        case .provisioning: return "provisioning"
        case .running: return "running"
        case .failed: return "failed"
        case .completed: return "completed"
        case .cached: return "cached"
        case .retrying: return "retrying"
        case .retried: return "retried"
        case .stopped: return "stopped"
        case .stopping: return "stopping"
        case .unknown(let value): return value
        }
    }

    var displayName: String {
        switch self {
        case .initializing: return "Initializing"
        case .provisioning: return "Provisioning"
        case .running: return "Running"
        case .failed: return "Failed"
        case .completed: return "Completed"
        case .cached: return "Cached"
        case .retrying: return "Retrying"
        case .retried: return "Retried"
        case .stopped: return "Stopped"
        case .stopping: return "Stopping"
        case .unknown(let raw): return raw.capitalized
        }
    }

    var isInProgressStatus: Bool {
        switch self {
        case .initializing, .provisioning, .running, .retrying, .stopping:
            return true
        default:
            return false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RunStatus(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
