import Foundation

struct ProjectTarget: Identifiable, Equatable, Sendable {
    let name: String
    let sourceDirectory: URL
    var id: String { name }
}
