import Foundation
import Testing
@testable import MusicPlaygourndCore

struct PreparedLoopTests {
    @Test(.timeLimit(.minutes(1)))
    func packedPCMIsExactAndRejectsMalformedBytes() throws {
        let samples: [Float] = [0, -0.0, 1, -1, 0.125, Float.leastNonzeroMagnitude]
        let loop = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                                beatCount: 4, samples: samples, events: [])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded = try encoder.encode(loop)
        let decoded = try PropertyListDecoder().decode(PreparedLoop.self, from: encoded)
        #expect(decoded.samples.map(\.bitPattern) == samples.map(\.bitPattern))
        var payload = try #require(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
        let bytes = try #require(payload["pcmFloat32LE"] as? Data)
        #expect(bytes.count == samples.count * 4)
        #expect(Array(bytes[8..<12]) == [0, 0, 128, 63])
        payload["pcmFloat32LE"] = Data([1, 2, 3])
        let malformed = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        #expect(throws: DecodingError.self) { try PropertyListDecoder().decode(PreparedLoop.self, from: malformed) }
        payload.removeValue(forKey: "pcmFloat32LE")
        payload["samples"] = samples
        let legacy = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        #expect(try PropertyListDecoder().decode(PreparedLoop.self, from: legacy).samples == samples)
    }

    @Test(.timeLimit(.minutes(3)))
    func testDecodedLoopValidationRejectsNonFiniteAndMismatchedSamples() throws {
        let invalidSamples = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: [Float.nan, 0],
            events: []
        )
        #expect {
            try invalidSamples.validate()
        } throws: { error in
            error as? PreparedLoopValidationError == .invalidSampleCount(2)
        }

        let invalidEvent = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: Array(repeating: 0, count: 176_400),
            events: [LoopEvent(
                sourceID: 0,
                label: "lead",
                startBeat: 0,
                durationBeats: 1,
                midiNote: 128,
                velocity: 80
            )]
        )
        #expect {
            try invalidEvent.validate()
        } throws: { error in
            if case .invalidEvent(index: 0, reason: "MIDI note is out of range") = error as? PreparedLoopValidationError { return true }
            return false
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func testDecodedLoopValidationRejectsDuplicateRowsAndInvalidPeaks() throws {
        let duplicateRows = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: Array(repeating: 0, count: 176_400),
            events: [],
            rows: [
                LoopRow(sourceID: 0, label: "first", anchor: nil, peaks: [0]),
                LoopRow(sourceID: 0, label: "second", anchor: nil, peaks: [0])
            ]
        )
        #expect {
            try duplicateRows.validate()
        } throws: { error in
            if case .invalidRow(index: 1, reason: "duplicate source ID") = error as? PreparedLoopValidationError { return true }
            return false
        }

        let invalidPeaks = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: Array(repeating: 0, count: 176_400),
            events: [],
            rows: [
                LoopRow(sourceID: 0, label: "lead", anchor: nil, peaks: [Float.nan])
            ]
        )
        #expect {
            try invalidPeaks.validate()
        } throws: { error in
            if case .invalidRow(index: 0, reason: "peak envelope contains an invalid value") = error as? PreparedLoopValidationError { return true }
            return false
        }

        let negativePatternIndex = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: Array(repeating: 0, count: 176_400),
            events: [LoopEvent(
                sourceID: 0,
                label: "lead",
                startBeat: 0,
                durationBeats: 1,
                midiNote: 60,
                velocity: 80,
                patternStepIndex: -1
            )],
            rows: [LoopRow(sourceID: 0, label: "lead", anchor: nil, peaks: [0], patternText: "x ~")]
        )
        #expect {
            try negativePatternIndex.validate()
        } throws: { error in
            if case .invalidEvent(index: 0, reason: "negative pattern step index") = error as? PreparedLoopValidationError { return true }
            return false
        }

        let outOfRangePatternIndex = PreparedLoop(
            sampleRate: 44_100,
            bpm: 120,
            beatsPerBar: 4,
            beatCount: 4,
            samples: Array(repeating: 0, count: 176_400),
            events: [LoopEvent(
                sourceID: 0,
                label: "lead",
                startBeat: 0,
                durationBeats: 1,
                midiNote: 60,
                velocity: 80,
                patternStepIndex: 2
            )],
            rows: [LoopRow(sourceID: 0, label: "lead", anchor: nil, peaks: [0], patternText: "x ~")]
        )
        #expect {
            try outOfRangePatternIndex.validate()
        } throws: { error in
            if case .invalidEvent(index: 0, reason: "pattern step index is outside pattern text") = error as? PreparedLoopValidationError { return true }
            return false
        }
    }
}

