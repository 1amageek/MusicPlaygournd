import Foundation

/// Immutable PCM ownership shared by metadata, playback and visualization.
public final class PCMBuffer: RandomAccessCollection, Sendable, Equatable {
    public typealias Index = Int
    public typealias Element = Float
    private enum Storage: Sendable {
        case array([Float])
        case bytes(Data, Range<Int>)
    }
    private let storage: Storage
    public let count: Int
    let firstNonFinite: Int?
    static let maximumBytes = Int(PreparedLoop.requiredSampleRate * PreparedLoop.maximumDurationSeconds) * 8

    init(_ samples: [Float]) {
        storage = .array(samples)
        count = samples.count
        firstNonFinite = samples.count <= Self.maximumBytes / 4 ? samples.firstIndex { !$0.isFinite } : nil
    }

    init(bytes: Data, range: Range<Int>? = nil) throws {
        let range = range ?? 0..<bytes.count
        guard range.lowerBound >= 0, range.upperBound <= bytes.count,
              range.count <= Self.maximumBytes, range.count.isMultiple(of: 4) else {
            throw PreparedLoopValidationError.invalidSampleCount(bytes.count / 4)
        }
        storage = .bytes(bytes, range)
        count = range.count / 4
        firstNonFinite = bytes.withUnsafeBytes { buffer in
            (0..<(range.count / 4)).first { index in
                !Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: range.lowerBound + index * 4, as: UInt32.self))).isFinite
            }
        }
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    public subscript(index: Int) -> Float {
        precondition(index >= 0 && index < count)
        switch storage {
        case .array(let samples): return samples[index]
        case .bytes(let bytes, let range):
            return bytes.withUnsafeBytes {
                Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: range.lowerBound + index * 4, as: UInt32.self)))
            }
        }
    }

    /// The Array API materializes only when the owner contains mapped bytes.
    var array: [Float] {
        switch storage {
        case .array(let samples): samples
        case .bytes: Array(self)
        }
    }

    // The immutable owner retains initialized storage throughout this borrow. Pointers never escape.
    func withLittleEndianBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        switch storage {
        case .bytes(let bytes, let range): return try bytes.withUnsafeBytes { try body(UnsafeRawBufferPointer(rebasing: $0[range])) }
        case .array(let samples):
            #if _endian(little)
            return try samples.withUnsafeBytes(body)
            #else
            return try samples.map { $0.bitPattern.littleEndian }.withUnsafeBytes(body)
            #endif
        }
    }

    public static func == (lhs: PCMBuffer, rhs: PCMBuffer) -> Bool {
        // Preserve Float equality, including NaN inequality, even for a shared owner.
        if lhs === rhs, lhs.firstNonFinite == nil { return true }
        return lhs.elementsEqual(rhs)
    }
}
