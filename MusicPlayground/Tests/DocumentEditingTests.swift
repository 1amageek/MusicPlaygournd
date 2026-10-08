@testable import MusicPlaygroundUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class DocumentEditingTests: XCTestCase {
    @Observable final class Buffers {
        let first = UUID()
        let second = UUID()
        var active: UUID
        var sources: [UUID: String]
        var plain = false
        var analysisCount = 0
        init() {
            active = first
            sources = [first: "let first = 1\n", second: "This is plain text, not Swift."]
        }
    }
    private struct Fixture: View {
        let buffers: Buffers
        var body: some View {
            SourceEditor(documentID: buffers.active, source: buffers.sources[buffers.active]!,
                         retainedDocuments: Set(buffers.sources.keys), isSyntaxEnabled: !buffers.plain,
                         onEdit: { buffers.sources[$0] = $1 },
                         onAnalysis: { _, _ in buffers.analysisCount += 1 }, onFailure: { if !$0.isEmpty { XCTFail($0) } })
        }
    }
    private func editor(_ view: UIView) -> SourceTextView? {
        if let found = view as? SourceTextView { return found }
        for child in view.subviews { if let found = editor(child) { return found } }
        return nil
    }
    func testRealDocumentSwitchRetainsNativeSelectionUndoAndPlainText() async throws {
        let buffers = Buffers()
        let controller = UIHostingController(rootView: Fixture(buffers: buffers))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let first = try XCTUnwrap(editor(controller.view))
        first.becomeFirstResponder()
        first.selectedRange = NSRange(location: first.textStorage.length, length: 0)
        first.insertText("// retained edit\n")
        let selection = first.selectedRange
        try await Task.sleep(for: .milliseconds(350))
        buffers.active = buffers.second; buffers.plain = true
        try await Task.sleep(for: .milliseconds(350))
        let second = try XCTUnwrap(editor(controller.view))
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.text, buffers.sources[buffers.second])
        XCTAssertTrue(second.symbols.isEmpty)
        buffers.active = buffers.first; buffers.plain = false
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(first === editor(controller.view))
        XCTAssertEqual(first.selectedRange, selection)
        XCTAssertTrue(first.undoManager?.canUndo == true)
        first.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(buffers.sources[buffers.first], "let first = 1\n")
        XCTAssertEqual(buffers.sources[buffers.second], "This is plain text, not Swift.")
    }
}
