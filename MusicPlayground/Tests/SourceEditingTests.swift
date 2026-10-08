@testable import MusicPlaygroundUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SourceEditingTests: XCTestCase {
    @Observable final class Buffer {
        var source = "struct Session {\n    var title = \"🎧日本語\"\n    var value = 0.25\n}"
        var failure = ""
        var analysis: SourceAnalysis?
        var formatRequest = 0
        var id = UUID()
    }

    private func editor(in view: UIView) -> SourceTextView? {
        if let view = view as? SourceTextView { return view }
        for child in view.subviews { if let found = editor(in: child) { return found } }
        return nil
    }

    func testRealUIKitHighlightEditingSelectionUndoAndIME() async throws {
        let buffer = Buffer()
        let previousTheme = UserDefaults.standard.object(forKey: "editor.theme")
        let previousSize = UserDefaults.standard.object(forKey: "editor.fontSize")
        UserDefaults.standard.set("Midnight", forKey: "editor.theme")
        UserDefaults.standard.set(12.0, forKey: "editor.fontSize")
        defer {
            if let previousTheme { UserDefaults.standard.set(previousTheme, forKey: "editor.theme") }
            else { UserDefaults.standard.removeObject(forKey: "editor.theme") }
            if let previousSize { UserDefaults.standard.set(previousSize, forKey: "editor.fontSize") }
            else { UserDefaults.standard.removeObject(forKey: "editor.fontSize") }
        }
        let root = EditorFixture(buffer: buffer)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let textView = try XCTUnwrap(editor(in: controller.view))
        textView.becomeFirstResponder()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while buffer.analysis == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(buffer.analysis)
        XCTAssertEqual(buffer.failure, "")
        XCTAssertEqual(textView.font?.pointSize, 12)
        XCTAssertEqual(textView.text.components(separatedBy: "\n").count, 4)
        let source = textView.text as NSString
        func color(_ word: String) -> UIColor? {
            textView.textStorage.attribute(.foregroundColor, at: (textView.text as NSString).range(of: word).location, effectiveRange: nil) as? UIColor
        }
        XCTAssertEqual(color("struct"), EditorTheme.midnight.palette.keyword)
        XCTAssertEqual(color("Session"), EditorTheme.midnight.palette.type)
        XCTAssertEqual(color("🎧日本語"), EditorTheme.midnight.palette.string)
        XCTAssertEqual(color("0.25"), EditorTheme.midnight.palette.number)
        let original = textView.text!
        let selection = source.range(of: "0.25")
        textView.selectedRange = selection
        textView.insertText("0.5")
        let selectedAfterEdit = textView.selectedRange
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(buffer.source.contains("0.5"))
        XCTAssertEqual(textView.selectedRange, selectedAfterEdit)
        XCTAssertEqual(color("0.5"), EditorTheme.midnight.palette.number)
        let undo = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(textView.text, original)
        XCTAssertEqual(buffer.source, original)
        textView.selectedRange = source.range(of: "title")
        textView.setMarkedText("名前", selectedRange: NSRange(location: 2, length: 0))
        let marked = textView.markedTextRange
        XCTAssertNotNil(marked)
        UserDefaults.standard.set("Dracula", forKey: "editor.theme")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(textView.markedTextRange)
        XCTAssertTrue(textView.text.contains("名前"))
        textView.unmarkText()
        textView.delegate?.textViewDidChange?(textView)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(buffer.source.contains("名前"))
        XCTAssertEqual(color("struct"), EditorTheme.dracula.palette.keyword)
    }

    func testInvalidSyntaxReportsParsingFailureAndKeepsActualText() async throws {
        let result = try await SwiftSourceAnalyzer().analyze(source: "struct Broken {")
        XCTAssertFalse(result.diagnostics.isEmpty)
        do { _ = try await SwiftSourceAnalyzer().format(source: "struct Broken {"); XCTFail("Invalid syntax must fail formatting.") }
        catch SourceAnalysisError.invalidSyntax { }
    }

    func testRapidDocumentReplacementRejectsOldAnalysisAndCountsLineEndings() async throws {
        let buffer = Buffer()
        let controller = UIHostingController(rootView: EditorFixture(buffer: buffer))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let oldEditor = try XCTUnwrap(editor(in: controller.view))
        oldEditor.selectedRange = NSRange(location: 0, length: 0)
        oldEditor.insertText("// a late previous document\n")
        buffer.id = UUID()
        buffer.source = "let fresh = \"new\"\r\n// comment\rlet number = 42\n"
        buffer.analysis = nil
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while (editor(in: controller.view) === oldEditor || buffer.analysis == nil) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let current = try XCTUnwrap(editor(in: controller.view))
        XCTAssertFalse(current === oldEditor)
        XCTAssertEqual(current.text, buffer.source)
        XCTAssertEqual(current.lineStarts.count, 4)
        let position = (current.text as NSString).range(of: "42").location
        XCTAssertEqual(current.textStorage.attribute(.foregroundColor, at: position, effectiveRange: nil) as? UIColor,
                       current.theme.palette.number)
        XCTAssertFalse(buffer.source.contains("late previous"))
    }

    func testSyntaxCompletionFormatIndentationAndUndoUseNativeStorage() async throws {
        let buffer = Buffer()
        buffer.source = "struct Session {\n    var value = 1\n    func play() { val }\n}"
        let controller = UIHostingController(rootView: EditorFixture(buffer: buffer))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let textView = try XCTUnwrap(editor(in: controller.view))
        textView.becomeFirstResponder()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while buffer.analysis == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let before = textView.text!
        let prefix = (before as NSString).range(of: "val }")
        textView.selectedRange = NSRange(location: prefix.location + 3, length: 0)
        textView.insertCompletion("value")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(buffer.source.contains("{ value }"))
        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(buffer.source, before)
        textView.undoManager?.removeAllActions()
        buffer.source = "struct Session { var 🎵Loop = 1; func play() { 🎵 } }"
        try await Task.sleep(for: .milliseconds(350))
        let emoji = (textView.text as NSString).range(of: "🎵 }")
        textView.selectedRange = NSRange(location: emoji.location + 2, length: 0)
        textView.insertCompletion("🎵Loop")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(buffer.source.contains("{ 🎵Loop }"))
        XCTAssertFalse(buffer.source.contains("🎵🎵"))
        textView.undoManager?.removeAllActions()
        buffer.source = "struct Session{var value=1}"
        try await Task.sleep(for: .milliseconds(350))
        let unformatted = textView.text!
        buffer.formatRequest += 1
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(buffer.source.contains("    var value = 1"))
        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(buffer.source, unformatted)
        textView.selectedRange = NSRange(location: 0, length: textView.textStorage.length)
        textView.insertText("struct Session {")
        textView.insertText("\n")
        textView.insertText("\t")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(buffer.source, "struct Session {\n        ")
    }

    private struct EditorFixture: View {
        var buffer: Buffer
        var body: some View {
            SourceEditor(documentID: buffer.id, source: buffer.source, formatRequest: buffer.formatRequest,
                         onEdit: { _, source in buffer.source = source },
                         onAnalysis: { _, value in buffer.analysis = value }, onFailure: { buffer.failure = $0 })
        }
    }
}
