import Foundation

public struct SourceDiagnostic: Sendable, Equatable, Identifiable {
    public let range: NSRange
    public let line: Int
    public let column: Int
    public let message: String
    public var id: String { "\(range.location):\(message)" }
    public init(range: NSRange, line: Int, column: Int, message: String) {
        self.range = range; self.line = line; self.column = column; self.message = message
    }
}
