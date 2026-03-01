import Foundation

struct ZenMLProject: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    let name: String
}
