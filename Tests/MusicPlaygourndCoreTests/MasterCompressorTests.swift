import AVFoundation
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct MasterCompressorTests {
        @Test(.timeLimit(.minutes(1)))
        func streamingRatioTimingStereoLinkAndFailures() throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
            buffer.frameLength = 4096
            let channels = try #require(buffer.floatChannelData)
            func process(_ kernel: MasterCompressorKernel, level: Float) throws -> Float {
                for frame in 0..<4096 { channels[0][frame] = level; channels[1][frame] = level * 0.5 }
                #expect(kernel.process(buffer.mutableAudioBufferList, frames: 4096) == noErr)
                #expect((0..<4096).allSatisfy { channels[1][$0] == channels[0][$0] * 0.5 })
                return channels[0][4095]
            }
            let fast = try MasterCompressorKernel()
            let settings = MasterCompressorSettings(enabled: true, threshold: -20, ratio: 4,
                attackMilliseconds: 0.1, releaseMilliseconds: 10)
            try fast.configure(settings)
            let compressed = try process(fast, level: 0.5)
            let expected = 0.5 * pow(10, -(20 * log10(0.5) + 20) * 0.75 / 20)
            #expect(abs(Double(compressed) - expected) < 0.00001)
            let snapshot = fast.snapshot()
            #expect(snapshot.inputEnvelope.count == 512 && snapshot.outputEnvelope.count == 512)
            #expect(abs(snapshot.gainReduction - (20 * log10(0.5) + 20) * 0.75) < 0.001)
            #expect(snapshot.inputEnvelope.last == 0.5)
            #expect(abs(Double(snapshot.outputEnvelope.last ?? 0) - expected) < 0.00001)
            let slow = try MasterCompressorKernel()
            var slowSettings = settings
            slowSettings.attackMilliseconds = 200
            slowSettings.releaseMilliseconds = 2000
            try slow.configure(slowSettings)
            #expect(try process(slow, level: 0.5) > compressed * 1.5)
            for _ in 0..<25 { _ = try process(slow, level: 0.5) }
            let releasedFast = try process(fast, level: 0.05)
            let releasedSlow = try process(slow, level: 0.05)
            #expect(releasedFast > 0.049 && releasedSlow < releasedFast * 0.5)
            #expect(slow.snapshot().inputEnvelope.count == 1024)
            try fast.configure(.defaults)
            #expect(try process(fast, level: 0.5) == 0.5)
            #expect(fast.snapshot().gainReduction == 0)
            channels[0][0] = .nan
            #expect(fast.process(buffer.mutableAudioBufferList, frames: 4096) == kAudioUnitErr_InvalidPropertyValue)
            #expect(fast.process(buffer.mutableAudioBufferList, frames: 4097) == kAudioUnitErr_TooManyFramesToProcess)
        }

        @Test(.timeLimit(.minutes(1)))
        func nativeGraphChangesPCMImmediatelyAndResetPreservesTransport() throws {
            var samples = [Float](repeating: 0, count: 88_200 * 2)
            for frame in 0..<88_200 {
                samples[frame * 2] = Float(sin(Double(frame) * 2 * .pi * 1000 / 44_100)) * 0.5
                samples[frame * 2 + 1] = samples[frame * 2] * 0.5
            }
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                beatCount: 4, samples: samples, events: []), revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.play()
            func rms() throws -> Double {
                var pcm: [Float] = []
                for _ in 0..<3 { pcm = try engine.renderOfflineForTests(frameCount: 4096) }
                return sqrt(pcm.reduce(0.0) { $0 + Double($1 * $1) } / Double(pcm.count))
            }
            let dry = try rms()
            let settings = MasterCompressorSettings(enabled: true, threshold: -24, ratio: 8,
                attackMilliseconds: 0.1, releaseMilliseconds: 100)
            try engine.setCompressor(settings)
            let wet = try rms()
            #expect(dry > 0.1 && wet < dry * 0.3 && wet > 0)
            #expect(engine.compressorSnapshot().gainReduction > 10)
            #expect(engine.compressorSnapshot().inputEnvelope.count == 1024)
            #expect(engine.snapshot().revision == 1 && engine.snapshot().isPlaying)
            for invalid in [MasterCompressorSettings(threshold: .nan), .init(threshold: -61),
                            .init(ratio: 0), .init(attackMilliseconds: 0), .init(releaseMilliseconds: .infinity)] {
                #expect(throws: PlaybackError.invalidCompressorSettings) { try engine.setCompressor(invalid) }
                #expect(engine.compressorSettings == settings)
            }
            try engine.setCompressor(.defaults)
            let restored = try rms()
            #expect(abs(restored - dry) < dry * 0.02)
            #expect(engine.compressorSnapshot().gainReduction == 0)
            engine.stop()
            #expect(engine.compressorSnapshot() == .empty)
        }
    }
}
