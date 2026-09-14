import Foundation
import Testing
@testable import MusicPlaygourndCore
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor struct TransportCueTests {
        @Test(.timeLimit(.minutes(1)))
        func nativeCueSetReturnHoldCancelAndDeckIsolation() async throws {
            let output = try AudioOutput()
            let a = try AudioLoopEngine(output: output)
            let b = try AudioLoopEngine(output: output)
            defer { a.stop(); b.stop() }
            let cue = TransportCue(engine: a)
            var errors: [String] = []
            cue.onError = { errors.append($0.localizedDescription) }
            cue.press()
            #expect(!cue.isPressed)
            for engine in [a, b] {
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120,
                    beatsPerBar: 4, beatCount: 4,
                    samples: (0..<176_400).map { Float(sin(Double($0 / 2) * 0.0627)) * 0.2 }, events: []), revision: 1)
            }
            try a.seek(bySeconds: 0.5)
            cue.press(); cue.release()
            #expect(abs(cue.cueBeat - 1) < 0.0001)
            try a.seek(bySeconds: 0.5)
            try a.play()
            cue.press(); cue.release()
            #expect(!a.snapshot().isPlaying)
            #expect(abs(a.snapshot().beatPosition - 1) < 0.0001)
            try a.prepareOfflineRenderingForTests()
            try b.setDeckGain(0)
            try b.play()
            cue.press()
            try await Task.sleep(for: .milliseconds(260))
            #expect(cue.isPreviewing && a.snapshot().isPlaying)
            let pcm = try a.renderOfflineForTests(frameCount: 4096)
            #expect(pcm.contains { abs($0) > 0.001 })
            cue.release()
            #expect(!a.snapshot().isPlaying && b.snapshot().isPlaying)
            #expect(abs(a.snapshot().beatPosition - 1) < 0.0001)
            cue.press(); cue.release()
            try await Task.sleep(for: .milliseconds(230))
            #expect(!a.snapshot().isPlaying)
            cue.press(shift: true)
            #expect(abs(a.snapshot().beatPosition) < 0.0001 && cue.cueBeat == 1)
            #expect(!cue.isPressed)
            cue.reset()
            #expect(cue.cueBeat == 0 && errors.isEmpty)
        }
    }
}
