import AVFoundation
import Testing
@testable import MusicPlaygourndCore

struct SourceUpdateTimingTests {
    @Test(.timeLimit(.minutes(1)), arguments: SourceUpdateTiming.allCases)
    func nativeCallbackHonorsTimingAndPublishesAfterFade(_ timing: SourceUpdateTiming) throws {
        let transport = AudioTransport()
        let old = loop(value: 0.2)
        let new = loop(value: 0.8, bpm: 60, beats: 8)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: old, revision: 1)
        try transport.startPlayback()
        _ = try render(transport, frames: 4_410)
        transport.beginUpdate(revision: 2)
        try transport.submit(loop: new, revision: 2, timing: timing)
        let wait: Int
        switch timing {
        case .immediate: wait = 0
        case .nextBeat: wait = 22_050 - 4_410
        case .nextBar: wait = 88_200 - 4_410
        }
        if wait > 0 {
            let waiting = try render(transport, frames: wait)
            #expect(waiting.allSatisfy { abs($0 - 0.2) < 0.00001 })
        }
        #expect(transport.snapshot().revision == 1)
        // Floating beat accumulation can place an exact boundary one sample late.
        let start = try render(transport, frames: 2)
        #expect(abs(start[0] - 0.2) < 0.00001)
        #expect(transport.snapshot().revision == 1)
        #expect(throws: (any Error).self) {
            try transport.installSwitchLoops([new], initialIndex: 0, revision: 2)
        }
        let fade = try render(transport, frames: AudioTransport.crossfadeFrames)
        #expect(abs(fade.last! - 0.8) < 0.00001)
        #expect(zip(fade, fade.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 < 0.001 })
        #expect(transport.snapshot().revision == 2)
        #expect(transport.snapshot().loop == new)
        let expectedBeat = Double(4_410 + wait) / 22_050 + Double(AudioTransport.crossfadeFrames + 2) / 44_100
        #expect(abs(transport.snapshot().beatPosition - expectedBeat) < 0.0001)
        _ = transport.drainRetiredAndRetainedIdentities()
        try transport.installSwitchLoops([new], initialIndex: 0, revision: 2)
        #expect(transport.snapshot().switchVariantIndex == 0)
        print("SOURCE UPDATE", timing.rawValue, "wait ms", Double(wait) / 44.1, "fade ms", Double(AudioTransport.crossfadeFrames) / 44.1)
    }

    @Test(.timeLimit(.minutes(1)))
    func latestEditPauseSeekAndRestartPreserveTiming() throws {
        let transport = AudioTransport()
        let old = loop(value: 0.2)
        let new = loop(value: 0.8, bpm: 180, beats: 1)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: old, revision: 1)
        try transport.startPlayback()
        _ = try render(transport, frames: 40_000)
        transport.beginUpdate(revision: 2)
        try transport.submit(loop: new, revision: 2, timing: .immediate)
        transport.beginUpdate(revision: 3)
        #expect(throws: (any Error).self) { try transport.submit(loop: new, revision: 2, timing: .immediate) }
        #expect(try render(transport, frames: 10).allSatisfy { $0 == 0.2 })
        try transport.submit(loop: new, revision: 3, timing: .immediate)
        try transport.seek(bySeconds: 0.1)
        let phase = transport.snapshot().beatPosition
        _ = try render(transport, frames: AudioTransport.crossfadeFrames)
        #expect(transport.snapshot().revision == 3)
        #expect(abs(transport.snapshot().beatPosition - (phase + 0.09).truncatingRemainder(dividingBy: 1)) < 0.0001)
        _ = transport.drainRetiredAndRetainedIdentities()
        transport.beginUpdate(revision: 4)
        try transport.submit(loop: old, revision: 4, timing: .nextBeat)
        try transport.restartFromBeginning()
        _ = try render(transport, frames: 14_700)
        #expect(transport.snapshot().revision == 3)
        _ = try render(transport, frames: AudioTransport.crossfadeFrames + 2)
        #expect(transport.snapshot().revision == 4)
        transport.stopPlayback()
        transport.beginUpdate(revision: 5)
        try transport.submit(loop: new, revision: 5, timing: .nextBar)
        #expect(try render(transport, frames: 256).allSatisfy { $0 == 0 })
        try transport.startPlayback()
        #expect(transport.snapshot().revision == 5)
        #expect(try render(transport, frames: 1)[0] == 0.8)
    }

    @Test(.timeLimit(.minutes(1)))
    func crossfadeReadsIndependentPCMClocksAcrossDifferentLoopLengths() throws {
        let transport = AudioTransport()
        func ramp(count: Int, bpm: Double, beats: Double, scale: Float) -> PreparedLoop {
            var pcm: [Float] = []
            for index in 0..<count {
                let value = scale * Float(index) / Float(count)
                pcm.append(value)
                pcm.append(-value)
            }
            return PreparedLoop(sampleRate: 44_100, bpm: bpm, beatsPerBar: 4, beatCount: beats, samples: pcm, events: [])
        }
        let old = ramp(count: 88_200, bpm: 120, beats: 4, scale: 0.4)
        let new = ramp(count: 14_700, bpm: 180, beats: 1, scale: 0.8)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: old, revision: 1)
        try transport.startPlayback()
        _ = try render(transport, frames: 40_000)
        let beat = transport.positionSnapshot().accumulatedBeatPosition
        let firstNewFrame = Int((beat.truncatingRemainder(dividingBy: 1) * 14_700).rounded(.down))
        transport.beginUpdate(revision: 2)
        try transport.submit(loop: new, revision: 2, timing: .immediate)
        let actual = try render(transport, frames: AudioTransport.crossfadeFrames)
        for frame in actual.indices {
            let mix = Float(frame) / Float(AudioTransport.crossfadeFrames - 1)
            let oldValue = 0.4 * Float(40_000 + frame) / 88_200
            let newValue = 0.8 * Float((firstNewFrame + frame) % 14_700) / 14_700
            #expect(abs(actual[frame] - (oldValue * (1 - mix) + newValue * mix)) < 0.00001)
        }
    }

    private func loop(value: Float, bpm: Double = 120, beats: Double = 4) -> PreparedLoop {
        let count = Int((beats * 60 / bpm * 44_100).rounded(.up))
        return PreparedLoop(sampleRate: 44_100, bpm: bpm, beatsPerBar: 4, beatCount: beats,
            samples: [Float](repeating: value, count: count * 2), events: [])
    }

    private func render(_ transport: AudioTransport, frames: Int) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        var samples: [Float] = []
        while samples.count < frames {
            let count = min(1_024, frames - samples.count)
            buffer.frameLength = AVAudioFrameCount(count)
            #expect(transport.render(frameCount: count, audioBufferList: buffer.mutableAudioBufferList) == noErr)
            let channels = try #require(buffer.floatChannelData)
            samples.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
        }
        return samples
    }
}
