import AppKit
import IOKit.hidsystem
import Testing
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct PlayModeKeysTests {
        @Test(.timeLimit(.minutes(1)))
        func standaloneSidesChordsRepeatsAndReset() {
            let keys = PlayModeKeys()
            let cases: [(UInt16, UInt, NSEvent.ModifierFlags, PlayModeKeys.Action)] = [
                (55, UInt(NX_DEVICELCMDKEYMASK), .command, .deck(0)),
                (54, UInt(NX_DEVICERCMDKEYMASK), .command, .deck(1))]
            for (code, mask, flag, action) in cases {
                let down = NSEvent.ModifierFlags(rawValue: flag.rawValue | mask)
                #expect(keys.handle(type: .flagsChanged, keyCode: code, flags: []) == nil)
                #expect(keys.handle(type: .flagsChanged, keyCode: code, flags: down) == nil)
                #expect(keys.handle(type: .flagsChanged, keyCode: code, flags: []) == action)
                _ = keys.handle(type: .flagsChanged, keyCode: code, flags: down)
                #expect(keys.handle(type: .keyDown, keyCode: 1, flags: down) == nil)
                #expect(keys.handle(type: .flagsChanged, keyCode: code, flags: []) == nil)
                _ = keys.handle(type: .flagsChanged, keyCode: code, flags: down)
                keys.reset()
                #expect(keys.handle(type: .flagsChanged, keyCode: code, flags: []) == nil)
            }
            let both = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK))
            _ = keys.handle(type: .flagsChanged, keyCode: 55, flags: NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(NX_DEVICELCMDKEYMASK)))
            _ = keys.handle(type: .flagsChanged, keyCode: 54, flags: both)
            #expect(keys.handle(type: .flagsChanged, keyCode: 54, flags: []) == nil)
            #expect(keys.handle(type: .flagsChanged, keyCode: 55, flags: []) == nil)
            #expect(keys.handle(type: .keyDown, keyCode: 49, flags: []) == .all)
            #expect(keys.handle(type: .keyDown, keyCode: 49, flags: [], repeating: true) == nil)
            #expect(keys.handle(type: .keyDown, keyCode: 49, flags: .command) == nil)
        }

        @Test(.timeLimit(.minutes(1)))
        func cuePressReleaseShiftAndCancellation() {
            let keys = PlayModeKeys()
            let left = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICELALTKEYMASK))
            let both = NSEvent.ModifierFlags(rawValue: left.rawValue | UInt(NX_DEVICERALTKEYMASK))
            #expect(keys.handle(type: .flagsChanged, keyCode: 58, flags: left) == .cueDown(0, false))
            #expect(keys.handle(type: .flagsChanged, keyCode: 61, flags: both) == .cueDown(1, false))
            #expect(keys.handle(type: .flagsChanged, keyCode: 61, flags: left) == .cueUp(1))
            #expect(keys.handle(type: .flagsChanged, keyCode: 58, flags: []) == .cueUp(0))
            #expect(keys.handle(type: .flagsChanged, keyCode: 58, flags: left.union(.shift)) == .cueDown(0, true))
            #expect(keys.handle(type: .keyDown, keyCode: 1, flags: left) == .cancelCue)
            #expect(keys.handle(type: .flagsChanged, keyCode: 58, flags: []) == nil)
            _ = keys.handle(type: .flagsChanged, keyCode: 58, flags: left)
            keys.reset()
            #expect(keys.handle(type: .flagsChanged, keyCode: 58, flags: []) == nil)
        }

        @Test(.timeLimit(.minutes(1)))
        func combinedTransportStopsMixedQueuedDecksWithoutStartingTheOther() async throws {
            let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".swift")
            try "// Keyboard transport fixture\n".write(to: file, atomically: true, encoding: .utf8)
            defer { do { try FileManager.default.removeItem(at: file) } catch { Issue.record(error) } }
            let workspace = DeckWorkspace()
            do {
                #expect(!workspace.hasPlaybackContent)
                try workspace.b.openDocument(at: file)
                #expect(workspace.hasPlaybackContent)
                try workspace.a.openDocument(at: file)
                workspace.toggleAllPlayback()
                #expect(workspace.a.isPlaybackQueued && workspace.b.isPlaybackQueued)
                workspace.b.togglePlayback()
                workspace.toggleAllPlayback()
                #expect(!workspace.a.isPlaybackQueued && !workspace.b.isPlaybackQueued)
                workspace.toggleAllPlayback()
                #expect(workspace.a.isPlaybackQueued && workspace.b.isPlaybackQueued)
                workspace.toggleAllPlayback()
                #expect(!workspace.a.isPlaybackQueued && !workspace.b.isPlaybackQueued)
                try await workspace.shutdown()
            } catch { try await workspace.shutdown(); throw error }
        }
    }
}
