import AVFoundation
import Synchronization

/// The render callback retains this owner, never an audio buffer or UI object.
final class OutputMeter: Sendable {
    private let callbacks = Atomic<UInt64>(0)
    private let peakBits = Atomic<UInt32>(0)

    var callbackCount: UInt64 { callbacks.load(ordering: .relaxed) }
    var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }

    func observe(_ buffer: AVReadOnlyAudioPCMBuffer) {
        var peak: Float = 0
        for channel in 0..<min(Int(buffer.format.channelCount), 2) {
            guard case .float(let samples) = buffer.channelData(channel) else { return }
            for frame in 0..<min(buffer.frameLength, 4096) {
                let value = abs(samples[frame])
                if value.isFinite { peak = max(peak, value) }
            }
        }
        peakBits.max(peak.bitPattern, ordering: .relaxed)
        callbacks.wrappingAdd(1, ordering: .relaxed)
    }

    func reset() {
        callbacks.store(0, ordering: .relaxed)
        peakBits.store(0, ordering: .relaxed)
    }
}
