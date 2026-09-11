import Darwin
import Foundation
import Synchronization

/// Atomically replaces one file containing bounded metadata followed by raw PCM.
enum PCMFileTransport {
    static let codingKey = CodingUserInfoKey(rawValue: "MusicPlaygournd.PCMFiles")!
    private static let magic = Data("MPCM0001".utf8)

    final class Context: Sendable {
        private struct State {
            var owners: [PCMBuffer] = []
            var byteCount = 0
        }
        private let state = Mutex(State())
        var byteCount: Int { state.withLock { $0.byteCount } }
        private let mapped: Data
        private let start: Int
        init(mapped: Data = Data(), start: Int = 0) {
            self.mapped = mapped
            self.start = start
        }

        func write(_ pcm: PCMBuffer) throws -> [Int] {
            try state.withLock { state in
                guard pcm.count <= PCMBuffer.maximumBytes / 4,
                      state.byteCount <= 16 * 1024 * 1024 - pcm.count * 4 else {
                    throw EvaluationError.invalidResult("PCM exceeds its sample bound.")
                }
                let range = [state.byteCount, pcm.count * 4]
                state.byteCount += pcm.count * 4
                state.owners.append(pcm)
                return range
            }
        }

        func read(_ range: [Int]) throws -> PCMBuffer {
            guard range.count == 2, range[0] >= 0, range[1] > 0,
                  range[0].isMultiple(of: 4), range[1].isMultiple(of: 4),
                  range[1] <= PCMBuffer.maximumBytes,
                  range[0] <= mapped.count - start,
                  range[1] <= mapped.count - start - range[0] else {
                throw EvaluationError.invalidResult("Invalid PCM byte range.")
            }
            let lower = start + range[0]
            return try PCMBuffer(bytes: mapped, range: lower..<(lower + range[1]))
        }

        func writePayload(to descriptor: Int32) throws {
            let owners = state.withLock { $0.owners }
            for pcm in owners { try pcm.withLittleEndianBytes { try PCMFileTransport.writeBytes($0, to: descriptor) } }
        }
    }

    // File descriptors belong to this synchronous operation. Borrowed bytes are initialized;
    // short writes advance only inside the validated range, and no pointer is retained.
    private static func writeBytes(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            offset += written
        }
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL, maximumBytes: Int) throws {
        let context = Context()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        encoder.userInfo[codingKey] = context
        let metadata = try encoder.encode(value)
        guard metadata.count <= maximumBytes - 16,
              context.byteCount <= maximumBytes - 16 - metadata.count else {
            throw EvaluationError.invalidResult("Worker result exceeds its size bound.")
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: UUID().uuidString + ".tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var closed = false
        do {
            var length = UInt64(metadata.count).littleEndian
            try magic.withUnsafeBytes { try writeBytes($0, to: descriptor) }
            try withUnsafeBytes(of: &length) { try writeBytes($0, to: descriptor) }
            try metadata.withUnsafeBytes { try writeBytes($0, to: descriptor) }
            try context.writePayload(to: descriptor)
            let result = close(descriptor)
            closed = true
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            let failure = error
            if !closed { close(descriptor) }
            try FileManager.default.removeItem(at: temporary)
            throw failure
        }
    }

    static func read<Value: Decodable>(_ type: Value.Type, from data: Data, at url: URL) throws -> Value {
        guard data.count <= 16 * 1024 * 1024 else { throw EvaluationError.invalidResult("Worker result exceeds its size bound.") }
        let decoder = PropertyListDecoder()
        guard data.starts(with: magic) else { return try decoder.decode(type, from: data) }
        guard data.count >= 16 else { throw EvaluationError.invalidResult("Truncated PCM header.") }
        let length = data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self)) }
        guard length <= UInt64(data.count - 16) else { throw EvaluationError.invalidResult("Invalid PCM metadata length.") }
        let start = 16 + Int(length)
        decoder.userInfo[codingKey] = Context(mapped: data, start: start)
        // Only bounded metadata is copied; PCM retains a range into the original mapping.
        return try decoder.decode(type, from: data.subdata(in: 16..<start))
    }
}
