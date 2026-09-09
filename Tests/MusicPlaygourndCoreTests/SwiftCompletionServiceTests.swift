import Foundation
import Testing
@testable import MusicPlaygourndCore

struct SwiftCompletionServiceTests {
    @Test(.timeLimit(.minutes(3)))
    func testSnippetSelectionAndMalformedEdits() throws {
        let decoded = try SwiftCompletionService.decodeSnippet("gain(${1:value}, cycle: ${2:cycle})$0", enabled: true)
        #expect(decoded.0 == "gain(value, cycle: cycle)")
        #expect(decoded.1 == NSRange(location: 5, length: 5))
        #expect(throws: (any Error).self) { try SwiftCompletionService.decodeSnippet("${1|one,two|}", enabled: true) }
        let invalid: [String: Any] = ["items": [["label": "gain", "textEdit": [
            "range": ["start": ["line": 99, "character": 0], "end": ["line": 99, "character": 1]], "newText": "gain(1)"
        ]]]]
        let data = try JSONSerialization.data(withJSONObject: invalid)
        #expect(throws: (any Error).self) { try SwiftCompletionService.decode(data, source: "sample.ga", cursor: 9) }
    }

    @Test(.timeLimit(.minutes(3)))
    func testRealSwiftMusicOverloadsUnicodeEditsAndShutdown() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "SwiftCompletionService-\(UUID().uuidString)")
        let executable = try #require(try NativeHostTests.SwiftCompletionConnectionTests.resolveSourceKitLSP())
        let service = SwiftCompletionService(packageURL: package, workspace: workspace, sourceKitLSPExecutable: executable, hostModuleDirectory: package.appending(path: ".build/debug"))
        do {
            let source = "// 🎵\nstruct Session: Music {\n var body: some Sound {\n Sample(\"kick\").ga\n }\n}"
            let cursor = NSMaxRange((source as NSString).range(of: ".ga"))
            let initial = Task { try await service.completions(source: source, utf16Offset: cursor) }
            try await Task.sleep(for: .milliseconds(100))
            initial.cancel()
            let gains = try await service.completions(source: source, utf16Offset: cursor)
            do { _ = try await initial.value; Issue.record("Cancelled initialization requester must not deliver candidates") }
            catch is CancellationError { }
            #expect(gains.contains { $0.label.contains("gain") && $0.label.contains("Double") })
            #expect(gains.contains { $0.label.contains("gain") && $0.label.contains("GainPattern") })
            let gain = try #require(gains.first { $0.label == "gain(value: Double)" })
            #expect(gain.detail == "ModifiedSound")
            #expect(gain.semanticKey == SwiftCompletionSemanticKey(
                label: "gain(value: Double)", detail: "ModifiedSound", argumentIndex: 0
            ))
            #expect(gain.annotation?.unit == "amplitude")
            #expect(gain.annotation?.minimum == 0)
            #expect(gain.annotation?.maximum == 2)
            let unsupportedPattern = try #require(
                gains.first { $0.label == "gain(pattern: GainPattern)" }
            )
            #expect(unsupportedPattern.detail == "ModifiedSound")
            #expect(unsupportedPattern.annotation == nil)
            #expect((source as NSString).substring(with: gain.replacementRange) == "ga")
            #expect(gain.insertion.hasPrefix("gain("))
            #expect(gain.selectionRange != nil)
            let rhythmSource = source.replacingOccurrences(of: ".ga", with: ".rh")
            let rhythms = try await service.completions(source: rhythmSource, utf16Offset: cursor)
            #expect(rhythms.contains { $0.label.contains("rhythm") })
            let old = Task { try await service.completions(source: source, utf16Offset: cursor) }
            old.cancel()
            do { _ = try await old.value; Issue.record("Cancelled completion must not be delivered") }
            catch is CancellationError { }
            let recovered = try await service.completions(source: rhythmSource, utf16Offset: cursor)
            #expect(recovered.contains { $0.label.contains("rhythm") })
            let colored = #"""
            // 🎵 Swift semantic colors
            import MusicPlayground
            /* outer /* nested */ comment */
            struct RhythmSection: Sound {
                var body: some Sound { Sample("kick").gain(slider(0.5, in: 0...1)) }
            }
            struct Session: Music {
                var body: some Sound { RhythmSection() }
                let url = #"https://example.com/日本語"#
                let message = "value \(1 + 2)"
            }
            """#
            let tokens = try await service.semanticTokens(source: colored)
            for (word, kind) in [("struct", "keyword"), ("RhythmSection", "struct"), ("Sound", "interface"), ("0.5", "number")] {
                #expect(tokens.contains { (colored as NSString).substring(with: $0.range) == word && $0.kind == kind }, "Missing \(kind): \(word)")
            }
            let bodyKinds = tokens.filter { (colored as NSString).substring(with: $0.range) == "body" }.map(\.kind)
            #expect(bodyKinds.contains("property") || bodyKinds.contains("variable"), "body classifications: \(bodyKinds)")
            let call = (colored as NSString).range(of: "RhythmSection()")
            #expect(tokens.contains { $0.range.location == call.location && ["struct", "method"].contains($0.kind) })
            let url = (colored as NSString).range(of: "https://example.com/日本語")
            #expect(tokens.contains { $0.kind == "string" && NSIntersectionRange($0.range, url) == url })
            async let coloring = service.semanticTokens(source: colored)
            async let completing = service.completions(source: rhythmSource, utf16Offset: cursor)
            let (sameTokens, candidates) = try await (coloring, completing)
            #expect(sameTokens == tokens)
            #expect(candidates.contains { $0.label.contains("rhythm") })
            try await service.shutdown()
            #expect(!(FileManager.default.fileExists(atPath: workspace.path)))
        } catch {
            try await service.shutdown()
            throw error
        }
    }
}
