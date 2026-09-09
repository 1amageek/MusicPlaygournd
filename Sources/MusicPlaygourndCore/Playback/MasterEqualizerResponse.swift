import Foundation

/// One native EQ band's normalized biquad coefficients.
public struct MasterEqualizerResponse: Sendable, Equatable {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    public func decibels(at frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / PreparedLoop.requiredSampleRate
        let realB = b0 + b1 * cos(omega) + b2 * cos(2 * omega)
        let imagB = -b1 * sin(omega) - b2 * sin(2 * omega)
        let realA = 1 + a1 * cos(omega) + a2 * cos(2 * omega)
        let imagA = -a1 * sin(omega) - a2 * sin(2 * omega)
        return 10 * log10((realB * realB + imagB * imagB) / (realA * realA + imagA * imagA))
    }
}
