import Foundation

public struct PreparedLoop: Codable, Sendable, Equatable {
    public static let requiredSampleRate = 44_100.0
    public static let maximumDurationSeconds = 16.0
    public static let maximumBeatCount = 32.0
    public static let maximumEvents = 1_024
    public static let maximumRows = 32
    public static let maximumPeakBins = 512

    public let sampleRate: Double
    public let bpm: Double
    public let beatsPerBar: Int
    public let beatCount: Double
    public let samples: [Float]
    public let events: [LoopEvent]
    public let meters: [PreparedMeterEnvelope]?
    public let rows: [LoopRow]

    public init(
        sampleRate: Double,
        bpm: Double,
        beatsPerBar: Int,
        beatCount: Double,
        samples: [Float],
        events: [LoopEvent],
        rows: [LoopRow] = [],
        meters: [PreparedMeterEnvelope]? = nil
    ) {
        self.sampleRate = sampleRate
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.beatCount = beatCount
        self.samples = samples
        self.events = events
        self.rows = rows
        self.meters = meters
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRate, bpm, beatsPerBar, beatCount, samples, pcmFloat32LE, events, meters, rows
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sampleRate = try values.decode(Double.self, forKey: .sampleRate)
        bpm = try values.decode(Double.self, forKey: .bpm)
        beatsPerBar = try values.decode(Int.self, forKey: .beatsPerBar)
        beatCount = try values.decode(Double.self, forKey: .beatCount)
        events = try values.decode([LoopEvent].self, forKey: .events)
        rows = try values.decode([LoopRow].self, forKey: .rows)
        meters = try values.decodeIfPresent([PreparedMeterEnvelope].self, forKey: .meters)
        if values.contains(.pcmFloat32LE) {
            let data = try values.decode(Data.self, forKey: .pcmFloat32LE)
            let maximumBytes = Int(Self.requiredSampleRate * Self.maximumDurationSeconds) * 2 * 4
            guard data.count.isMultiple(of: 4), data.count <= maximumBytes else {
                throw DecodingError.dataCorruptedError(forKey: .pcmFloat32LE, in: values,
                    debugDescription: "PCM must contain bounded, complete Float32 samples.")
            }
            // The Data owns this scoped borrow; each unaligned read is within its checked byte count.
            samples = data.withUnsafeBytes { bytes in
                (0..<(bytes.count / 4)).map { index in
                    Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
                }
            }
        } else {
            samples = try values.decode([Float].self, forKey: .samples)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sampleRate, forKey: .sampleRate)
        try values.encode(bpm, forKey: .bpm)
        try values.encode(beatsPerBar, forKey: .beatsPerBar)
        try values.encode(beatCount, forKey: .beatCount)
        try values.encode(events, forKey: .events)
        try values.encode(rows, forKey: .rows)
        try values.encodeIfPresent(meters, forKey: .meters)
        // Serialization needs owned bytes beyond this Array borrow; Data performs that boundary copy.
        #if _endian(little)
        let data = samples.withUnsafeBytes { Data($0) }
        #else
        let data = samples.map { $0.bitPattern.littleEndian }.withUnsafeBytes { Data($0) }
        #endif
        try values.encode(data, forKey: .pcmFloat32LE)
    }

