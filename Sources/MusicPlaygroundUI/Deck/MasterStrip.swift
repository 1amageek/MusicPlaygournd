import SwiftUI

public struct MasterStrip<Scope: View, Headphones: View, Record: View>: View {
    let colorA: Color
    let colorB: Color
    @Binding var crossfade: Double
    @Binding var volume: Double
    private let scope: @MainActor () -> Scope
    private let headphones: @MainActor () -> Headphones
    private let record: @MainActor () -> Record
    private let volumeGesture: AnyView?

    public init(colorA: Color, colorB: Color, crossfade: Binding<Double>, volume: Binding<Double>, volumeGesture: AnyView? = nil,
                @ViewBuilder scope: @escaping @MainActor () -> Scope,
                @ViewBuilder headphones: @escaping @MainActor () -> Headphones,
                @ViewBuilder record: @escaping @MainActor () -> Record) {
        self.colorA = colorA; self.colorB = colorB; self._crossfade = crossfade; self._volume = volume
        self.scope = scope; self.headphones = headphones; self.record = record; self.volumeGesture = volumeGesture
    }
    public var body: some View {
        VStack(spacing: 7) {
            scope().frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                Text("A").foregroundStyle(colorA)
                GeometryReader { geometry in
                    let travel = max(1, geometry.size.width - 12)
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [colorA, colorB], startPoint: .leading, endPoint: .trailing)).frame(height: 5)
                        Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 14).offset(x: geometry.size.width / 2)
                        RoundedRectangle(cornerRadius: 3).fill(.white.gradient).frame(width: 12, height: 24)
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1).offset(x: crossfade * travel)
                    }.frame(height: 28).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { crossfade = min(1, max(0, ($0.location.x - 6) / travel)) })
                        .onTapGesture(count: 2) { crossfade = 0.5 }
                }.frame(height: 28)
                    .accessibilityElement().accessibilityLabel("A B crossfader")
                    .accessibilityValue(String(format: "%.0f percent B", crossfade * 100))
                    .accessibilityAdjustableAction { direction in
                        crossfade = min(1, max(0, crossfade + (direction == .increment ? 0.05 : -0.05)))
                    }.accessibilityAction(named: "Center") { crossfade = 0.5 }
                    .accessibilityIdentifier("crossfader")
                Text("B").foregroundStyle(colorB)
            }.font(.system(size: 15, weight: .bold))
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1).controlSize(.mini).tint(.gray)
                    .background(volumeGesture).frame(maxWidth: .infinity).accessibilityLabel("Master volume")
                headphones().contentShape(Rectangle())
                record().contentShape(Rectangle())
            }
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }
}
