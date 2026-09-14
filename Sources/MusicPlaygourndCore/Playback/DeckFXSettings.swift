import Foundation

public struct DeckFXSettings: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable {
        case phaser = "Phaser", chorus = "Chorus", flanger = "Flanger"
    }
    public var kind: Kind
    public var rate: Double
    public var depth: Double
    public var feedback: Double
    public var mix: Double

    public init(kind: Kind = .phaser, rate: Double = 0.5,
                depth: Double = 0.7, feedback: Double = 0.3, mix: Double = 0) {
        self.kind = kind; self.rate = rate
        self.depth = depth; self.feedback = feedback; self.mix = mix
    }
    public static let defaults = Self()

    func validate() throws {
        guard rate.isFinite, (0.05...16).contains(rate), depth.isFinite, (0...1).contains(depth),
              feedback.isFinite, (0...0.85).contains(feedback), mix.isFinite, (0...1).contains(mix) else {
            throw PlaybackError.invalidDeckFXSettings
        }
    }
}
