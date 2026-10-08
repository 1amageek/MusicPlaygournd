import SwiftUI
import MusicPlaygourndCore
import MusicPlaygroundUI

extension DeckFXSettings: EffectSettings {
    public var showsFeedback: Bool { kind != .chorus }
}

typealias DeckFXView = EffectView<DeckFXSettings>
