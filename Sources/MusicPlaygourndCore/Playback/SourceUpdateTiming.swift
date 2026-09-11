import Foundation

/// Determines when prepared source edits begin replacing the playing loop.
public enum SourceUpdateTiming: String, CaseIterable, Sendable {
    case immediate
    case nextBeat
    case nextBar

    public var title: String {
        switch self {
        case .immediate: "Immediate"
        case .nextBeat: "Next Beat"
        case .nextBar: "Next Bar"
        }
    }

    func boundary(after beat: Double, beatsPerBar: Int) -> Double {
        switch self {
        case .immediate: return beat
        case .nextBeat: return floor(beat) + 1
        case .nextBar:
            let meter = Double(beatsPerBar)
            return (floor(beat / meter) + 1) * meter
        }
    }
}
