public protocol RhythmScore {
    associatedtype Event: RhythmEvent
    associatedtype Row: RhythmRow
    var events: [Event] { get }
    var rows: [Row] { get }
    var bpm: Double { get }
    var beatCount: Double { get }
    var beatsPerBar: Int { get }
}
