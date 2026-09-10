import Testing
import AVFoundation
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct TwoDeckPlaybackTests {
        @Test(.timeLimit(.minutes(1)))
        func nativeSyncAlignsIndependentDeckClocks() async throws {
            let output = try AudioOutput()
            let a = try AudioLoopEngine(output: output)
            let b = try AudioLoopEngine(output: output)
            defer { a.stop(); b.stop() }
            for engine in [a, b] {
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                    beatCount: 4, samples: [Float](repeating: 0, count: 176_400), events: []), revision: 1)
            }
            try a.play()
            try await Task.sleep(for: .milliseconds(350))
            try b.setPlaybackRate(1.25)
            try b.play()
            try await Task.sleep(for: .milliseconds(250))
            #expect(!a.deckMeter().interleavedSamples.isEmpty)
            #expect(!b.deckMeter().interleavedSamples.isEmpty)
            let beforeA = try a.playbackClockAnchor()
            let beforeB = try b.playbackClockAnchor()
            #expect(abs(try beforeA.beat(atHostTime: beforeB.presentationHostTime) - beforeB.accumulatedBeatPosition) > 0.3)
            try b.synchronize(to: a)
            try await Task.sleep(for: .milliseconds(250))
            let afterA = try a.playbackClockAnchor()
            let afterB = try b.playbackClockAnchor()
            #expect(abs(try afterA.beat(atHostTime: afterB.presentationHostTime) - afterB.accumulatedBeatPosition) < 0.04)
            #expect(afterA.beatsPerMinute == afterB.beatsPerMinute)
            a.stop()
            #expect(throws: PlaybackClockError.self) { try b.synchronize(to: a) }
            #expect(b.snapshot().isPlaying)
        }

        @Test(.timeLimit(.minutes(1)))
        func crossfadeEndpointsAndPauseKeepTheOtherDeckRunning() throws {
            let output = try AudioOutput()
            let a = try AudioLoopEngine(output: output)
            let b = try AudioLoopEngine(output: output)
            defer { a.stop(); b.stop() }
            func load(_ engine: AudioLoopEngine, left: Float, right: Float) throws {
                var samples = [Float](repeating: 0, count: 88_200 * 2)
                for frame in 0..<88_200 {
                    samples[frame * 2] = left
                    samples[frame * 2 + 1] = right
                }
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120,
                    beatsPerBar: 4, beatCount: 4, samples: samples, events: []), revision: 1)
            }
            try load(a, left: 0.25, right: 0)
            try load(b, left: 0, right: 0.5)
            try a.prepareOfflineRenderingForTests()
            try output.setCrossfade(0)
            try a.play(); try b.play()
            var pcm = try a.renderOfflineForTests(frameCount: 4096)
            #expect(abs(pcm[pcm.count - 2] - 0.25) < 0.01)
            #expect(abs(pcm[pcm.count - 1]) < 0.0001)
            a.stop(); b.stop()
            try output.setCrossfade(1)
            try a.play(); try b.play()
            pcm = try a.renderOfflineForTests(frameCount: 4096)
            #expect(abs(pcm[pcm.count - 2]) < 0.0001)
            #expect(abs(pcm[pcm.count - 1] - 0.5) < 0.01)
            let before = b.snapshot().beatPosition
            a.stop()
            pcm = try b.renderOfflineForTests(frameCount: 4096)
            #expect(!a.snapshot().isPlaying && b.snapshot().isPlaying)
            #expect(b.snapshot().beatPosition > before)
            #expect(abs(pcm[pcm.count - 1] - 0.5) < 0.01)
            #expect(throws: PlaybackError.self) { try output.setCrossfade(.nan) }
            #expect(output.crossfade == 1)
            b.stop()
            try output.setBalance(-1)
            try b.play()
            pcm = try b.renderOfflineForTests(frameCount: 4096)
            #expect(abs(pcm[pcm.count - 1]) < 0.0001)
            #expect(throws: PlaybackError.self) { try output.setBalance(.nan) }
            #expect(output.masterBalance == -1)
            try output.setReverb(mix: 0.25)
            #expect(throws: PlaybackError.self) { try output.setReverb(mix: 2) }
            #expect(output.reverbMix == 0.25)
            try output.setBalance(0)
            try output.setReverb(mix: 0)
            #expect(output.masterBalance == 0 && output.reverbMix == 0)
        }
    }
}
