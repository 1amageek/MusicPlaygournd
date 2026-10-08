#if os(macOS)
import MusicPlaygourndCore
#endif
import MusicPlaygroundUI

// Presentation consumes the renderer's final pitch capability, never source-note guesses.
extension LoopEvent: RhythmEvent {
    public var displayedMIDINote: Int? {
        if case .note(let value) = midiProjection { return value }
        return nil
    }

    var pitchDescription: String {
        switch midiProjection {
        case .none: "unpitched"
        case .note(let value): "MIDI \(value)"
        case .unsupported(.fractionalPitch): "fractional pitch"
        case .unsupported(.timeVaryingPitch): "time-varying pitch"
        case .unsupported(.legacyMetadataMissing): "pitch metadata unavailable"
        case .unsupported(.outOfRange): "pitch outside MIDI range"
        }
    }

    public var eventDescription: String {
        "onset \(startBeat), duration \(durationBeats), \(pitchDescription)"
    }
}
