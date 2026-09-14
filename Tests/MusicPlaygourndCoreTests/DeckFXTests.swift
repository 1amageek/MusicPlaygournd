import AVFoundation
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct DeckFXTests {
        private func input(_ i: Int) -> Float {
            Float(0.15 * sin(Double(i) * 2 * .pi * 440 / 44100)
                + 0.1 * sin(Double(i) * 2 * .pi * 1700 / 44100))
        }

        @Test(.timeLimit(.minutes(1)))
        func streamingEffectsPartitionBypassAndValidation() throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
            let channels = try #require(buffer.floatChannelData)
            func render(_ kernel: DeckFXKernel, count: Int, block: Int) throws -> [Float] {
                var result: [Float] = []
                var offset = 0
                while offset < count {
                    let frames = min(block, count - offset)
                    buffer.frameLength = AVAudioFrameCount(frames)
                    for i in 0..<frames { channels[0][i] = input(offset + i); channels[1][i] = channels[0][i] }
                    #expect(kernel.process(buffer.mutableAudioBufferList, frames: frames) == noErr)
                    for i in 0..<frames { result.append(channels[0][i]); result.append(channels[1][i]) }
                    offset += frames
                }
                return result
            }
            for kind in DeckFXSettings.Kind.allCases {
                let whole = DeckFXKernel(), split = DeckFXKernel()
                let settings = DeckFXSettings(enabled: true, kind: kind, rate: 16, depth: 0.8, mix: 0.7)
                try whole.configure(settings); try split.configure(settings)
                let a = try render(whole, count: 16384, block: 4096)
                let b = try render(split, count: 16384, block: 127)
                #expect(a == b)
                #expect(a.allSatisfy { $0.isFinite })
                #expect((2000..<16000).contains { abs(a[$0 * 2] - input($0)) > 0.03 })
                if kind == .chorus { #expect((2000..<16000).contains { abs(a[$0 * 2] - a[$0 * 2 + 1]) > 0.01 }) }
                var changed = settings; changed.rate = 7; changed.depth = 0.1; changed.feedback = 0.8
                try whole.configure(changed)
                #expect(try render(whole, count: 8192, block: 4096) != render(split, count: 8192, block: 4096))
                changed.kind = kind == .phaser ? .flanger : .phaser
                try whole.configure(changed)
                let switched = try render(whole, count: 4096, block: 127)
                #expect(switched.allSatisfy { $0.isFinite })
                #expect(zip(switched.dropFirst(2), switched).allSatisfy { abs($0 - $1) < 0.5 })
                try whole.configure(.defaults)
                let dry = try render(whole, count: 4096, block: 4096)
                #expect((1024..<4096).allSatisfy { dry[$0 * 2] == input($0) })
                // A fully bypassed history cannot leak into reactivation.
                let fresh = DeckFXKernel()
                try whole.configure(settings); try fresh.configure(settings)
                whole.resetHistory(); fresh.resetHistory()
                #expect(try render(whole, count: 4096, block: 4096) == render(fresh, count: 4096, block: 4096))
            }
            let kernel = DeckFXKernel()
            for invalid in [DeckFXSettings(rate: .nan), .init(depth: -1), .init(feedback: 0.9), .init(mix: .infinity)] {
                #expect(throws: PlaybackError.invalidDeckFXSettings) { try kernel.configure(invalid) }
            }
            buffer.frameLength = 4096
            channels[0][0] = .nan
            #expect(kernel.process(buffer.mutableAudioBufferList, frames: 4096) == kAudioUnitErr_InvalidPropertyValue)
            #expect(kernel.process(buffer.mutableAudioBufferList, frames: 4097) == kAudioUnitErr_TooManyFramesToProcess)
        }

        @Test(.timeLimit(.minutes(1)))
        func nativeGraphAndDeckIsolation() throws {
            func render(_ settings: DeckFXSettings, muteA: Bool = false) throws -> [Float] {
                let output = try AudioOutput()
                let a = try AudioLoopEngine(output: output), b = try AudioLoopEngine(output: output)
                defer { a.stop(); b.stop() }
                var samples: [Float] = []
                for i in 0..<88200 { samples.append(input(i)); samples.append(input(i) * 0.7) }
                let loop = PreparedLoop(sampleRate: 44100, bpm: 120, beatsPerBar: 4, beatCount: 4, samples: samples, events: [])
                for engine in [a, b] { engine.beginUpdate(revision: 1); try engine.submit(loop: loop, revision: 1) }
                try a.setDeckGain(muteA ? 0 : 1)
                try b.setDeckGain(muteA ? 1 : 0)
                try a.prepareOfflineRenderingForTests()
                try a.play(); try b.play()
                try a.setFX(settings)
                #expect(b.fxSettings == .defaults)
                #expect(throws: PlaybackError.invalidDeckFXSettings) { try a.setFX(.init(rate: -1)) }
                #expect(a.fxSettings == settings)
                var result: [Float] = []
                for _ in 0..<6 { result += try a.renderOfflineForTests(frameCount: 4096) }
                #expect(a.snapshot().revision == 1 && a.snapshot().isPlaying && b.snapshot().isPlaying)
                return result
            }
            let dry = try render(.defaults)
            for kind in DeckFXSettings.Kind.allCases {
                let wet = try render(.init(enabled: true, kind: kind, mix: 0.8))
                #expect(zip(dry, wet).reduce(0.0) { $0 + Double(abs($1.0 - $1.1)) } / Double(dry.count) > 0.01)
            }
            let bDry = try render(.defaults, muteA: true)
            let bWithAEffect = try render(.init(enabled: true, kind: .flanger), muteA: true)
            #expect(zip(bDry, bWithAEffect).allSatisfy { abs($0 - $1) < 0.00001 })
        }
    }
}
