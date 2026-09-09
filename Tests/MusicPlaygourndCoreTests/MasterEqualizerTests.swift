import SwiftMusic
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct MasterEqualizerTests {
        @Test(.timeLimit(.minutes(1)))
        func liveBandCutsNativePCMAndRejectsInvalidValues() async throws {
            let sound = try SoundCompiler().compile(Synthesizer(.sine).notes("C4 C4 C4 C4"))
            let loop = try LoopRenderer().render(sound, bpm: 120, beatsPerBar: 4)
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop, revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.setLowPass(cutoff: 10_000)
            try engine.play()
            func energy() throws -> Double {
                var result = 0.0
                for _ in 0..<4 {
                    result = try engine.renderOfflineForTests(frameCount: 2_048)
                        .reduce(0) { $0 + Double($1 * $1) }
                }
                return result
            }
            let baseline = try energy()
            let value = MasterEqualizerBand(frequency: 261.6256, gain: -12)
            try engine.setEqualizerBand(1, value: value)
            try await Task.sleep(for: .milliseconds(60))
            let filtered = try energy()
            #expect(baseline > 0 && filtered < baseline * 0.15 && filtered > baseline * 0.02)
            #expect(engine.snapshot().isPlaying && engine.snapshot().revision == 1)
            #expect(engine.masterParametersForTests.lowPass == 10_000)
            for invalid in [MasterEqualizerBand(frequency: .nan), .init(frequency: 0), .init(frequency: 1_000, gain: 13)] {
                #expect(throws: PlaybackError.invalidEqualizerBand) { try engine.setEqualizerBand(1, value: invalid) }
            }
            #expect(throws: PlaybackError.invalidEqualizerBand) { try engine.setEqualizerBand(3, value: value) }
            #expect(engine.equalizerBands[1] == value)
        }
    }
}