    public func validate() throws {
        guard sampleRate == Self.requiredSampleRate else {
            throw PreparedLoopValidationError.invalidSampleRate(sampleRate)
        }
        guard bpm.isFinite, (40...240).contains(bpm) else {
            throw PreparedLoopValidationError.invalidBPM(bpm)
        }
        guard (2...7).contains(beatsPerBar) else {
            throw PreparedLoopValidationError.invalidMeter(beatsPerBar)
        }
        guard beatCount.isFinite,
              beatCount > 0,
              beatCount <= Self.maximumBeatCount else {
            throw PreparedLoopValidationError.invalidBeatCount(beatCount)
        }

        let barCount = (beatCount / Double(beatsPerBar)).rounded()
        guard barCount >= 1,
              abs(barCount * Double(beatsPerBar) - beatCount) <= 1e-9 else {
            throw PreparedLoopValidationError.invalidBeatCount(beatCount)
        }

        let duration = beatCount * 60 / bpm
        guard duration.isFinite, duration <= Self.maximumDurationSeconds else {
            throw PreparedLoopValidationError.invalidBeatCount(beatCount)
        }
        let expectedFrames = Int((duration * sampleRate).rounded(.up))
        guard expectedFrames >= 1, samples.count == expectedFrames * 2 else {
            throw PreparedLoopValidationError.invalidSampleCount(samples.count)
        }

        let maximumSamples = Int(Self.requiredSampleRate * Self.maximumDurationSeconds) * 2
        guard samples.count <= maximumSamples else {
            throw PreparedLoopValidationError.tooManySamples(limit: maximumSamples)
        }
        for (index, sample) in samples.enumerated() {
            guard sample.isFinite else {
                throw PreparedLoopValidationError.nonFiniteSample(index: index)
            }
        }

        guard rows.count <= Self.maximumRows else {
            throw PreparedLoopValidationError.tooManyRows(limit: Self.maximumRows)
        }
        var rowIDs = Set<Int>()
        for (index, row) in rows.enumerated() {
            guard row.sourceID >= 0 else {
                throw PreparedLoopValidationError.invalidRow(index: index, reason: "negative source ID")
            }
            guard rowIDs.insert(row.sourceID).inserted else {
                throw PreparedLoopValidationError.invalidRow(index: index, reason: "duplicate source ID")
            }
            guard !row.label.isEmpty else {
                throw PreparedLoopValidationError.invalidRow(index: index, reason: "empty label")
            }
            if let anchor = row.anchor {
                guard !anchor.fileID.isEmpty, anchor.line > 0, anchor.column > 0 else {
                    throw PreparedLoopValidationError.invalidRow(index: index, reason: "invalid source anchor")
                }
            }
            if let resultLine = row.resultLine, resultLine <= 0 {
                throw PreparedLoopValidationError.invalidRow(index: index, reason: "invalid expression end line")
            }
            guard row.peaks.count <= Self.maximumPeakBins else {
                throw PreparedLoopValidationError.invalidRow(index: index, reason: "peak envelope exceeds 512 bins")
            }
            for peak in row.peaks {
                guard peak.isFinite, peak >= 0 else {
                    throw PreparedLoopValidationError.invalidRow(index: index, reason: "peak envelope contains an invalid value")
                }
            }
        }

        if let meters {
            guard meters.count <= 64 else {
                throw PreparedLoopValidationError.invalidTelemetry("Meter count exceeds Track/Bus limits")
            }
            var targets = Set<PreparedMeterEnvelope.Target>()
            for meter in meters {
                try meter.validate()
                guard targets.insert(meter.target).inserted else {
                    throw PreparedLoopValidationError.invalidTelemetry("Duplicate meter identity")
                }
            }
        }

        guard events.count <= Self.maximumEvents else {
            throw PreparedLoopValidationError.tooManyEvents(limit: Self.maximumEvents)
        }
        var previousStart = 0.0
        for (index, event) in events.enumerated() {
            if let pan = event.pan, !pan.isFinite || !(-1...1).contains(pan) {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "pan is invalid")
            }
            guard event.sourceID >= 0 else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "negative source ID")
            }
            guard !event.label.isEmpty else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "empty label")
            }
            guard event.startBeat.isFinite,
                  event.durationBeats.isFinite,
                  event.startBeat >= 0,
                  event.startBeat < beatCount,
                  event.durationBeats > 0 else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "invalid timing")
            }
            let end = event.startBeat + event.durationBeats
            if event.wrapsLoopBoundary {
                guard event.durationBeats <= beatCount, end > beatCount else {
                    throw PreparedLoopValidationError.invalidEvent(index: index, reason: "invalid loop boundary continuation")
                }
            } else if end > beatCount + 1e-9 {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "invalid timing")
            }
            guard event.startBeat + 1e-9 >= previousStart else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "events are not sorted")
            }
            previousStart = event.startBeat
            if let midiNote = event.midiNote, !(0...127).contains(midiNote) {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "MIDI note is out of range")
            }
            if case .note(let note) = event.midiProjection, !(0...127).contains(note) {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "MIDI projection is out of range")
            }
            guard (1...127).contains(event.velocity) else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "velocity is out of range")
            }
            guard event.gain.isFinite, event.gain >= 0 else {
                throw PreparedLoopValidationError.invalidEvent(index: index, reason: "gain must be finite and nonnegative")
            }
            if let patternStepIndex = event.patternStepIndex {
                guard patternStepIndex >= 0 else {
                    throw PreparedLoopValidationError.invalidEvent(index: index, reason: "negative pattern step index")
                }
                guard patternStepIndex < Self.maximumPatternTokenCount else {
                    throw PreparedLoopValidationError.invalidEvent(index: index, reason: "pattern step index exceeds 1023")
                }
                if let row = rows.first(where: { $0.sourceID == event.sourceID }),
                   let patternText = row.patternText {
                    let tokenCount = patternText.split(whereSeparator: Self.isPatternDelimiter).count
                    guard patternStepIndex < tokenCount else {
                        throw PreparedLoopValidationError.invalidEvent(index: index, reason: "pattern step index is outside pattern text")
                    }
                }
            }
        }
    }

    private static let maximumPatternTokenCount = 1_024

    private static func isPatternDelimiter(_ character: Character) -> Bool {
        if character == "[" || character == "]" || character == "<" || character == ">" { return true }
        return switch character.asciiValue {
        case 9, 10, 11, 12, 13, 32: true
        default: false
        }
    }
}
