import Foundation

/// Target values for one native one-octave parametric master EQ band.
public struct MasterEqualizerBand: Sendable, Equatable {
    public var frequency: Float
    public var gain: Float

    public init(frequency: Float, gain: Float = 0) {
        self.frequency = frequency
        self.gain = gain
    }

    public static let defaults: [Self] = [
        .init(frequency: 180), .init(frequency: 1_000), .init(frequency: 6_000)
    ]
}
