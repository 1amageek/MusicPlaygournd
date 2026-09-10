import Foundation

/// Live master dynamics, independent of the source score.
public struct MasterCompressorSettings: Sendable, Equatable {
    public var enabled: Bool
    public var threshold: Double
    public var ratio: Double
    public var attackMilliseconds: Double
    public var releaseMilliseconds: Double

    public init(enabled: Bool = false, threshold: Double = -18, ratio: Double = 4,
                attackMilliseconds: Double = 10, releaseMilliseconds: Double = 100) {
        self.enabled = enabled
        self.threshold = threshold
        self.ratio = ratio
        self.attackMilliseconds = attackMilliseconds
        self.releaseMilliseconds = releaseMilliseconds
    }

    public static let defaults = Self()

    func validate() throws {
        guard threshold.isFinite, (-60...0).contains(threshold),
              ratio.isFinite, (1...20).contains(ratio),
              attackMilliseconds.isFinite, (0.1...200).contains(attackMilliseconds),
              releaseMilliseconds.isFinite, (10...2000).contains(releaseMilliseconds) else {
            throw PlaybackError.invalidCompressorSettings
        }
    }
}
