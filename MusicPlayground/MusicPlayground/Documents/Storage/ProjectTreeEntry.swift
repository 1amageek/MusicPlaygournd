import Foundation

struct ProjectTreeEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
}
