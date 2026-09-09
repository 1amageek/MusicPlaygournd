import SwiftMusic
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    struct LiveOutputTests {
        @MainActor
        @Test(.timeLimit(.minutes(3)))
        func testHardwareTapAndLiveControlsPreserveAdoptedPlayback() async throws {
            let sound = try SoundCompiler().compile(Synthesizer(.sine).notes("C3 C3 C3 C3"))
            let loop = try LoopRenderer().render(sound, bpm: 120, beatsPerBar: 4)
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop, revision: 1)
            try engine.play()
            try await Task.sleep(for: .milliseconds(350))
            let first = engine.outputMeter()
            #expect(first.interleavedSamples.count == 16_384)
            #expect(first.sampleRate > 0)
            #expect(first.interleavedSamples.map { abs($0) }.max() ?? 0 > 0.0001)
            try engine.setMasterVolume(0.5)
            try await Task.sleep(for: .milliseconds(350))
            let halfPeak = engine.outputMeter().interleavedSamples.map { abs($0) }.max() ?? 0
            let fullPeak = first.interleavedSamples.map { abs($0) }.max() ?? 0
            #expect(halfPeak > fullPeak * 0.4 && halfPeak < fullPeak * 0.6)
            try engine.setMasterVolume(0)
            try await Task.sleep(for: .milliseconds(350))
            #expect(engine.outputMeter().interleavedSamples.allSatisfy { abs($0) < 0.000001 })
            #expect(throws: PlaybackError.invalidMasterVolume(2)) { try engine.setMasterVolume(2) }
            try await Task.sleep(for: .milliseconds(50))
            #expect(engine.outputMeter().interleavedSamples.allSatisfy { abs($0) < 0.000001 })
            #expect(engine.snapshot().revision == 1)
            #expect(engine.snapshot().isPlaying)
            try engine.setMasterVolume(1)
            try await Task.sleep(for: .milliseconds(350))
            #expect(engine.outputMeter().interleavedSamples.contains { abs($0) > 0.0001 })
            try engine.setPlaybackRate(137.0 / 120.0)
            try engine.setLowPass(cutoff: 800)
            try engine.setDelay(mix: 0.3)
            try engine.setReverb(mix: 0.2)
            engine.beginUpdate(revision: 2)
            #expect(throws: (any Error).self) { try engine.submit(loop: loop, revision: 1) }
            try await Task.sleep(for: .milliseconds(350))
            #expect(engine.snapshot().revision == 1)
            #expect(engine.snapshot().isPlaying)
            let live = engine.outputMeter()
            #expect(live.interleavedSamples.allSatisfy { $0.isFinite })
            #expect(live.interleavedSamples.map { abs($0) }.max() ?? 0 > 0.0001)
            engine.stop()
            #expect(engine.outputMeter().interleavedSamples.allSatisfy { $0 == 0 })
        }
    }
}
