import Foundation

/// Bounded, bandlimited reads from an immutable stereo PCM borrow.
struct ScratchResampler: Sendable {
    static let maximumSpeed = 32.0
    private let radius = 32.0
    private let table: [Double]

    init() {
        table = (0...4096).map { index in
            let x = Double(index) / 128
            let sinc = x == 0 ? 0.9 : sin(.pi * 0.9 * x) / (.pi * x)
            return sinc * (0.42 + 0.5 * cos(.pi * x / 32) + 0.08 * cos(2 * .pi * x / 32))
        }
    }

    // The caller retains validated, initialized little-endian stereo Float32 storage.
    // Position is finite and wrapped; speed is finite and bounded. No pointer escapes.
    func sample(pcm: UnsafeRawBufferPointer, position: Double, speed: Double) -> (Float, Float) {
        let frames = pcm.count / 8
        let stretch = max(1, abs(speed))
        let width = radius * stretch
        let first = Int(ceil(position - width))
        let last = Int(floor(position + width))
        var frame = first % frames
        if frame < 0 { frame += frames }
        var left = 0.0, right = 0.0, weight = 0.0
        let scale = 128 / stretch
        for source in first...last {
            let coordinate = min(4096, abs(Double(source) - position) * scale)
            let index = Int(coordinate)
            let fraction = coordinate - Double(index)
            let coefficient = table[index] + (table[min(index + 1, 4096)] - table[index]) * fraction
            let value = Self.frame(pcm: pcm, index: frame)
            left += Double(value.0) * coefficient
            right += Double(value.1) * coefficient
            weight += coefficient
            frame += 1
            if frame == frames { frame = 0 }
        }
        return (Float(left / weight), Float(right / weight))
    }

    static func frame(pcm: UnsafeRawBufferPointer, index: Int) -> (Float, Float) {
        (Float(bitPattern: UInt32(littleEndian: pcm.loadUnaligned(fromByteOffset: index * 8, as: UInt32.self))),
         Float(bitPattern: UInt32(littleEndian: pcm.loadUnaligned(fromByteOffset: index * 8 + 4, as: UInt32.self))))
    }
}
