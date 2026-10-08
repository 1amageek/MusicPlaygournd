import Foundation

public enum SourceAnalysisError: Error, LocalizedError, Sendable, Equatable {
    case sourceTooLarge
    case invalidParserRange
    case invalidSyntax
    public var errorDescription: String? {
        switch self {
        case .sourceTooLarge: "Syntax analysis supports at most 2 MiB of source; the document is retained."
        case .invalidParserRange: "The syntax parser returned an invalid source range."
        case .invalidSyntax: "Resolve the parsing diagnostics before formatting the source."
        }
    }
}
