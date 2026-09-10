import Foundation

/// A bounded monotonic tap estimator, independent for each deck.
struct TapTempo {
    private var previous: TimeInterval?
    private var intervals: [TimeInterval] = []

    mutating func tap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        guard time.isFinite else { return nil }
        defer { previous = time }
        guard let previous, time > previous, time - previous <= 2 else {
            intervals.removeAll(keepingCapacity: true)
            return nil
        }
        let interval = time - previous
        guard (0.25...1.5).contains(interval) else {
            intervals.removeAll(keepingCapacity: true)
            return nil
        }
        intervals.append(interval)
        if intervals.count > 4 { intervals.removeFirst() }
        return 60 / (intervals.reduce(0, +) / Double(intervals.count))
    }
}
