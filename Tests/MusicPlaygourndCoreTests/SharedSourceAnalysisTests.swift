import Foundation
import MusicPlaygroundUI
import Testing

@Suite struct SharedSourceAnalysisTests {
    @Test(.timeLimit(.minutes(1))) func grammarAndUnicodeRanges() async throws {
        let source = ##"""
        import SwiftMusic
        /* outer /* inner 日本語 */ still comment */
        struct Session: Music {
            var title = #"raw \#(42) 🎧"#
            var body: some Sound {
                Track("Melody") { Synthesizer(.sine).gain(0.25) }
            }
            func render(_ count: Int) { print(count) }
        }
        """##
        let result = try await SwiftSourceAnalyzer(importedTypes: ["Track", "Synthesizer"]).analyze(source: source)
        #expect(result.diagnostics.isEmpty)
        let text = source as NSString
        #expect(result.tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= text.length })
        func kind(_ word: String) -> String? {
            let range = text.range(of: word)
            return result.tokens.last { NSIntersectionRange($0.range, range).length == range.length }?.kind
        }
        #expect(kind("struct") == "keyword")
        #expect(kind("Session") == "type")
        #expect(kind("Synthesizer") == "type")
        #expect(kind("gain") == "function")
        #expect(kind("render") == "function")
        #expect(kind("0.25") == "number")
        #expect(kind("日本語") == "comment")
        #expect(kind("raw") == "string")
        #expect(kind("42") == "number")
        #expect(result.symbols.contains("Session"))
        #expect(result.symbols.contains("title"))
        #expect(result.symbols.contains("render"))
        #expect(!result.symbols.contains("gain"))
    }

    @Test(.timeLimit(.minutes(1))) func actualEditsDiagnosticsAndFormat() async throws {
        let analyzer = SwiftSourceAnalyzer()
        let first = try await analyzer.analyze(source: "let value = 0.25")
        let changed = try await analyzer.analyze(source: "let value = \"different\"")
        #expect(first.tokens.contains { $0.kind == "number" })
        #expect(!changed.tokens.contains { $0.kind == "number" })
        #expect(changed.tokens.contains { $0.kind == "string" })
        let broken = try await analyzer.analyze(source: "struct Session {")
        #expect(!broken.diagnostics.isEmpty)
        await #expect(throws: SourceAnalysisError.invalidSyntax) { try await analyzer.format(source: "struct Session {") }
        let formatted = try await analyzer.format(source: "struct Session{var value=0.25}")
        #expect(formatted.contains("    var value = 0.25"))
        #expect(try await analyzer.analyze(source: formatted).diagnostics.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func admissionAndCancellation() async throws {
        await #expect(throws: SourceAnalysisError.sourceTooLarge) {
            try await SwiftSourceAnalyzer().analyze(source: String(repeating: " ", count: 2 * 1024 * 1024 + 1))
        }
        let work = Task {
            try Task.checkCancellation()
            return try await SwiftSourceAnalyzer().analyze(source: "let value = 1")
        }
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
    }
}
