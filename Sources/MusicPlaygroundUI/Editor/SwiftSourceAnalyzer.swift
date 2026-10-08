import Foundation
import SwiftParser
import SwiftSyntax
import SwiftIDEUtils
import SwiftParserDiagnostics
import SwiftBasicFormat

/// Native syntax analysis; it does not evaluate or type-check source.
public struct SwiftSourceAnalyzer: SwiftSourceAnalyzing {
    private let importedTypes: Set<String>
    public init(importedTypes: Set<String> = []) { self.importedTypes = importedTypes }

    public func analyze(source: String) async throws -> SourceAnalysis {
        let types = importedTypes
        let work = Task.detached(priority: .userInitiated) { try Self.analyze(source, importedTypes: types) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    public func format(source: String) async throws -> String {
        let work = Task.detached(priority: .userInitiated) {
            try Self.admit(source)
            let tree = Parser.parse(source: source)
            guard ParseDiagnosticsGenerator.diagnostics(for: tree).isEmpty else { throw SourceAnalysisError.invalidSyntax }
            let result = BasicFormat(indentationWidth: .spaces(4)).rewrite(tree).description
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    private static func admit(_ source: String) throws {
        try Task.checkCancellation()
        guard source.utf8.count <= 2 * 1024 * 1024 else { throw SourceAnalysisError.sourceTooLarge }
    }

    private static func analyze(_ source: String, importedTypes: Set<String>) throws -> SourceAnalysis {
        try admit(source)
        let tree = Parser.parse(source: source)
        // One bounded UTF-8 -> UTF-16 boundary map; parser offsets never index a String by grapheme.
        var offsets = [Int](repeating: -1, count: source.utf8.count + 1)
        var byte = 0, utf16 = 0
        offsets[0] = 0
        for scalar in source.unicodeScalars {
            byte += scalar.utf8.count; utf16 += scalar.utf16.count
            offsets[byte] = utf16
        }
        func range(_ start: Int, _ end: Int) throws -> NSRange {
            guard start >= 0, end >= start, end < offsets.count,
                  offsets[start] >= 0, offsets[end] >= 0 else { throw SourceAnalysisError.invalidParserRange }
            return NSRange(location: offsets[start], length: offsets[end] - offsets[start])
        }
        var tokens: [SyntaxToken] = []
        for classification in tree.classifications {
            let kind: String
            switch classification.kind {
            case .keyword, .ifConfigDirective: kind = "keyword"
            case .type: kind = "type"
            case .stringLiteral: kind = "string"
            case .regexLiteral: kind = "regexp"
            case .integerLiteral, .floatLiteral: kind = "number"
            case .lineComment, .blockComment, .docLineComment, .docBlockComment: kind = "comment"
            case .attribute: kind = "decorator"
            case .identifier, .dollarIdentifier, .argumentLabel: kind = "property"
            default: continue
            }
            tokens.append(.init(range: try range(classification.range.lowerBound.utf8Offset,
                                                classification.range.upperBound.utf8Offset), kind: kind))
        }
        let syntaxTokens = tree.tokens(viewMode: .sourceAccurate)
        var types = importedTypes
        var symbols = importedTypes
        for token in syntaxTokens {
            if isTypeName(token) { types.insert(token.text); symbols.insert(token.text) }
            if let pattern = token.parent?.as(IdentifierPatternSyntax.self), pattern.identifier == token {
                symbols.insert(token.text)
            }
            if let decl = token.parent?.as(FunctionDeclSyntax.self), decl.name == token {
                symbols.insert(token.text)
            }
        }
        // AST roles override generic identifiers; imported type names are supplied by the caller.
        for token in tree.tokens(viewMode: .sourceAccurate) {
            guard case .identifier = token.tokenKind else { continue }
            var kind: String?
            if isTypeName(token) || types.contains(token.text) { kind = "type" }
            else if let decl = token.parent?.as(FunctionDeclSyntax.self), decl.name == token { kind = "function" }
            else {
                var node = token.parent
                while let current = node {
                    if let call = current.as(FunctionCallExprSyntax.self) {
                        if call.calledExpression.lastToken(viewMode: .sourceAccurate) == token { kind = "function" }
                        break
                    }
                    if current.is(LabeledExprSyntax.self) || current.is(CodeBlockItemSyntax.self) { break }
                    node = current.parent
                }
            }
            if let kind {
                tokens.append(.init(range: try range(token.positionAfterSkippingLeadingTrivia.utf8Offset,
                                                     token.endPositionBeforeTrailingTrivia.utf8Offset), kind: kind))
            }
        }
        let converter = SourceLocationConverter(fileName: "", tree: tree)
        let diagnostics = try ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
            let location = diagnostic.location(converter: converter)
            let offset = diagnostic.position.utf8Offset
            return SourceDiagnostic(range: try range(offset, offset), line: location.line,
                                    column: location.column, message: diagnostic.message)
        }
        try Task.checkCancellation()
        return SourceAnalysis(tokens: tokens, diagnostics: diagnostics, symbols: symbols.filter { $0 != "_" }.sorted())
    }

    private static func isTypeName(_ token: TokenSyntax) -> Bool {
        guard let parent = token.parent else { return false }
        if let node = parent.as(StructDeclSyntax.self) { return node.name == token }
        if let node = parent.as(ClassDeclSyntax.self) { return node.name == token }
        if let node = parent.as(EnumDeclSyntax.self) { return node.name == token }
        if let node = parent.as(ActorDeclSyntax.self) { return node.name == token }
        if let node = parent.as(ProtocolDeclSyntax.self) { return node.name == token }
        if let node = parent.as(TypeAliasDeclSyntax.self) { return node.name == token }
        return false
    }
}