extension PreparedLoopTests {
    @Test(.timeLimit(.minutes(1)))
    func mappedPCMRetainsOwnershipAndRejectsInvalidRanges() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PCM-" + UUID().uuidString)
        let file = directory.appending(path: "result.plist")
        var samples = [Float](repeating: 0.125, count: 176_400)
        samples[1] = -0.0
        samples[2] = Float.leastNonzeroMagnitude
        let original = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
            beatCount: 4, samples: samples, events: [])
        try PCMFileTransport.write(original, to: file, maximumBytes: 16 * 1024 * 1024)
        let mapped = try Data(contentsOf: file, options: .alwaysMapped)
        #expect(mapped.count < samples.count * 4 + 1024)
        let decoded = try PCMFileTransport.read(PreparedLoop.self, from: mapped, at: file)
        try decoded.validate()
        samples[23] = .infinity
        let invalid = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
            beatCount: 4, samples: samples, events: [])
        try PCMFileTransport.write(invalid, to: file, maximumBytes: 16 * 1024 * 1024)
        let nonfinite = try PCMFileTransport.read(PreparedLoop.self,
            from: Data(contentsOf: file, options: .alwaysMapped), at: file)
        #expect(throws: PreparedLoopValidationError.nonFiniteSample(index: 23)) { try nonfinite.validate() }
        #expect(throws: Error.self) { try PCMFileTransport.write(original, to: file, maximumBytes: 10) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["result.plist"])
        try FileManager.default.removeItem(at: directory)
        samples[23] = 0.125
        #expect(decoded.samples.map(\.bitPattern) == samples.map(\.bitPattern))
        let located = PreparedLoop(sampleRate: decoded.sampleRate, bpm: decoded.bpm,
            beatsPerBar: decoded.beatsPerBar, beatCount: decoded.beatCount, pcm: decoded.pcm, events: [])
        #expect(located.pcm === decoded.pcm)
        for _ in 0..<100 { try located.validate() }

        let context = PCMFileTransport.Context(mapped: Data(repeating: 0, count: 32), start: 16)
        for range in [[-1, 4], [0, -1], [1, 4], [0, 3], [0, 20], [Int.max, 4], [0, Int.max], []] {
            #expect(throws: Error.self) { try context.read(range) }
        }
        #expect(try context.read([0, 16]).count == 4)
        #expect(throws: Error.self) {
            try PCMFileTransport.read(PreparedLoop.self, from: Data(mapped.prefix(12)), at: file)
        }
        var corrupt = Data(mapped)
        corrupt.replaceSubrange(8..<16, with: repeatElement(UInt8(255), count: 8))
        #expect(throws: Error.self) { try PCMFileTransport.read(PreparedLoop.self, from: corrupt, at: file) }
    }
}

extension NativeHostTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func mappedPCMPlaysAfterFileReplacementAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PCM-Native-" + UUID().uuidString)
        let file = directory.appending(path: "result.plist")
        let samples = (0..<176_400).map { Float(sin(Double($0 / 2) * 0.03) * ($0.isMultiple(of: 2) ? 0.25 : 0.1)) }
        let original = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
            beatCount: 4, samples: samples, events: [])
        try PCMFileTransport.write(original, to: file, maximumBytes: 16 * 1024 * 1024)
        let mapped = try PCMFileTransport.read(PreparedLoop.self,
            from: Data(contentsOf: file, options: .alwaysMapped), at: file)
        try FileManager.default.removeItem(at: directory)
        var outputs = [[Float]]()
        for loop in [original, mapped] {
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop, revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.play()
            outputs.append(try engine.renderOfflineForTests(frameCount: 4096))
        }
        #expect(outputs[0] == outputs[1])
        #expect(outputs[1].contains { abs($0) > 0.1 })
    }
}
