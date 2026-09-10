import AVFoundation
import Synchronization

/// One bounded copy bridges two hardware clocks. All borrows end inside callbacks.
final class CueAudioBuffer: Sendable {
    static let capacity = 8192
    private struct State {
        var samples = [Float](repeating: 0, count: capacity * 2)
        var written = 0
        var read = 0.0
        var primed = false
        var enabled = false
    }
    private let state = Mutex(State())

    func reset(enabled: Bool) {
        state.withLock { $0.written = 0; $0.read = 0; $0.primed = false; $0.enabled = enabled }
    }

    func capture(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved, buffer.format.channelCount == 2,
              let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        state.withLock { state in
            guard state.enabled else { return }
            // Only the newest capacity frames are useful after an overrun.
            for frame in max(0, frames - Self.capacity)..<frames {
                let slot = state.written % Self.capacity
                state.samples[slot * 2] = channels[0][frame]
                state.samples[slot * 2 + 1] = channels[1][frame]
                state.written += 1
            }
            if Double(state.written) - state.read > Double(Self.capacity) {
                state.read = Double(state.written - 1024)
                state.primed = false
            }
        }
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) -> OSStatus {
        guard frames >= 0, frames <= Self.capacity, buffers.count == 2,
              buffers.allSatisfy({ $0.mNumberChannels == 1 && Int($0.mDataByteSize) >= frames * MemoryLayout<Float>.stride && $0.mData != nil }) else {
            return kAudio_ParamError
        }
        // AVAudioSourceNode supplies initialized, aligned noninterleaved Float32 buffers.
        let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
        let right = buffers[1].mData!.assumingMemoryBound(to: Float.self)
        state.withLock { state in
            let available = Double(state.written) - state.read
            if !state.primed && available >= 1024 { state.primed = true }
            let step = 1 + min(0.005, max(-0.005, (available - 1024) / 204800))
            for frame in 0..<frames {
                guard state.enabled, state.primed, state.read + 1 < Double(state.written) else {
                    left[frame] = 0; right[frame] = 0
                    state.primed = false
                    continue
                }
                let index = Int(state.read)
                let fraction = Float(state.read - Double(index))
                let a = (index % Self.capacity) * 2
                let b = ((index + 1) % Self.capacity) * 2
                left[frame] = state.samples[a] + (state.samples[b] - state.samples[a]) * fraction
                right[frame] = state.samples[a + 1] + (state.samples[b + 1] - state.samples[a + 1]) * fraction
                state.read += step
            }
        }
        return noErr
    }
}
