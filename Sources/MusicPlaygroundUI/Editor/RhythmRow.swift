public protocol RhythmRow {
    var sourceID: Int { get }
    var trackID: Int? { get }
    var peaks: [Float] { get }
    var label: String { get }
}
