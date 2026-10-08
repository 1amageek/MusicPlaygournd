import Foundation

struct DocumentSnapshot: Sendable {
    let url: URL
    let source: String
    let isReadOnly: Bool
}
