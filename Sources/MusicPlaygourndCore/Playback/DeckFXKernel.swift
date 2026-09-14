import AVFoundation
import Synchronization

/// Streaming modulation owns its preallocated histories; no PCM is retained or copied.
final class DeckFXKernel: Sendable {
    private struct State {
        var target = DeckFXSettings.defaults
        var kind = DeckFXSettings.Kind.phaser
        var rate = 0.5
        var depth = 0.7
        var feedback = 0.3
        var wet = 0.0
        var phase = 0.0
        var leftDelay = ModulationProcessor.DelayState(ring: [Double](repeating: 0, count: 2048))
        var rightDelay = ModulationProcessor.DelayState(ring: [Double](repeating: 0, count: 2048))
        var leftPhaser = ModulationProcessor.PhaserState(inputs: [Double](repeating: 0, count: 6), outputs: [Double](repeating: 0, count: 6))
        var rightPhaser = ModulationProcessor.PhaserState(inputs: [Double](repeating: 0, count: 6), outputs: [Double](repeating: 0, count: 6))

        mutating func clear() {
            for i in leftDelay.ring.indices { leftDelay.ring[i] = 0; rightDelay.ring[i] = 0 }
            leftDelay.write = 0; rightDelay.write = 0
            for i in leftPhaser.inputs.indices {
                leftPhaser.inputs[i] = 0; leftPhaser.outputs[i] = 0
                rightPhaser.inputs[i] = 0; rightPhaser.outputs[i] = 0
            }
            leftPhaser.feedbackSample = 0; rightPhaser.feedbackSample = 0
            phase = 0
        }
    }
    private let state = Mutex(State())

    func configure(_ value: DeckFXSettings) throws {
        try value.validate()
        state.withLock { $0.target = value }
    }

    func resetHistory() {
        state.withLock { s in
            s.clear(); s.kind = s.target.kind; s.wet = 0
            s.rate = s.target.rate; s.depth = s.target.depth; s.feedback = s.target.feedback
        }
    }

    func process(_ data: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> OSStatus {
        guard (0...4096).contains(frames) else { return kAudioUnitErr_TooManyFramesToProcess }
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        guard buffers.count == 2, buffers.allSatisfy({
            $0.mNumberChannels == 1 && $0.mData != nil && Int($0.mDataByteSize) >= frames * MemoryLayout<Float>.stride
        }) else { return kAudioUnitErr_FormatNotSupported }
        // AU host owns initialized planar Float32 buffers. Bounds are checked above;
        // these aligned borrows never escape the callback and are mutated only here.
        let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
        let right = buffers[1].mData!.assumingMemoryBound(to: Float.self)
        for i in 0..<frames {
            guard left[i].isFinite, right[i].isFinite else { return kAudioUnitErr_InvalidPropertyValue }
        }
        return state.withLock { s in
            do {
                let sampleRate = PreparedLoop.requiredSampleRate
                let smoothing = 1 - exp(-1 / (0.02 * sampleRate))
                for i in 0..<frames {
                    let changing = s.kind != s.target.kind
                    let targetWet = !changing ? s.target.mix : 0
                    let previousWet = s.wet
                    s.wet += min(1 / (0.01 * sampleRate), max(-1 / (0.01 * sampleRate), targetWet - s.wet))
                    if s.wet == 0 {
                        if changing || previousWet > 0 { s.clear(); s.kind = s.target.kind }
                        // Clearing on bypass prevents stale tails on the next activation.
                        if s.target.mix == 0 { continue }
                    }
                    s.rate += (s.target.rate - s.rate) * smoothing
                    s.depth += (s.target.depth - s.depth) * smoothing
                    s.feedback += (s.target.feedback - s.feedback) * smoothing
                    let l = Double(left[i]), r = Double(right[i])
                    let wave = sin(2 * .pi * s.phase)
                    let wetL: Double, wetR: Double
                    switch s.kind {
                    case .phaser:
                        let frequency = 200 + 4800 * s.depth * (wave + 1) / 2
                        let tangent = tan(.pi * frequency / sampleRate)
                        let coefficient = (tangent - 1) / (tangent + 1)
                        wetL = try s.leftPhaser.advance(l, coefficient: coefficient, feedback: s.feedback)
                        wetR = try s.rightPhaser.advance(r, coefficient: coefficient, feedback: s.feedback)
                    case .chorus:
                        wetL = try s.leftDelay.advance(l, delay: (0.015 + 0.01 * s.depth * wave) * sampleRate, feedback: 0)
                        wetR = try s.rightDelay.advance(r, delay: (0.015 + 0.01 * s.depth * cos(2 * .pi * s.phase)) * sampleRate, feedback: 0)
                    case .flanger:
                        let delay = (0.003 + 0.002 * s.depth * wave) * sampleRate
                        wetL = try s.leftDelay.advance(l, delay: delay, feedback: s.feedback)
                        wetR = try s.rightDelay.advance(r, delay: delay, feedback: s.feedback)
                    }
                    let a = l * (1 - s.wet) + wetL * s.wet
                    let b = r * (1 - s.wet) + wetR * s.wet
                    guard a.isFinite, b.isFinite, abs(a) <= Double(Float.greatestFiniteMagnitude),
                          abs(b) <= Double(Float.greatestFiniteMagnitude) else { return kAudioUnitErr_InvalidPropertyValue }
                    left[i] = Float(a); right[i] = Float(b)
                    s.phase += s.rate / sampleRate
                    if s.phase >= 1 { s.phase -= 1 }
                }
                return noErr
            } catch { return kAudioUnitErr_InvalidPropertyValue }
        }
    }
}
