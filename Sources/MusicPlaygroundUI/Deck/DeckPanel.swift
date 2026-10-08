import SwiftUI

public struct DeckPanel<Header: View, Controls: View, Wave: View>: View {
    private let header: @MainActor () -> Header
    private let controls: @MainActor () -> Controls
    private let wave: @MainActor () -> Wave

    public init(@ViewBuilder header: @escaping @MainActor () -> Header, @ViewBuilder controls: @escaping @MainActor () -> Controls,
                @ViewBuilder wave: @escaping @MainActor () -> Wave) {
        self.header = header; self.controls = controls; self.wave = wave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header().frame(height: 32)
            controls().frame(height: 92)
            wave().frame(height: 36)
        }
        .padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
