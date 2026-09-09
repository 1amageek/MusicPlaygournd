import Foundation
import Testing
@testable import MusicPlaygourndCore
@testable import MusicPlaygourndApp

struct SwiftSemanticTokenTests {
    @Test func decoderValidatesUTF16AndNegotiatedLegend() throws {
        func response(_ values: [Int]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["result": ["data": values]])
        }
        let source = "// 🎵\r\nstruct 型 {}"
        let tokens = try SwiftSemanticToken.decode(response([0, 0, 5, 0, 0, 1, 0, 6, 1, 0, 0, 7, 1, 2, 1]),
            source: source, types: ["comment", "keyword", "struct"], modifiers: ["declaration"])
        #expect(tokens.map { (source as NSString).substring(with: $0.range) } == ["// 🎵", "struct", "型"])
        #expect(tokens.last?.modifiers == ["declaration"])
        let symbol: [String: Any] = ["kind": 23, "selectionRange": ["start": ["line": 1, "character": 7], "end": ["line": 1, "character": 8]]]
        let declarationData = try JSONSerialization.data(withJSONObject: ["result": [symbol]])
        #expect(try SwiftSemanticToken.declarations(declarationData, source: source).first?.range == tokens.last?.range)
        let reversed: [String: Any] = ["kind": 23, "selectionRange": ["start": ["line": 1, "character": 8], "end": ["line": 1, "character": 7]]]
        #expect(throws: SwiftCompletionError.self) {
            try SwiftSemanticToken.declarations(JSONSerialization.data(withJSONObject: ["result": [reversed]]), source: source)
        }
        for invalid in [[0, 0], [0, 3, 1, 0, 0], [99, 0, 1, 0, 0], [0, 0, 1, 99, 0],
                        [0, 0, 1, 0, 4], [0, 0, 99, 0, 0], [0, -1, 2, 0, 0]] {
            #expect(throws: SwiftCompletionError.self) {
                try SwiftSemanticToken.decode(response(invalid), source: source, types: ["comment"], modifiers: [])
            }
        }
    }
}

extension NativeHostTests {
    struct SemanticProjectTests {
        @Test(.timeLimit(.minutes(2))) @MainActor
        func realStarterTypesAndUnsavedProjectFiles() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "SemanticProject-\(UUID().uuidString)")
            try SessionModel.createProject(at: root)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let file = root.appending(path: "Sources/\(root.lastPathComponent)/Session.swift")
            let source = SessionModel.initialSource
            let sibling = file.deletingLastPathComponent().appending(path: "Voice.swift")
            try "struct Voice {}".write(to: sibling, atomically: true, encoding: .utf8)
            let lsp = try #require(try SwiftCompletionConnectionTests.resolveSourceKitLSP())
            let host = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let service = ProjectCompletionService(root: root, executable: lsp, hostModuleDirectory: host.appending(path: ".build/debug"))
            do {
                let tokens = try await service.semanticTokens(source: source, file: file, buffers: [file: source])
                for name in ["RhythmSection", "SynthSection", "BusReturn", "Sample", "slider"] {
                    let range = (source as NSString).range(of: name + "(")
                    let token = try #require(tokens.first { $0.range.location == range.location }, "Missing reference: \(name)")
                    #expect(["struct", "class", "type", "function", "method"].contains(token.kind), "\(name): \(token.kind)")
                }
                let changed = "// 🎵 日本語\nstruct Session { let voice = Voice(); let url = #\"https://example.com\"# }"
                let edits = try await service.semanticTokens(source: changed, file: file, buffers: [file: changed, sibling: "struct Voice { let value = 1 }"])
                let voice = (changed as NSString).range(of: "Voice()")
                #expect(edits.contains { $0.range.location == voice.location && ["struct", "method"].contains($0.kind) })
                let manifest = root.appending(path: "Package.swift")
                let packageSource = try String(contentsOf: manifest, encoding: .utf8)
                let manifestTokens = try await service.semanticTokens(source: packageSource, file: manifest, buffers: [file: changed])
                let url = (packageSource as NSString).range(of: "https://github.com/1amageek/SwiftMusic.git")
                #expect(manifestTokens.contains { $0.kind == "string" && NSIntersectionRange($0.range, url) == url })
                #expect(try String(contentsOf: file, encoding: .utf8) == source)
                try await service.shutdown()
                await #expect(throws: SwiftCompletionError.self) { try await service.semanticTokens(source: source, file: file, buffers: [:]) }
            } catch { try await service.shutdown(); throw error }
        }
    }
}
