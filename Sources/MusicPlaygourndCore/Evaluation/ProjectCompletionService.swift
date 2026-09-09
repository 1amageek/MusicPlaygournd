import Foundation

/// Uses the real package graph and unsaved buffers without writing user files.
public actor ProjectCompletionService {
    private let root: URL
    private let connection: SwiftCompletionConnection
    private var started = false
    private var busy = false
    private var closed = false
    private var version = 0
    private var opened: Set<URL> = []

    init(root: URL, executable: String) {
        self.root = root
        connection = SwiftCompletionConnection(executable: executable, workspace: root)
    }

    public func completions(source: String, utf16Offset: Int, file: URL, buffers: [URL: String]) async throws -> [SwiftCompletion] {
        while busy { try await Task.sleep(for: .milliseconds(20)) }
        guard !closed else { throw SwiftCompletionError.shutdown }
        guard source.utf8.count <= 65_536, utf16Offset >= 0, utf16Offset <= source.utf16.count,
              Range(NSRange(location: utf16Offset, length: 0), in: source) != nil,
              file.path.hasPrefix(root.path + "/") else { throw SwiftCompletionError.invalidSource("Invalid project document or cursor.") }
        busy = true
        defer { busy = false }
        let cold = !started
        if cold {
            try await connection.start()
            _ = try await connection.request(method: "initialize", parameters: Self.json([
                "processId": ProcessInfo.processInfo.processIdentifier, "rootUri": root.absoluteString,
                "capabilities": ["textDocument": ["completion": ["completionItem": ["snippetSupport": true]]]],
                "workspaceFolders": [["uri": root.absoluteString, "name": root.lastPathComponent]]
            ]), timeout: .seconds(30))
            try await connection.notify(method: "initialized", parameters: Self.json([:]))
            started = true
        }
        let start = SwiftCompletionService.identifierStart(in: source, cursor: utf16Offset)
        var documents = buffers.filter { $0.key.path.hasPrefix(root.path + "/") && $0.key.pathExtension == "swift" }
        documents[file] = (source as NSString).replacingCharacters(in: NSRange(location: start, length: utf16Offset - start), with: "")
        for url in opened where documents[url] == nil {
            try await connection.notify(method: "textDocument/didClose", parameters: Self.json(["textDocument": ["uri": url.absoluteString]]))
        }
        opened.formIntersection(documents.keys)
        version += 1
        for (url, text) in documents {
            guard text.utf8.count <= 65_536 else { throw SwiftCompletionError.invalidSource("Source exceeds 64 KiB.") }
            if opened.contains(url) {
                try await connection.notify(method: "textDocument/didChange", parameters: Self.json([
                    "textDocument": ["uri": url.absoluteString, "version": version], "contentChanges": [["text": text]]
                ]))
            } else {
                try await connection.notify(method: "textDocument/didOpen", parameters: Self.json([
                    "textDocument": ["uri": url.absoluteString, "languageId": "swift", "version": version, "text": text]
                ]))
                opened.insert(url)
            }
        }
        if cold { _ = try await connection.request(method: "workspace/synchronize", parameters: Self.json(["index": true]), timeout: .seconds(60)) }
        try Task.checkCancellation()
        let document = documents[file]!
        let response = try await connection.request(method: "textDocument/completion", parameters: Self.json([
            "textDocument": ["uri": file.absoluteString],
            "position": SwiftCompletionService.position(in: document, offset: start), "context": ["triggerKind": 1]
        ]), timeout: .seconds(30))
        try Task.checkCancellation()
        return try SwiftCompletionService.decode(response, source: source, cursor: utf16Offset, prefix: "")
    }

    public func shutdown() async throws {
        closed = true
        try await connection.shutdown()
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
