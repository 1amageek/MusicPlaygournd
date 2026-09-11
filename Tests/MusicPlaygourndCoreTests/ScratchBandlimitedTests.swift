import AVFoundation
import Foundation
import Testing
@testable import MusicPlaygourndCore

struct ScratchBandlimitedTests {
    private func tone(_ frequency: Double) -> [Float] {
        var pcm = [Float](repeating: 0, count: 88_200)
        for frame in 0..<44_100 {
            pcm[frame * 2] = Float(0.3 * sin(Double(frame) * 2 * .pi * frequency / 44_100))
            pcm[frame * 2 + 1] = -pcm[frame * 2]
        }
        return pcm
    }

    @Test(.timeLimit(.minutes(1)))
    func fastHandInputPreservesDistanceWhileReadSpeedStaysBounded() throws {
        for direction in [-1.0, 1.0] {
            let transport = AudioTransport()
            let loop = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 2,
                samples: tone(440), events: [])
            transport.beginUpdate(revision: 1)
            try transport.submit(loop: loop, revision: 1)
            try transport.seek(bySeconds: 0.5)
            // A 400x input used to throw, although the position servo can track it safely.
            try transport.scratch(bySeconds: direction * 0.4, over: 0.001)
            let start = transport.positionSnapshot().accumulatedBeatPosition
            _ = try render(transport, frames: 100)
            let moved = abs(transport.positionSnapshot().accumulatedBeatPosition - start)
            #expect(moved <= 32 * 100 * 2 / 44_100.0 + 1e-9)
            _ = try render(transport, frames: 8000)
            #expect(abs(transport.positionSnapshot().accumulatedBeatPosition - (1 + direction * 0.8)) < 1e-8)
            transport.releaseScratch()
            let coast = try render(transport, frames: 1000)
            #expect(coast.allSatisfy { $0.isFinite })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func heldPositionReturnsExactlyAcrossRatesAndCallbackPartitions() throws {
        let loop = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 2, samples: tone(440), events: [])
        for rate in [0.5, 1, 2] {
            for chunk in [127, 512] {
                let transport = AudioTransport()
                transport.beginUpdate(revision: 1)
                try transport.submit(loop: loop, revision: 1)
                try transport.seek(bySeconds: 0.3)
                transport.setClockRate(rate)
                try transport.scratch(bySeconds: 0.1, over: 0.1)
                for _ in 0..<100 { _ = try render(transport, frames: chunk) }
                #expect(abs(transport.snapshot().beatPosition - 0.8) < 1e-8)
                try transport.scratch(bySeconds: -0.1, over: 0.03)
                for _ in 0..<100 { _ = try render(transport, frames: chunk) }
                #expect(abs(transport.snapshot().beatPosition - 0.6) < 1e-8)
                #expect(try render(transport, frames: 512).allSatisfy { $0 == 0 })
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func speedDependentFilteringRejectsAliasedTonesAndPreservesStereo() {
        let resampler = ScratchResampler()
        for speed in [0.5, 1.5, 4.0, -4.0, 32.0] {
            let pass = tone(200)
            let stop = tone(speed == 0.5 ? 20_000 : ceil(22_050 / abs(speed) * 1.05))
            func power(_ pcm: [Float]) -> Double {
                pcm.withUnsafeBytes { bytes in
                    var sum = 0.0
                    for index in 0..<2048 {
                        let raw = (123.25 + Double(index) * speed).truncatingRemainder(dividingBy: 44_100)
                        let value = resampler.sample(pcm: bytes, position: raw < 0 ? raw + 44_100 : raw, speed: speed)
                        #expect(value.0.isFinite && value.1 == -value.0)
                        sum += Double(value.0 * value.0)
                    }
                    return sum / 2048
                }
            }
            let passPower = power(pass)
            #expect(passPower > 0.035 && passPower < 0.055)
            if abs(speed) > 1 {
                let rejection = 10 * log10(power(stop) / passPower)
                print("SCRATCH ALIAS dB", speed, rejection)
                #expect(rejection < -50)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func eventGapsReversalAndCancellationStayContinuous() throws {
        let transport = AudioTransport()
        let loop = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 2, samples: tone(440), events: [])
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: loop, revision: 1)
        var samples: [Float] = []
        for _ in 0..<20 {
            try transport.scratch(bySeconds: 0.01, over: 0.01)
            samples = try render(transport, frames: 512)
        }
        // The former 441-frame ticket produced 71 abruptly zeroed samples here.
        #expect(samples[441..<512].filter { $0 == 0 }.count < 2)
        try transport.scratch(bySeconds: -0.01, over: 0.01)
        samples += try render(transport, frames: 1024)
        let jump = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        print("SCRATCH REVERSAL maximum sample jump", jump)
        #expect(jump < 0.025)
        let beforeFailure = transport.snapshot()
        #expect(throws: PlaybackError.invalidScratchMotion) { try transport.scratch(bySeconds: .greatestFiniteMagnitude, over: 0.01) }
        #expect(transport.snapshot() == beforeFailure)
        transport.endScratch()
        samples = try render(transport, frames: 512)
        #expect(samples.suffix(200).allSatisfy { $0 == 0 })
        #expect(!transport.isScratching && !transport.snapshot().isPlaying)
        try transport.scratch(bySeconds: 0.01, over: 0.01)
        _ = try render(transport, frames: 10_000)
        #expect(try render(transport, frames: 512).allSatisfy { $0 == 0 })
        // Immediate abort is reserved for failed native output startup.
        transport.endScratch(immediate: true)
        #expect(!transport.isScratching)
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedPCMAndShortLoopsUseTheSameBoundedBorrow() throws {
        let resampler = ScratchResampler()
        let pcm = tone(1000)
        let owner = try pcm.withUnsafeBytes { try PCMBuffer(bytes: Data($0)) }
        let mapped = owner.withLittleEndianBytes { resampler.sample(pcm: $0, position: 44_099.75, speed: -4) }
        let array = pcm.withUnsafeBytes { resampler.sample(pcm: $0, position: 44_099.75, speed: -4) }
        #expect(mapped.0 == array.0 && mapped.1 == array.1)
        let tiny: [Float] = [0.2, -0.2]
        let dc = tiny.withUnsafeBytes { resampler.sample(pcm: $0, position: 0.5, speed: 32) }
        #expect(abs(dc.0 - 0.2) < 0.00001 && abs(dc.1 + 0.2) < 0.00001)
    }

    @Test(.timeLimit(.minutes(1)))
    func maximumSpeedCallbackCost() throws {
        let a = AudioTransport(), b = AudioTransport()
        let loop = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 2, samples: tone(440), events: [])
        for transport in [a, b] {
            transport.beginUpdate(revision: 1)
            try transport.submit(loop: loop, revision: 1)
            try transport.scratch(bySeconds: 3.2, over: 0.1)
            _ = try render(transport, frames: 4410)
        }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        var times: [Double] = []
        for _ in 0..<7 {
            try a.scratch(bySeconds: 3.2, over: 0.1)
            try b.scratch(bySeconds: 3.2, over: 0.1)
            let start = ProcessInfo.processInfo.systemUptime
            let first = a.render(frameCount: 512, audioBufferList: buffer.mutableAudioBufferList)
            let second = b.render(frameCount: 512, audioBufferList: buffer.mutableAudioBufferList)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            #expect(first == noErr && second == noErr)
        }
        print("SCRATCH TWO DECK 32x 512 frames ms", times.sorted(), "budget ms", 512.0 / 44.1)
    }

    private func render(_ transport: AudioTransport, frames: Int) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var samples: [Float] = []
        while samples.count < frames {
            let count = min(1024, frames - samples.count)
            buffer.frameLength = AVAudioFrameCount(count)
            #expect(transport.render(frameCount: count, audioBufferList: buffer.mutableAudioBufferList) == noErr)
            samples.append(contentsOf: UnsafeBufferPointer(start: try #require(buffer.floatChannelData)[0], count: count))
        }
        return samples
    }
}
