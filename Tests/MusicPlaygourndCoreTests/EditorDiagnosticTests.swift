import AppKit
import SwiftUI
import Testing
@testable import MusicPlaygourndApp
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct EditorDiagnosticTests {
        @Test
        func unicodeAliasesAndUnknownFiles() throws {
            let text = "// 🎵\nlet 日本 = missing\n"
            let input = EditorDiagnostic.Source(documentID: UUID(), url: nil,
                path: "Sources/Set/Trance.swift", text: text, isEntry: true)
            let output = """
            Session.swift:2:14: error: cannot find 'missing' in scope
            Session.swift:2:14: error: cannot find 'missing' in scope
            /cache/Project/Sources/Set/Trance.swift:3:1: note: end
            /dependency/Other.swift:2:1: error: foreign
            """
            let issues = EditorDiagnostic.parse(output, sources: [input])
            #expect(issues.count == 3)
            let range = try #require(issues[0].range)
            #expect((text as NSString).substring(with: range) == "m")
            #expect(issues[1].range == NSRange(location: text.utf16.count, length: 0))
            #expect(issues[2].range == nil)
            #expect(EditorDiagnostic.utf16Range(source: text, line: 2, column: 6) == nil)
            #expect(EditorDiagnostic.utf16Range(source: text, line: 9, column: 1) == nil)
            #expect(EditorDiagnostic.parse(output, sources: [input, input]).allSatisfy { $0.range == nil })
        }

        @Test(.timeLimit(.minutes(1)))
        func actualCompilerErrorsNavigateToSiblingAndRejectStaleEdits() async throws {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "editor-issues-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let entry = root.appending(path: "Entry.swift")
            let helper = root.appending(path: "Helper.swift")
            let text = "// 日本語\nlet value: Int = \"wrong\"\nlet other: Int = \"also wrong\"\n"
            try "struct Entry {}".write(to: entry, atomically: true, encoding: .utf8)
            try text.write(to: helper, atomically: true, encoding: .utf8)
            let evaluator = SourceEvaluator(packageURL: root, workspace: root.appending(path: "work"), swiftExecutable: "/usr/bin/swift")
            try FileManager.default.createDirectory(at: root.appending(path: "work"), withIntermediateDirectories: true)
            let model = SessionModel(documents: SessionDocumentStore(), audioEnabled: false)
            try model.openDocument(at: entry)
            let sources: [EditorDiagnostic.Source] = [
                .init(documentID: model.activeDocumentID, url: entry, path: "Entry.swift", text: model.source, isEntry: true),
                .init(documentID: nil, url: helper, path: "Helper.swift", text: text, isEntry: false)
            ]
            do {
                _ = try await evaluator.run("/usr/bin/swiftc", ["-typecheck", "-parse-as-library", entry.path, helper.path], timeout: 30)
                Issue.record("Invalid Swift must fail")
            } catch EvaluationError.processFailed(let output) {
                model.recordCompilerFailure(EvaluationError.processFailed(output), sources: sources)
                let issue = try #require(model.compilerIssues.first { $0.line == 2 && $0.severity == "error" })
                #expect(model.compilerIssues.filter { $0.severity == "error" }.count == 2)
                #expect(model.visibleCompilerIssues.isEmpty)
                model.revealDiagnostic(issue)
                #expect(model.fileURL == helper)
                #expect(model.selectionRange == issue.range)
                #expect(model.visibleCompilerIssues.count == 2)
                #expect(model.source == text)
                let selection = model.selectionToken
                model.source = "// changed\n" + text
                #expect(model.visibleCompilerIssues.isEmpty)
                model.revealDiagnostic(issue)
                #expect(model.selectionToken == selection)
            }
            try await model.shutdown()
            try await evaluator.shutdown()
        }

        @Test
        func nativeAnnotationsPreserveSelectionAndRetireAfterEditing() throws {
            let text = "let value = missing\n"
            let input = EditorDiagnostic.Source(documentID: UUID(), url: nil, path: "Session.swift", text: text, isEntry: true)
            let issues = EditorDiagnostic.parse("Session.swift:1:13: error: unknown name", sources: [input])
            let editor = CompletionTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
            editor.string = text
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            let scroll = NSScrollView()
            scroll.documentView = editor
            let ruler = LineNumberRulerView(scrollView: scroll, orientation: .verticalRuler)
            var view = CodeEditor(text: .constant(text), inlineLoop: nil, inlineEnabled: false,
                resultLines: [:], beatPosition: 0, isPlaying: false, selectionLine: nil, selectionToken: 0,
                rhythmLines: [], rowLines: [:], patternTexts: [:], activeTokens: [:], scrollDelta: 0,
                onLayout: { _ in }, beforeEdit: { _, _ in }, onEdit: {}, completions: { _, _ in [] },
                onCompletionStatus: { _ in })
            view.diagnostics = issues
            let coordinator = view.makeCoordinator()
            coordinator.lineNumberRuler = ruler
            coordinator.updateDiagnostics(editor)
            let layout = try #require(editor.layoutManager)
            #expect(layout.temporaryAttribute(.underlineColor, atCharacterIndex: 12, effectiveRange: nil) as? NSColor == .systemRed)
            #expect(ruler.diagnostics.count == 1)
            #expect(editor.diagnosticLines.count == 1)
            #expect(editor.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "unknown name" })
            #expect(editor.string == text && editor.selectedRange() == NSRange(location: 2, length: 0))
            editor.string = "// edit\n" + text
            coordinator.updateDiagnostics(editor)
            #expect(ruler.diagnostics.isEmpty)
            #expect(editor.diagnosticLines.isEmpty)
            #expect(editor.subviews.compactMap { $0 as? NSButton }.isEmpty)
            #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 12, effectiveRange: nil) == nil)
        }
    }
}
