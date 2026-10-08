import Foundation

public protocol RhythmEvent {
    var sourceID: Int { get }
    var label: String { get }
    var startBeat: Double { get }
    var gain: Double { get }
    var displayedMIDINote: Int? { get }
    var eventDescription: String { get }
    func isActive(at beat: Double, in loopBeats: Double) -> Bool
    func forEachBeatRange(in loopBeats: Double, _ body: (Range<Double>) -> Void)
}
