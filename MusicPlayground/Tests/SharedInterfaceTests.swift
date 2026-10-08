import AVFoundation
import Observation
import SwiftUI
import SwiftMusic
import UIKit
import XCTest
@testable import MusicPlayground
@testable import MusicPlaygroundUI

@MainActor
final class SharedInterfaceTests: XCTestCase {
    @Observable final class State {
        var source = DemoMusic.source
        let id = UUID()
        var layout = 0
        var resultLines: [Int: Int] = [:]
        var rows: [InlineSourceResult] = []
        var failure = ""
    }
    private struct Fixture: View {
        let state: State
        var body: some View {
            GeometryReader { geometry in
                EditorResultsLayout(mode: state.layout, size: geometry.size) {
                    SourceEditor(documentID: state.id, source: state.source, onEdit: { _, value in state.source = value },
                        onFailure: { state.failure = $0 }, inlineResults: state.layout == 0 ? state.rows : [])
                    Color.black
                    Color.gray
                }
            }
        }
    }
    private func editor(in view: UIView) -> SourceTextView? {
        if let found = view as? SourceTextView { return found }
        for child in view.subviews { if let found = editor(in: child) { return found } }
        return nil
    }
    func testActualAcceptedRowsAndInlineSpacingKeepCharactersUndoAndLayoutIdentity() async throws {
        let audio = try AudioWorkspace()
        do {
            try await audio.prepareDefault(id: UUID())
            let loop = try XCTUnwrap(audio.a.loop)
            XCTAssertEqual(loop.rows.count, 4)
            let lines = DemoMusic.resultLines(for: loop)
            XCTAssertEqual(lines.count, loop.rows.count, "Every actual renderer row must map to its displayed accepted expression.")
            let state = State()
            state.rows = loop.rows.map { row in
                InlineSourceResult(id: row.sourceID, line: lines[row.sourceID]!) {
                    InlineRhythmCard(label: row.label, events: loop.events.filter { $0.sourceID == row.sourceID }, beats: loop.beatCount,
                        meter: loop.beatsPerBar, beat: 0, playing: false, muted: false, hasTrack: true, toggle: {})
                }
            }
            let controller = UIHostingController(rootView: Fixture(state: state))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            let text = try XCTUnwrap(editor(in: controller.view))
            XCTAssertThrowsError(try text.inlineLayout.update([InlineSourceResult(id: 0, line: 0) { Text("Invalid") }]))
            XCTAssertThrowsError(try text.inlineLayout.update([InlineSourceResult(id: 0, line: 1) { Text("First") }, InlineSourceResult(id: 0, line: 2) { Text("Duplicate") }]))
            XCTAssertEqual(text.text, DemoMusic.source); XCTAssertEqual(text.textStorage.string, DemoMusic.source)
            let end = lines[loop.rows[0].sourceID]!
            let nextStart = text.lineStarts[end]
            let start = text.lineStarts[end - 1]
            let manager = text.layoutManager
            let before = manager.lineFragmentUsedRect(forGlyphAt: manager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            let after = manager.lineFragmentUsedRect(forGlyphAt: manager.glyphIndexForCharacter(at: nextStart), effectiveRange: nil)
            XCTAssertGreaterThan(after.minY - before.maxY, 48, "The real TextKit layout must reserve space for the visible result.")
            text.becomeFirstResponder(); text.selectedRange = NSRange(location: text.textStorage.length, length: 0)
            text.insertText("\n// retain undo")
            try await Task.sleep(for: .milliseconds(200))
            let selection = text.selectedRange
            for layout in [1, 2, 0] {
                state.layout = layout
                try await Task.sleep(for: .milliseconds(200)); controller.view.layoutIfNeeded()
                XCTAssertTrue(editor(in: controller.view) === text)
                XCTAssertEqual(text.selectedRange, selection); XCTAssertTrue(text.undoManager?.canUndo == true)
            }
            text.undoManager?.undo()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(state.source, DemoMusic.source); XCTAssertEqual(state.failure, "")
            try await audio.stop()
        } catch { do { try await audio.stop() } catch { XCTFail("Cleanup: \(error)") }; throw error }
    }
    func testCommittedEditsRemapBothAcceptedDecksWithoutChangingTheirAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "anchors-" + UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Anchors." + UUID().uuidString))
        let documents = DocumentWorkspace(files: ProjectFiles(projectsDirectory: root), defaults: defaults)
        let audio = try AudioWorkspace()
        defer { do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Cleanup: \(error)") } }
        do {
            await documents.start(template: DemoMusic.source)
            let document = try XCTUnwrap(documents.activeDocument)
            try await audio.prepareDefault(id: document.id)
            documents.sourceDidChange = { id, range, replacement in
                audio.a.sourceEdited(id: id, range: range, replacement: replacement)
                audio.b.sourceEdited(id: id, range: range, replacement: replacement)
            }
            let loop = try XCTUnwrap(audio.a.loop), initial = audio.a.sourceLines(in: document.source)
            XCTAssertEqual(initial.rows.count, 4); XCTAssertEqual(initial.results.count, 4)
            documents.edit(document.id, source: "// 🎵 inserted\n" + document.source)
            for deck in [audio.a, audio.b] {
                let shifted = deck.sourceLines(in: document.source)
                XCTAssertEqual(shifted.rows, initial.rows.mapValues { $0 + 1 })
                XCTAssertEqual(shifted.results, initial.results.mapValues { $0 + 1 })
                XCTAssertEqual(deck.loop, loop); XCTAssertEqual(deck.acceptedSource, DemoMusic.source)
            }
            documents.edit(document.id, source: DemoMusic.source)
            XCTAssertEqual(audio.a.sourceLines(in: document.source).rows, initial.rows)
            let lines = document.source.components(separatedBy: "\n")
            let removed = initial.rows[loop.rows[0].sourceID]!
            let text = document.source as NSString
            let start = lines.prefix(removed - 1).reduce(0) { $0 + $1.utf16.count + 1 }
            let range = text.lineRange(for: NSRange(location: start, length: 0))
            documents.edit(document.id, source: lines.enumerated().filter { $0.offset != removed - 1 }.map(\.element).joined(separator: "\n"), edits: [(range, "")])
            XCTAssertNil(audio.a.sourceLines(in: document.source).rows[loop.rows[0].sourceID])
            XCTAssertEqual(audio.a.sourceLines(in: document.source).rows.count, 3)
            XCTAssertEqual(audio.a.loop, loop)
            let coordinator = NativeScratchView(deck: audio.a, activate: { try await audio.activate() }, open: {}).makeCoordinator()
            XCTAssertTrue(coordinator.accessibleForward())
            try await Task.sleep(for: .milliseconds(400)); coordinator.cancel()
            XCTAssertTrue(coordinator.accessibleBackward())
            try await Task.sleep(for: .milliseconds(400)); coordinator.cancel()
            XCTAssertNil(audio.a.error); XCTAssertFalse(audio.a.isPlaying)
            try await audio.stop()
        } catch { do { try await audio.stop() } catch { XCTFail("Cleanup: \(error)") }; throw error }
    }
    func testRealNativeCueTouchDownUpCancelAndLateActivationGuard() async throws {
        let audio = try AudioWorkspace()
        do {
            try await audio.prepareDefault(id: UUID())
            let controller = UIHostingController(rootView: NativeCueButton(deck: audio.a, color: .blue, name: "A", activate: { try await audio.activate() }).frame(width: 30, height: 30))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.layoutIfNeeded()
            func button(_ view: UIView) -> UIButton? {
                if let button = view as? UIButton { return button }
                for child in view.subviews { if let found = button(child) { return found } }; return nil
            }
            let cue = try XCTUnwrap(button(controller.view))
            cue.sendActions(for: .touchDown); cue.sendActions(for: .touchCancel)
            try await Task.sleep(for: .milliseconds(300)); audio.refresh()
            XCTAssertFalse(audio.a.cue.isPreviewing); XCTAssertFalse(audio.a.isPlaying)
            cue.sendActions(for: .touchDown)
            try await Task.sleep(for: .milliseconds(500)); audio.refresh()
            XCTAssertTrue(audio.a.cue.isPreviewing); XCTAssertTrue(audio.a.isPlaying)
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !audio.masterSamples.contains(where: { abs($0) > 0.001 }) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50)); audio.refresh()
            }
            XCTAssertTrue(audio.masterSamples.contains { abs($0) > 0.001 })
            cue.sendActions(for: .touchUpOutside)
            try await Task.sleep(for: .milliseconds(100)); audio.refresh()
            XCTAssertFalse(audio.a.cue.isPressed); XCTAssertFalse(audio.a.isPlaying)
            try await audio.stop()
        } catch { do { try await audio.stop() } catch { XCTFail("Cleanup: \(error)") }; throw error }
    }
    func testTabReorderPreservesCanonicalBuffersSelectionAndBothDeckAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reorder-" + UUID().uuidString)
        let prefs = try XCTUnwrap(UserDefaults(suiteName: "Reorder." + UUID().uuidString))
        let documents = DocumentWorkspace(files: ProjectFiles(projectsDirectory: root), defaults: prefs)
        let audio = try AudioWorkspace()
        defer { do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Cleanup: \(error)") } }
        do {
            await documents.start(template: DemoMusic.source)
            let original = try XCTUnwrap(documents.activeDocument)
            try documents.attach(original.id, to: 1)
            try await audio.prepareDefault(id: original.id)
            try await audio.toggle(0); try await audio.toggle(1)
            await documents.newFile(deck: 0)
            let first = try XCTUnwrap(documents.activeDocument)
            documents.edit(first.id, source: "let retained = 1\n")
            await documents.newFile(deck: 0)
            let second = try XCTUnwrap(documents.activeDocument)
            documents.reorder(second.id, before: original.id, deck: 0)
            XCTAssertEqual(documents.tabs(in: 0).map(\.id), [second.id, original.id, first.id])
            XCTAssertTrue(documents.activeDocument === second)
            XCTAssertTrue(documents.selectedDocument(in: 1) === original)
            XCTAssertEqual(first.source, "let retained = 1\n"); XCTAssertTrue(first.isDirty)
            audio.refresh(); XCTAssertTrue(audio.a.isPlaying); XCTAssertTrue(audio.b.isPlaying)
            XCTAssertEqual(audio.a.documentID, original.id); XCTAssertEqual(audio.b.documentID, original.id)
            do { try await audio.a.prepare(id: first.id, source: first.source); XCTFail("Edited source must request the separate compiler.") }
            catch DocumentFailure.compilerRequired { }
            XCTAssertEqual(audio.a.documentID, original.id); XCTAssertTrue(audio.a.isPlaying)
            try await audio.stop()
        } catch { do { try await audio.stop() } catch { XCTFail("Cleanup: \(error)") }; throw error }
    }
}
