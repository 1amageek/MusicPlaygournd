import Accelerate
import Foundation

/// Performs bounded real-valued convolution through cached Accelerate DFT setups.
internal final class FFTConvolver {
    // Pad tiny convolutions to at least two frames so the native setup path has
    // a nonzero power-of-two transform, including for a one-frame convolution.
    private static let minimumTransformLength = 2
    private static let maximumTransformLength = 2_097_152
    private static let maximumScratchBytes = 48 * 1024 * 1024

    private struct SetupPair {
        let forward: vDSP_DFT_Setup
        let inverse: vDSP_DFT_Setup
    }

    private let maximumLinearFrameCount: Int
    private var setups: [Int: SetupPair] = [:]
    private var inputReal: [Float] = []
    private var inputImaginary: [Float] = []
    private var impulseReal: [Float] = []
    private var impulseImaginary: [Float] = []
    private var productReal: [Float] = []
    private var productImaginary: [Float] = []
    private var cachedImpulse: [Float] = []
    private(set) var workspaceAllocations = 0
    private(set) var impulseTransforms = 0

    init(maximumLinearFrameCount: Int) throws {
        guard maximumLinearFrameCount > 0,
              let transformLength = Self.nextPowerOfTwo(maximumLinearFrameCount),
              transformLength <= Self.maximumTransformLength,
              transformLength <= Self.maximumScratchBytes / (MemoryLayout<Float>.stride * 6) else {
            throw LoopRenderingError.invalidSound("FFT convolution frame bound is invalid")
        }
        self.maximumLinearFrameCount = maximumLinearFrameCount
    }

    deinit {
        // The cache owns each native setup pair and is the sole destruction owner.
        for pair in setups.values {
            vDSP_DFT_DestroySetup(pair.forward)
            vDSP_DFT_DestroySetup(pair.inverse)
        }
    }

    func convolve(
        _ input: [Float],
        with impulse: [Float],
        outputFrameCount: Int,
        circular: Bool
    ) throws -> [Float] {
        guard !input.isEmpty, !impulse.isEmpty else {
            throw LoopRenderingError.invalidSound("FFT convolution input must not be empty")
        }
        guard outputFrameCount > 0, outputFrameCount <= maximumLinearFrameCount else {
            throw LoopRenderingError.invalidSound("FFT convolution output frame count is out of bounds")
        }
        guard input.allSatisfy(\.isFinite), impulse.allSatisfy(\.isFinite) else {
            throw LoopRenderingError.invalidSound("FFT convolution input must be finite")
        }

        let (sum, overflow) = input.count.addingReportingOverflow(impulse.count)
        guard !overflow, sum > 0 else {
            throw LoopRenderingError.invalidSound("FFT convolution input length overflow")
        }
        let naturalLength = sum - 1
        guard naturalLength > 0, naturalLength <= maximumLinearFrameCount,
              let transformLength = Self.nextPowerOfTwo(naturalLength),
              transformLength <= Self.maximumTransformLength,
              transformLength <= Self.maximumScratchBytes / (MemoryLayout<Float>.stride * 6) else {
            throw LoopRenderingError.invalidSound("FFT convolution transform length is out of bounds")
        }

        let pair = try setup(for: transformLength)

        try Task.checkCancellation()
        if inputReal.count != transformLength {
            inputReal = [Float](repeating: 0, count: transformLength)
            inputImaginary = [Float](repeating: 0, count: transformLength)
            impulseReal = [Float](repeating: 0, count: transformLength)
            impulseImaginary = [Float](repeating: 0, count: transformLength)
            productReal = [Float](repeating: 0, count: transformLength)
            productImaginary = [Float](repeating: 0, count: transformLength)
            cachedImpulse = []
            workspaceAllocations += 1
        }
        // This render-local owner retains six scratch arrays (48 MiB maximum) and
        // one immutable impulse (at most 8 MiB). No buffer is shared across renders.
        // Accelerate borrows aligned Array storage synchronously; no pointer escapes.
        if cachedImpulse != impulse {
            cachedImpulse = []
            for index in 0..<transformLength {
                inputReal[index] = index < impulse.count ? impulse[index] : 0
                inputImaginary[index] = 0
            }
            vDSP_DFT_Execute(pair.forward, inputReal, inputImaginary, &impulseReal, &impulseImaginary)
            guard impulseReal.allSatisfy(\.isFinite), impulseImaginary.allSatisfy(\.isFinite) else {
                throw LoopRenderingError.invalidSound("FFT convolution impulse transform is non-finite")
            }
            cachedImpulse = impulse
            impulseTransforms += 1
        }
        try Task.checkCancellation()
        for index in 0..<transformLength {
            inputReal[index] = index < input.count ? input[index] : 0
            inputImaginary[index] = 0
        }
        vDSP_DFT_Execute(pair.forward, inputReal, inputImaginary, &productReal, &productImaginary)
        guard productReal.allSatisfy(\.isFinite), productImaginary.allSatisfy(\.isFinite) else {
            throw LoopRenderingError.invalidSound("FFT convolution input transform is non-finite")
        }
        try Task.checkCancellation()

        for index in 0..<transformLength {
            let real = productReal[index] * impulseReal[index]
                - productImaginary[index] * impulseImaginary[index]
            let imaginary = productReal[index] * impulseImaginary[index]
                + productImaginary[index] * impulseReal[index]
            guard real.isFinite, imaginary.isFinite else {
                throw LoopRenderingError.invalidSound("FFT convolution spectrum product is non-finite")
            }
            productReal[index] = real
            productImaginary[index] = imaginary
        }

        vDSP_DFT_Execute(
            pair.inverse,
            productReal,
            productImaginary,
            &inputReal,
            &inputImaginary
        )

        try Task.checkCancellation()
        let scale = 1 / Float(transformLength)
        var output = [Float](repeating: 0, count: outputFrameCount)
        if circular {
            for index in 0..<naturalLength {
                let value = inputReal[index] * scale
                guard value.isFinite else {
                    throw LoopRenderingError.invalidSound("FFT convolution output is non-finite")
                }
                let destination = index % outputFrameCount
                let sum = output[destination] + value
                guard sum.isFinite else {
                    throw LoopRenderingError.invalidSound("FFT convolution output is non-finite")
                }
                output[destination] = sum
            }
        } else {
            for index in 0..<min(naturalLength, outputFrameCount) {
                let value = inputReal[index] * scale
                guard value.isFinite else {
                    throw LoopRenderingError.invalidSound("FFT convolution output is non-finite")
                }
                output[index] = value
            }
        }
        return output
    }

    private func setup(for length: Int) throws -> SetupPair {
        if let cached = setups[length] {
            return cached
        }
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(length), .FORWARD) else {
            throw LoopRenderingError.invalidSound("Accelerate FFT setup is unavailable")
        }
        guard let inverse = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(length), .INVERSE) else {
            vDSP_DFT_DestroySetup(forward)
            throw LoopRenderingError.invalidSound("Accelerate inverse FFT setup is unavailable")
        }
        let pair = SetupPair(forward: forward, inverse: inverse)
        setups[length] = pair
        return pair
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        var result = minimumTransformLength
        while result < value {
            if result > maximumTransformLength / 2 { return nil }
            result *= 2
        }
        return result
    }
}
