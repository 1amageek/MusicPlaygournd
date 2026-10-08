import Foundation

public struct SyntaxToken: Sendable, Equatable {
    public let range: NSRange
    public let kind: String
    public init(range: NSRange, kind: String) { self.range = range; self.kind = kind }
}
