import Foundation

/// A compiler issue whose navigation is valid only for its captured source bytes.
struct EditorDiagnostic: Identifiable, Equatable {
    struct Source: Equatable {
        let documentID: UUID?
        let url: URL?
        let path: String
        let text: String
        let isEntry: Bool
    }

    let id = UUID()
    let file: String
    let line: Int
    let column: Int
    let severity: String
    let message: String
    let source: Source?
    let range: NSRange?

    var location: String { "\(source?.path ?? file):\(line):\(column)" }

    func matches(documentID: UUID, url: URL?, text: String) -> Bool {
        guard let source, range != nil,
              source.text.utf8.elementsEqual(text.utf8) else { return false }
        return source.url.map { $0 == url } ?? (source.documentID == documentID)
    }

    static func parse(_ output: String, sources: [Source]) -> [Self] {
        // Compiler output is already bounded to 1 MiB by Evaluation.
        let pattern = #/^(.+?):([0-9]+):([0-9]+): (error|warning|note): (.+)$/#
        var issues: [Self] = []
        for record in output.split(whereSeparator: \.isNewline) {
            guard let match = record.wholeMatch(of: pattern),
                  let line = Int(match.2), let column = Int(match.3), line > 0, column > 0 else { continue }
            let file = String(match.1)
            let candidates = sources.filter { source in
                if file == "Session.swift" { return source.isEntry }
                if let url = source.url, file == url.path { return true }
                return file == source.path || (source.path.contains("/") && file.hasSuffix("/Project/" + source.path))
            }
            let source = candidates.count == 1 ? candidates[0] : nil
            let issue = Self(file: file, line: line, column: column,
                severity: String(match.4), message: String(match.5), source: source,
                range: source.flatMap { utf16Range(source: $0.text, line: line, column: column) })
            if !issues.contains(where: { $0.file == file && $0.line == line && $0.column == column
                && $0.severity == issue.severity && $0.message == issue.message }) { issues.append(issue) }
        }
        return issues
    }

    static func utf16Range(source: String, line: Int, column: Int) -> NSRange? {
        guard line > 0, column > 0 else { return nil }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard line <= lines.count else { return nil }
        let text = lines[line - 1]
        guard column - 1 <= text.utf8.count,
              let byte = text.utf8.index(text.utf8.startIndex, offsetBy: column - 1, limitedBy: text.utf8.endIndex),
              let index = String.Index(byte, within: source) else { return nil }
        let offset = index.utf16Offset(in: source)
        let length = index == text.endIndex ? 0 : source[index].utf16.count
        return NSRange(location: offset, length: length)
    }
}
