import AVFoundation
import SwiftMusic
import Synchronization

/// Owns streaming dynamics and bounded display envelopes under one isolation boundary.
final class MasterCompressorKernel: Sendable {
    static let binCount = 512
    static let framesPerBin = 16

    private struct State {
        var settings = MasterCompressorSettings.defaults
        var processor: DynamicsProcessor
        var detector = 0.0
        var reduction = 0.0
        var input = [Float](repeating: 0, count: binCount * 2)
        var output = [Float](repeating: 0, count: binCount * 2)
        var cursor = 0
        var count = 0
        var binFrames = 0
        var inputLow: Float = 0
        var inputHigh: Float = 0
        var outputLow: Float = 0
        var outputHigh: Float = 0
    }
    private let state: Mutex<State>

    init() throws {
        state = Mutex(State(processor: try Self.processor(for: .defaults)))
    }

    private static func processor(for value: MasterCompressorSettings) throws -> DynamicsProcessor {
        try value.validate()
        return try DynamicsProcessor(.sidechainCompressor(SidechainCompressor(
            threshold: Decibels(value: value.threshold), ratio: value.ratio,
            attack: .milliseconds(value.attackMilliseconds),
            release: .milliseconds(value.releaseMilliseconds),
            knee: Decibels(value: 0))))
    }

    func configure(_ value: MasterCompressorSettings) throws {
        let processor = try Self.processor(for: value)
        state.withLock { state in
            state.settings = value
            state.processor = processor
            if !value.enabled { state.detector = 0; state.reduction = 0 }
        }
    }

    func resetHistory() {
        state.withLock { state in
            state.detector = 0; state.reduction = 0
            state.cursor = 0; state.count = 0; state.binFrames = 0
            state.inputLow = 0; state.inputHigh = 0
            state.outputLow = 0; state.outputHigh = 0
        }
    }

    func snapshot() -> MasterCompressorSnapshot {
        state.withLock { state in
            // The UI owns these bounded copies; render-owned arrays never share COW backing.
            var input = [Float](repeating: 0, count: state.count * 2)
            var output = input
            let first = (state.cursor + Self.binCount - state.count) % Self.binCount
            for index in 0..<state.count {
                let source = ((first + index) % Self.binCount) * 2
                input[index * 2] = state.input[source]
                input[index * 2 + 1] = state.input[source + 1]
                output[index * 2] = state.output[source]
                output[index * 2 + 1] = state.output[source + 1]
            }
            return MasterCompressorSnapshot(inputEnvelope: input, outputEnvelope: output,
                                            gainReduction: state.reduction)
        }
    }

    func process(_ data: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> OSStatus {
        guard (0...4096).contains(frames) else { return kAudioUnitErr_TooManyFramesToProcess }
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        let bytes = frames * MemoryLayout<Float>.stride
        guard buffers.count == 2,
              buffers.allSatisfy({ $0.mNumberChannels == 1 && $0.mData != nil && Int($0.mDataByteSize) >= bytes }) else {
            return kAudioUnitErr_FormatNotSupported
        }
        // The upstream AU owns initialized, aligned noninterleaved Float32 buffers.
        // These callback-local borrows never escape and no raw memory is retained.
        let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
        let right = buffers[1].mData!.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            guard left[frame].isFinite, right[frame].isFinite else { return kAudioUnitErr_InvalidPropertyValue }
        }
        return state.withLock { state in
            do {
                for frame in 0..<frames {
                    let l = left[frame], r = right[frame]
                    let gain = state.settings.enabled
                        ? try state.processor.step(peak: Double(max(abs(l), abs(r))), state: &state.detector) : 1
                    left[frame] = l * Float(gain)
                    right[frame] = r * Float(gain)
                    state.reduction = gain > 0 ? -20 * log10(gain) : 0
                    state.inputLow = min(state.inputLow, l, r)
                    state.inputHigh = max(state.inputHigh, l, r)
                    state.outputLow = min(state.outputLow, left[frame], right[frame])
                    state.outputHigh = max(state.outputHigh, left[frame], right[frame])
                    state.binFrames += 1
                    if state.binFrames == Self.framesPerBin {
                        let index = state.cursor * 2
                        state.input[index] = state.inputLow; state.input[index + 1] = state.inputHigh
                        state.output[index] = state.outputLow; state.output[index + 1] = state.outputHigh
                        state.cursor = (state.cursor + 1) % Self.binCount
                        state.count = min(Self.binCount, state.count + 1)
                        state.binFrames = 0
                        state.inputLow = 0; state.inputHigh = 0
                        state.outputLow = 0; state.outputHigh = 0
                    }
                }
                return noErr
            } catch {
                return kAudioUnitErr_InvalidPropertyValue
            }
        }
    }
}
