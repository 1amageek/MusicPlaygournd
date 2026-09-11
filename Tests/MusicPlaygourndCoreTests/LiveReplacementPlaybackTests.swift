import AVFoundation
import Testing
@testable import MusicPlaygourndCore

struct LiveReplacementPlaybackTests {
    @Test(.timeLimit(.minutes(3)))
    func replacementCrossfadesAtCurrentPhaseAndKeepsOnlyLatestPending() throws {
        let transport = AudioTransport()
        let first = loop(scale: 0.2), second = loop(scale: 0.6)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: first, revision: 1)
        try transport.startPlayback()
        _ = try render(transport, frames: 87_700)
        let beat = transport.positionSnapshot().accumulatedBeatPosition
        try transport.replace(loop: second, revision: 1, generation: 1)
        try transport.replace(loop: loop(scale: 0.7), revision: 1, generation: 2)
        try transport.replace(loop: loop(scale: 0.8), revision: 1, generation: 3)
        #expect(transport.snapshot().overrideGeneration == 1)
        let pcm = try render(transport, frames: AudioTransport.crossfadeFrames)
        var maximumError: Float = 0
        for index in pcm.indices {
            let frame = (87_700 + index) % 88_200
            let weight = Float(index) / Float(AudioTransport.crossfadeFrames - 1)
            let expected = first.samples[frame * 2] * (1 - weight) + second.samples[frame * 2] * weight
            maximumError = max(maximumError, abs(pcm[index] - expected))
        }
        #expect(maximumError < 0.000001)
        #expect(abs(transport.positionSnapshot().accumulatedBeatPosition - beat - 0.06) < 0.000001)
        // A retired slot prevents starting another fade before the host drains ownership.
        _ = try render(transport, frames: 1)
        #expect(transport.snapshot().overrideGeneration == 1)
        let retained = transport.drainRetiredAndRetainedIdentities()
        #expect(retained.count == 2)
        #expect(!retained.contains(.init(revision: 1, generation: 2)))
        _ = try render(transport, frames: AudioTransport.crossfadeFrames)
        #expect(transport.snapshot().overrideGeneration == 3)
        #expect(transport.snapshot().revision == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func invalidReplacementPreservesStateAndCodeAdoptionInvalidatesGeneration() throws {
        let transport = AudioTransport()
        transport.beginUpdate(revision: 4)
        try transport.submit(loop: loop(scale: 0.2), revision: 4)
        try transport.startPlayback()
        _ = try render(transport, frames: 88_190)
        try transport.replace(loop: loop(scale: 0.5), revision: 4, generation: 7)
        let before = transport.snapshot()
        #expect(throws: PlaybackError.staleOverrideGeneration(7)) {
            try transport.replace(loop: loop(scale: 0.8), revision: 4, generation: 7)
        }
        #expect(throws: PlaybackError.incompatibleReplacement) {
            try transport.replace(loop: loop(scale: 0.8, bpm: 60), revision: 4, generation: 8)
        }
        #expect(transport.snapshot() == before)
        transport.beginUpdate(revision: 5)
        try transport.submit(loop: loop(scale: 0.3), revision: 5)
        _ = try render(transport, frames: AudioTransport.crossfadeFrames)
        #expect(transport.snapshot().revision == 4)
        // The host drains retired PCM off callback before a source fade can begin.
        _ = transport.drainRetiredAndRetainedIdentities()
        _ = try render(transport, frames: AudioTransport.crossfadeFrames)
        #expect(transport.snapshot().revision == 5)
        #expect(transport.snapshot().overrideGeneration == 0)
        #expect(throws: PlaybackError.staleRevision(4)) {
            try transport.replace(loop: loop(scale: 0.8), revision: 4, generation: 9)
        }
        try transport.replace(loop: loop(scale: 0.8), revision: 5, generation: 1)
        transport.stopPlayback()
        #expect(transport.snapshot().overrideGeneration == 1)
        #expect(transport.drainRetiredAndRetainedIdentities().count == 1)
        #expect(try render(transport, frames: 8).allSatisfy { $0 == 0 })
    }

    @Test(.timeLimit(.minutes(3)))
    func replacementAllowsAudibleMetadataButRejectsChangedEventIdentity() throws {
        let transport = AudioTransport()
        let base = loop(scale: 0.2)
        func value(start: Double, gain: Double, peak: Float) -> PreparedLoop {
            PreparedLoop(sampleRate: base.sampleRate, bpm: base.bpm,
                beatsPerBar: base.beatsPerBar, beatCount: base.beatCount, samples: base.samples,
                events: [LoopEvent(sourceID: 0, label: "Voice", startBeat: start,
                    durationBeats: gain, midiNote: 60, velocity: 100, patternStepIndex: 0, gain: gain)],
                rows: [LoopRow(sourceID: 0, label: "Voice", anchor: nil, peaks: [peak])])
        }
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: value(start: 0, gain: 1, peak: 0.2), revision: 1)
        try transport.replace(loop: value(start: 0, gain: 0.5, peak: 0.1), revision: 1, generation: 1)
        #expect(transport.snapshot().loop?.events.first?.gain == 0.5)
        #expect(transport.snapshot().loop?.rows.first?.peaks.first == 0.1)
        #expect(throws: PlaybackError.incompatibleReplacement) {
            try transport.replace(loop: value(start: 1, gain: 0.5, peak: 0.1), revision: 1, generation: 2)
        }
        #expect(transport.snapshot().overrideGeneration == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func seekMovesPCMAndPreservesPausedState() throws {
        let transport = AudioTransport()
        #expect(throws: PlaybackError.noCurrentLoop) { try transport.seek(bySeconds: 1) }
        let source = loop(scale: 0.8)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: source, revision: 1)
        try transport.seek(bySeconds: 0.5)
        #expect(!transport.snapshot().isPlaying)
        #expect(abs(transport.snapshot().beatPosition - 1) < 0.00001)
        try transport.startPlayback()
        #expect(abs(try render(transport, frames: 1)[0] - source.samples[22_050 * 2]) < 0.00001)
        try transport.seek(bySeconds: -1)
        #expect(transport.snapshot().isPlaying)
        #expect(abs(transport.snapshot().beatPosition - (3 + 2.0 / 44_100)) < 0.00001)
        #expect(abs(try render(transport, frames: 1)[0] - source.samples[66_151 * 2]) < 0.00001)
        let before = transport.snapshot()
        #expect(throws: PlaybackError.invalidSeekOffset) { try transport.seek(bySeconds: .infinity) }
        #expect(transport.snapshot() == before)
        transport.stopPlayback()
        try transport.seek(bySeconds: 2)
        #expect(!transport.snapshot().isPlaying)
        #expect(abs(transport.snapshot().beatPosition - before.beatPosition) < 0.00001)
    }

    @Test(.timeLimit(.minutes(1)))
    func scratchRendersReversePCMWhilePausedAndRestoresTransportIntent() throws {
        let transport = AudioTransport()
        #expect(throws: PlaybackError.noCurrentLoop) { try transport.scratch(bySeconds: 0.1, over: 0.1) }
        let source = loop(scale: 0.8)
        transport.beginUpdate(revision: 1)
        try transport.submit(loop: source, revision: 1)
        try transport.scratch(bySeconds: -8.0 / 44_100, over: 4.0 / 44_100)
        #expect(!transport.snapshot().isPlaying && transport.isScratching)
        let reverse = try render(transport, frames: 4)
        for (index, frame) in [0, 88_198, 88_196, 88_194].enumerated() {
            #expect(abs(reverse[index] - source.samples[frame * 2]) < 0.00001)
        }
        #expect(try render(transport, frames: 8).allSatisfy { $0 == 0 })
        let before = transport.snapshot()
        for interval in [0.0, -1, .infinity, 0.3] {
            #expect(throws: PlaybackError.invalidScratchMotion) {
                try transport.scratch(bySeconds: 1, over: interval)
            }
        }
        #expect(throws: PlaybackError.invalidScratchMotion) {
            try transport.scratch(bySeconds: .nan, over: 0.1)
        }
        #expect(transport.snapshot() == before)
        #expect(throws: PlaybackClockError.unavailable) { try transport.clockAnchor(presentationLatency: 0) }
        #expect(throws: PlaybackError.replacementInProgress) {
            try transport.replace(loop: source, revision: 1, generation: 1)
        }
        try transport.scratch(bySeconds: 0, over: 0.1)
        #expect(try render(transport, frames: 8).allSatisfy { $0 == 0 })
        transport.endScratch()
        #expect(!transport.snapshot().isPlaying && !transport.isScratching)
        #expect(try render(transport, frames: 8).allSatisfy { $0 == 0 })
        try transport.startPlayback()
        try transport.scratch(bySeconds: 2.0 / 44_100, over: 4.0 / 44_100)
        let forward = try render(transport, frames: 4)
        #expect(abs(forward[0] - source.samples[88_192 * 2]) < 0.00001)
        #expect(abs(forward[1] - (source.samples[88_192 * 2] + source.samples[88_193 * 2]) / 2) < 0.00001)
        #expect(transport.snapshot().isPlaying)
        transport.endScratch()
        let resumed = try render(transport, frames: 2)
        #expect(abs(resumed[0] - source.samples[88_194 * 2]) < 0.00002)
        #expect(abs(resumed[1] - source.samples[88_195 * 2]) < 0.00002)
        try transport.scratch(bySeconds: 0.1, over: 0.1)
        transport.stopPlayback()
        #expect(!transport.isScratching)
        #expect(try render(transport, frames: 8).allSatisfy { $0 == 0 })
        try transport.scratch(bySeconds: 2, over: 0.1)
        #expect(try render(transport, frames: 4).contains { abs($0) > 0.01 })
        transport.endScratch()
    }

    private func loop(scale: Float, bpm: Double = 120) -> PreparedLoop {
        var samples = [Float](repeating: 0, count: 88_200 * 2)
        for frame in 0..<88_200 {
            let value = scale * Float(frame % 100) / 100
            samples[frame * 2] = value
            samples[frame * 2 + 1] = -value
        }
        return PreparedLoop(sampleRate: 44_100, bpm: bpm, beatsPerBar: 4,
                            beatCount: 4, samples: samples, events: [])
    }

    private func render(_ transport: AudioTransport, frames: Int) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        var result: [Float] = []
        result.reserveCapacity(frames)
        while result.count < frames {
            let count = min(1_024, frames - result.count)
            buffer.frameLength = AVAudioFrameCount(count)
            #expect(transport.render(frameCount: count, audioBufferList: buffer.mutableAudioBufferList) == noErr)
            let data = try #require(buffer.floatChannelData)
            for index in 0..<count { result.append(data[0][index]) }
        }
        return result
    }
}
