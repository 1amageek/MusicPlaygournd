import Foundation

/// One compiler-classified token in the exact caller-owned UTF-16 source snapshot.
public struct SwiftSemanticToken: Sendable, Equatable {
    public let range: NSRange
    public let kind: String
    public let modifiers: Set<String>

    public init(range: NSRange, kind: String, modifiers: Set<String> = []) {
        self.range = range
        self.kind = kind
        self.modifiers = modifiers
    }

    static var capabilities: [String: Any] {
        ["textDocument": [
            "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
            "completion": ["completionItem": ["snippetSupport": true]],
            "semanticTokens": [
                "requests": ["full": true], "formats": ["relative"],
                "tokenTypes": ["namespace", "type", "class", "actor", "enum", "interface", "struct", "typeParameter",
                               "parameter", "variable", "property", "enumMember", "function", "method", "macro",
                               "keyword", "modifier", "comment", "string", "number", "regexp", "operator", "decorator", "identifier"],
                "tokenModifiers": ["declaration", "definition", "readonly", "static", "deprecated", "defaultLibrary"],
                "overlappingTokenSupport": true, "multilineTokenSupport": false
            ]
        ]]
    }

    static func legend(_ data: Data) throws -> (types: [String], modifiers: [String]) {
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = response?["result"] as? [String: Any]
        let capabilities = result?["capabilities"] as? [String: Any]
        let provider = capabilities?["semanticTokensProvider"] as? [String: Any]
        guard let legend = provider?["legend"] as? [String: Any],
              let types = legend["tokenTypes"] as? [String], !types.isEmpty,
              let modifiers = legend["tokenModifiers"] as? [String], modifiers.count < 32 else {
            throw SwiftCompletionError.protocolError("SourceKit-LSP does not provide a valid semantic token legend.")
        }
        return (types, modifiers)
    }

    /// SourceKit semantic tokens classify references; document symbols classify declarations.
    static func declarations(_ data: Data, source: String, prefix: String = "") throws -> [Self] {
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let symbols = response?["result"] as? [[String: Any]] else {
            throw SwiftCompletionError.malformedResponse("Invalid document symbols.")
        }
        let document = (prefix + source) as NSString
        var lineStarts = [0]
        for index in 0..<document.length where document.character(at: index) == 10 { lineStarts.append(index + 1) }
        func offset(_ position: [String: Int]) throws -> Int {
            guard let line = position["line"], let column = position["character"],
                  line >= 0, line < lineStarts.count, column >= 0 else {
                throw SwiftCompletionError.malformedResponse("Invalid document symbol position.")
            }
            let end = line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : document.length
            guard column <= end - lineStarts[line] else { throw SwiftCompletionError.malformedResponse("Symbol exceeds its line.") }
            return lineStarts[line] + column
        }
        let kinds = [2: "namespace", 5: "class", 6: "method", 7: "property", 8: "property", 9: "method",
                     10: "enum", 11: "interface", 12: "function", 13: "variable", 14: "variable", 22: "enumMember", 23: "struct", 26: "typeParameter"]
        var pending = symbols
        var result: [Self] = []
        while let symbol = pending.popLast() {
            if let children = symbol["children"] as? [[String: Any]] { pending.append(contentsOf: children) }
            guard let number = symbol["kind"] as? Int else { throw SwiftCompletionError.malformedResponse("Missing symbol kind.") }
            guard let kind = kinds[number] else { continue }
            guard let selection = symbol["selectionRange"] as? [String: [String: Int]],
                  let first = selection["start"], let last = selection["end"] else {
                throw SwiftCompletionError.malformedResponse("Missing symbol selection range.")
            }
            let start = try offset(first), end = try offset(last)
            guard end >= start else { throw SwiftCompletionError.malformedResponse("Reversed symbol range.") }
            for boundary in [start, end] where boundary < document.length {
                guard !(0xDC00...0xDFFF).contains(document.character(at: boundary)) else {
                    throw SwiftCompletionError.malformedResponse("Symbol splits a UTF-16 surrogate pair.")
                }
            }
            if end <= prefix.utf16.count { continue }
            let range = NSRange(location: start - prefix.utf16.count, length: end - start)
            guard range.location >= 0, range.length >= 0, Range(range, in: source) != nil else {
                throw SwiftCompletionError.malformedResponse("Invalid document symbol range.")
            }
            if range.length > 0 { result.append(Self(range: range, kind: kind, modifiers: ["declaration"])) }
        }
        return result
    }

    static func decode(_ data: Data, source: String, prefix: String = "", types: [String], modifiers: [String]) throws -> [Self] {
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = response?["result"] as? [String: Any], let values = result["data"] as? [Int], values.count % 5 == 0 else {
            throw SwiftCompletionError.malformedResponse("Invalid semantic token array.")
        }
        let document = (prefix + source) as NSString
        let prefixLength = prefix.utf16.count
        var starts = [0]
        var ends: [Int] = []
        var index = 0
        while index < document.length {
            let c = document.character(at: index)
            if c == 10 || c == 13 {
                ends.append(index)
                if c == 13, index + 1 < document.length, document.character(at: index + 1) == 10 { index += 1 }
                starts.append(index + 1)
            }
            index += 1
        }
        ends.append(document.length)
        var line = 0
        var column = 0
        var previousStart = 0
        var tokens: [Self] = []
        tokens.reserveCapacity(values.count / 5)
        for i in stride(from: 0, to: values.count, by: 5) {
            let deltaLine = values[i], deltaColumn = values[i + 1], length = values[i + 2]
            let type = values[i + 3], flags = values[i + 4]
            guard deltaLine >= 0, deltaLine < starts.count - line, deltaColumn >= 0,
                  length > 0, type >= 0, type < types.count, flags >= 0, flags < (1 << modifiers.count) else {
                throw SwiftCompletionError.malformedResponse("Invalid semantic token coordinates or classification.")
            }
            line += deltaLine
            if deltaLine > 0 { column = 0 }
            let lineLength = ends[line] - starts[line]
            guard column <= lineLength, deltaColumn <= lineLength - column else {
                throw SwiftCompletionError.malformedResponse("Semantic token column exceeds its line.")
            }
            column += deltaColumn
            guard length <= lineLength - column else { throw SwiftCompletionError.malformedResponse("Semantic token exceeds its line.") }
            let start = starts[line] + column
            guard start >= previousStart else { throw SwiftCompletionError.malformedResponse("Unsorted semantic tokens.") }
            previousStart = start
            let previousEnd = start + length
            if previousEnd <= prefixLength { continue }
            for boundary in [start, previousEnd] where boundary < document.length {
                guard !(0xDC00...0xDFFF).contains(document.character(at: boundary)) else {
                    throw SwiftCompletionError.malformedResponse("Semantic token splits a UTF-16 surrogate pair.")
                }
            }
            let range = NSRange(location: start - prefixLength, length: length)
            guard range.location >= 0, Range(range, in: source) != nil else {
                throw SwiftCompletionError.malformedResponse("Semantic token splits Unicode or the injected prefix.")
            }
            var labels: Set<String> = []
            for bit in modifiers.indices where flags & (1 << bit) != 0 { labels.insert(modifiers[bit]) }
            tokens.append(Self(range: range, kind: types[type], modifiers: labels))
        }
        return tokens
    }
}
