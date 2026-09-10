import Foundation

/// Time-aligned min/max pairs, taken directly before and after compression.
public struct MasterCompressorSnapshot: Sendable, Equatable {
    public let inputEnvelope: [Float]
    public let outputEnvelope: [Float]
    public let gainReduction: Double

    public static let empty = Self(inputEnvelope: [], outputEnvelope: [], gainReduction: 0)
}
