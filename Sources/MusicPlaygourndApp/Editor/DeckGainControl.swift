import SwiftUI

struct DeckGainControl: View {
    @Binding var value: Double
    let color: Color
    let name: String
    var label = "GAIN"
    var resetValue = 1.0
    var valueLabel: String? = nil
    @State private var dragOrigin: Double?

    var body: some View {
        VStack(spacing: 5) {
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
            ZStack {
                Circle().trim(from: 0.125, to: 0.875).stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(90))
                Circle().trim(from: 0.125, to: 0.125 + value * 0.75).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(90))
                Rectangle().fill(.white).frame(width: 1.5, height: 7).offset(y: -10).rotationEffect(.degrees(-135 + value * 270))
            }.frame(width: 29, height: 29).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    if dragOrigin == nil { dragOrigin = value }
                    value = min(1, max(0, (dragOrigin ?? value) - gesture.translation.height / 100))
                }.onEnded { _ in dragOrigin = nil })
                .onTapGesture(count: 2) { value = resetValue }
                .background(MultiFingerGestureView(onChange: { value = min(1, max(0, value + $0 * 0.01)) }))
                .help("Drag or use two or three fingers in any direction to adjust this control. Double-click to reset.")
            Text(valueLabel ?? String(format: "%.0f%%", value * 100)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Deck \(name) \(label.lowercased())")
            .accessibilityValue(String(format: "%.0f percent", value * 100))
            .accessibilityAdjustableAction { value = min(1, max(0, value + ($0 == .increment ? 0.05 : -0.05))) }
            .accessibilityAction(named: "Reset") { value = resetValue }
    }
}
