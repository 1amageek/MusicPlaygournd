public struct SourceAnalysis: Sendable, Equatable {
    public let tokens: [SyntaxToken]
    public let diagnostics: [SourceDiagnostic]
    public let symbols: [String]
    public init(tokens: [SyntaxToken], diagnostics: [SourceDiagnostic], symbols: [String] = []) {
        self.tokens = tokens; self.diagnostics = diagnostics; self.symbols = symbols
    }
}
