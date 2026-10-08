public protocol SwiftSourceAnalyzing: Sendable {
    func analyze(source: String) async throws -> SourceAnalysis
    func format(source: String) async throws -> String
}
