import Foundation

enum ServerConnectionHealth: Equatable, Sendable {
    case connected
    case disconnected
    case serverError
}

struct ServerConnection: Equatable, Sendable {
    let url: URL
    let serverName: String?
    let workspaceName: String?
    let proDashboardURL: URL?
    let projectID: UUID?
    let projectName: String?
    let health: ServerConnectionHealth
}
