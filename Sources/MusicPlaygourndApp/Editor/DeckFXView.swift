import SwiftUI
import MusicPlaygourndCore

struct DeckFXView: View {
    let settings: DeckFXSettings
    let beats: Double?
    let onChange: (DeckFXSettings) -> Void
    let onBeatsChange: (Double?) -> Void
    let onReset: () -> Void
    @State private var details = false
    let tint: Color
    let name: String

    private func binding<Value>(_ key: WritableKeyPath<DeckFXSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: key] }, set: {
            var value = settings; value[keyPath: key] = $0; onChange(value)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Deck \(name) · FX").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Enabled", isOn: binding(\.enabled)).labelsHidden()
                    .toggleStyle(.switch).controlSize(.mini).accessibilityLabel("Enable Deck \(name) FX")
                Button("Reset", action: onReset).buttonStyle(.plain)
                    .accessibilityLabel("Reset Deck \(name) FX")
            }
            Picker("Effect", selection: binding(\.kind)) {
                ForEach(DeckFXSettings.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Deck \(name) effect")
            HStack(spacing: 5) {
                ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { beat in
                    Button(beat == 0.25 ? "¼" : beat == 0.5 ? "½" : String(Int(beat))) { onBeatsChange(beat) }
                        .buttonStyle(.plain).frame(maxWidth: .infinity).frame(height: 27)
                        .background(beats == beat ? tint.opacity(0.3) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Deck \(name) FX \(beat) beats")
                        .accessibilityAddTraits(beats == beat ? .isSelected : [])
                }
                Text("BEATS").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
            modulationPad
            DisclosureGroup("Details", isExpanded: $details) {
                VStack(spacing: 12) {
                    Toggle("Sync to BPM", isOn: Binding(get: { beats != nil }, set: { onBeatsChange($0 ? 1 : nil) }))
                        .toggleStyle(.switch).controlSize(.mini)
                    parameter("Rate", key: \.rate, range: 0.05...16, value: String(format: "%.2f Hz", settings.rate))
                        .disabled(beats != nil)
                    if settings.kind != .chorus {
                        parameter("Feedback", key: \.feedback, range: 0...0.85, value: percent(settings.feedback))
                    }
                }.padding(.top, 10)
            }
        }.font(.system(size: 11)).padding(18).frame(width: 330).tint(tint)
    }

    private var modulationPad: some View {
        VStack(spacing: 7) {
            HStack {
                Text("MIX →  \(percent(settings.mix))")
                Spacer()
                Text("DEPTH ↑  \(percent(settings.depth))")
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(tint)
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 16)
                let height = max(1, geometry.size.height - 16)
                let x = 8 + settings.mix * width
                let y = 8 + (1 - settings.depth) * height
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.3))
                    Path { path in
                        for index in 1..<4 {
                            let fraction = CGFloat(index) / 4
                            path.move(to: CGPoint(x: 8 + width * fraction, y: 8))
                            path.addLine(to: CGPoint(x: 8 + width * fraction, y: height + 8))
                            path.move(to: CGPoint(x: 8, y: 8 + height * fraction))
                            path.addLine(to: CGPoint(x: width + 8, y: 8 + height * fraction))
                        }
                    }.stroke(.white.opacity(0.08), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 8)); path.addLine(to: CGPoint(x: x, y: height + 8))
                        path.move(to: CGPoint(x: 8, y: y)); path.addLine(to: CGPoint(x: width + 8, y: y))
                    }.stroke(tint.opacity(0.35), lineWidth: 1)
                    Circle().fill(tint).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: tint.opacity(0.6), radius: 6)
                        .position(x: x, y: y)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    movePad(to: event.location, in: geometry.size)
                })
                .accessibilityRepresentation {
                    VStack {
                        Slider(value: binding(\.mix), in: 0...1).accessibilityLabel("Deck \(name) FX Mix")
                        Slider(value: binding(\.depth), in: 0...1).accessibilityLabel("Deck \(name) FX Depth")
                    }
                }
                .accessibilityIdentifier("deck-\(name)-fx-pad")
                .help("Drag horizontally for dry/wet mix, vertically for depth. Release to keep the current settings.")
            }.frame(height: 150)
        }
    }

    func movePad(to point: CGPoint, in size: CGSize) {
        guard point.x.isFinite, point.y.isFinite, size.width > 16, size.height > 16 else { return }
        var value = settings
        value.mix = min(1, max(0, (point.x - 8) / (size.width - 16)))
        value.depth = min(1, max(0, 1 - (point.y - 8) / (size.height - 16)))
        onChange(value)
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private func parameter(_ label: String, key: WritableKeyPath<DeckFXSettings, Double>,
                           range: ClosedRange<Double>, value: String) -> some View {
        VStack(spacing: 4) {
            HStack { Text(label); Spacer(); Text(value).monospacedDigit().foregroundStyle(tint) }
            Slider(value: binding(key), in: range).controlSize(.small)
                .accessibilityLabel("Deck \(name) FX \(label)")
        }
    }
}
