import SwiftUI

public struct DeckTransportRow<ColorButton: View, Load: View, Play: View, Cue: View, Tempo: View, Tap: View, Sync: View, Headphones: View, FX: View, Controls: View>: View {
    private let colorButton: @MainActor () -> ColorButton
    private let load: @MainActor () -> Load
    private let play: @MainActor () -> Play
    private let cue: @MainActor () -> Cue
    private let tempo: @MainActor () -> Tempo
    private let tap: @MainActor () -> Tap
    private let sync: @MainActor () -> Sync
    private let headphones: @MainActor () -> Headphones
    private let fx: @MainActor () -> FX
    private let controls: @MainActor () -> Controls
    public init(@ViewBuilder _ colorButton: @escaping @MainActor () -> ColorButton, @ViewBuilder load: @escaping @MainActor () -> Load, @ViewBuilder play: @escaping @MainActor () -> Play, @ViewBuilder cue: @escaping @MainActor () -> Cue, @ViewBuilder tempo: @escaping @MainActor () -> Tempo, @ViewBuilder tap: @escaping @MainActor () -> Tap, @ViewBuilder sync: @escaping @MainActor () -> Sync, @ViewBuilder headphones: @escaping @MainActor () -> Headphones, @ViewBuilder fx: @escaping @MainActor () -> FX, @ViewBuilder controls: @escaping @MainActor () -> Controls) {
        self.colorButton = colorButton
        self.load = load
        self.play = play
        self.cue = cue
        self.tempo = tempo
        self.tap = tap
        self.sync = sync
        self.headphones = headphones
        self.fx = fx
        self.controls = controls
    }
    public var body: some View {
        HStack(spacing: 4) {
            colorButton().contentShape(Rectangle())
            load().contentShape(Rectangle())
            play().contentShape(Rectangle())
            cue().contentShape(Rectangle())
            tempo().contentShape(Rectangle())
            tap().contentShape(Rectangle())
            sync().contentShape(Rectangle())
            headphones().contentShape(Rectangle())
            fx().contentShape(Rectangle())
            controls().contentShape(Rectangle())
        }.font(.system(size: 8, weight: .medium)).buttonStyle(.borderless).frame(height: 32)
    }
}
