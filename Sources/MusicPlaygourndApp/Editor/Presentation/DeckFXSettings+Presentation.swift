#if os(macOS)
import MusicPlaygourndCore
#endif
import MusicPlaygroundUI

extension DeckFXSettings: EffectSettings {
    public var showsFeedback: Bool { kind != .chorus }
}

