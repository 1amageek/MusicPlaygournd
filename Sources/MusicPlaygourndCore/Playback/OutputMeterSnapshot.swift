import Foundation

/// A bounded stereo snapshot copied after the playback effects graph.
public struct OutputMeterSnapshot: Sendable, Equatable {
    public let interleavedSamples: [Float]
    public let performance: PlaybackPerformanceSnapshot?
    public let sampleRate: Double
    public let sequence: UInt64

    public init(interleavedSamples: [Float], sampleRate: Double, performance: PlaybackPerformanceSnapshot? = nil, sequence: UInt64 = 0) {
        self.interleavedSamples = interleavedSamples
        self.sampleRate = sampleRate
        self.sequence = sequence
        self.performance = performance
    }
}
