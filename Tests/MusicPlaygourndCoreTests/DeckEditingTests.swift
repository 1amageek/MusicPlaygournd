import AppKit
import Foundation
import Testing
@testable import MusicPlaygourndApp
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct DeckEditingTests {
        @Test(.timeLimit(.minutes(1)))
        func droppedFileSelectsItsDeckBeforeDiscoveryCompletes() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let file = root.appending(path: "Dropped.swift")
            try "import SwiftMusic\nstruct Dropped: Music { var body: some Sound { Sample(\"kick\") } }".write(to: file, atomically: true, encoding: .utf8)
            let workspace = DeckWorkspace()
            #expect(workspace.selectedDeck == 0)
            #expect(workspace.receiveDrop([NSItemProvider(object: file as NSURL)], into: 1))
            for _ in 0..<100 where workspace.selectedDeck != 1 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(workspace.selectedDeck == 1)
            #expect(workspace.active === workspace.b)
            #expect(workspace.active.fileURL == file)
            #expect(workspace.active.source.contains("struct Dropped"))
            workspace.loadFile(root.appending(path: "Missing.swift"), into: 0)
            #expect(workspace.selectedDeck == 1)
            try await workspace.shutdown()
        }

        @Test(.timeLimit(.minutes(1)))
        func queuedPlaybackCanBeCancelledWithoutRestartingPreparation() async throws {
            let model = SessionModel()
            model.fileURL = FileManager.default.temporaryDirectory.appending(path: "QueuedPlayback.swift")
            model.isPreparing = true
            model.togglePlayback()
            #expect(model.isPlaybackQueued)
            #expect(!model.isPlaying)
            model.togglePlayback()
            #expect(!model.isPlaybackQueued)
            #expect(model.isPreparing)
            try await model.shutdown()
        }

        @Test(.timeLimit(.minutes(1)))
        func tapsAndSharedDocumentsKeepSelectionIndependentOfLoading() async throws {
            var taps = TapTempo()
            #expect(taps.tap(at: 0) == nil)
            #expect(taps.tap(at: 0.5) == 120)
            #expect(taps.tap(at: 1) == 120)
            #expect(taps.tap(at: 4) == nil)
            #expect(taps.tap(at: 4.25) == 240)
            #expect(taps.tap(at: .nan) == nil)
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let first = root.appending(path: "One.swift")
            let second = root.appending(path: "Two.swift")
            try "// shared".write(to: first, atomically: true, encoding: .utf8)
            try "// another".write(to: second, atomically: true, encoding: .utf8)
            let store = SessionDocumentStore()
            let output = try AudioOutput()
            let a = SessionModel(output: output, deckID: UUID().uuidString, documents: store)
            let b = SessionModel(output: output, deckID: UUID().uuidString, documents: store)
            try a.openDocument(at: first)
            try b.openDocument(at: first)
            #expect(a.activeDocument === b.activeDocument)
            a.source = "// 日本語"
            a.sourceChanged()
            #expect(b.source == "// 日本語" && b.activeDocument.isDirty)
            try a.openDocument(at: second)
            #expect(b.fileURL == first)
            #expect(a.revision == 0 && b.revision == 0)
            #expect(a.loadedDocument == nil && b.loadedDocument == nil)
            #expect(a.closeDocument(a.activeDocumentID, decision: .discard))
            #expect(b.hasOpenDocument && b.source == "// 日本語")
            #expect(b.saveDocument())
            #expect(try String(contentsOf: first, encoding: .utf8) == "// 日本語")
            #expect(!a.activeDocument.isDirty)
            b.source = "// discard this edit"
            b.sourceChanged()
            #expect(b.closeDocument(b.activeDocumentID, decision: .discard))
            #expect(a.source == "// 日本語" && !a.activeDocument.isDirty)
            #expect(throws: SessionModel.DocumentFailure.self) { try store.validateSave(a.activeDocument, to: second) }
            try await a.shutdown()
            try await b.shutdown()
        }
    }
}
