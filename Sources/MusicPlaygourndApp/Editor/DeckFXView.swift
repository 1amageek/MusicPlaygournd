import SwiftUI
import MusicPlaygourndCore

struct DeckFXView: View {
    let settings: DeckFXSettings
    let onChange: (DeckFXSettings) -> Void
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
                Button("Reset") { onChange(.defaults) }.buttonStyle(.plain)
                    .accessibilityLabel("Reset Deck \(name) FX")
            }
            Picker("Effect", selection: binding(\.kind)) {
                ForEach(DeckFXSettings.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Deck \(name) effect")
            Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(height: 30, alignment: .topLeading)
            parameter("Rate", key: \.rate, range: 0.05...8, value: String(format: "%.2f Hz", settings.rate))
            parameter("Depth", key: \.depth, range: 0...1, value: percent(settings.depth))
            if settings.kind != .chorus {
                parameter("Feedback", key: \.feedback, range: 0...0.85, value: percent(settings.feedback))
            }
            parameter("Mix", key: \.mix, range: 0...1, value: percent(settings.mix))
            HStack {
                Text("DRY"); Spacer(); Text("WET")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(18).frame(width: 330).tint(tint)
    }

    private var description: String {
        switch settings.kind {
        case .phaser: "Six-stage phase sweep. Depth opens the frequency range."
        case .chorus: "Short modulated delays add stereo movement and width."
        case .flanger: "Sweeping short delay. Feedback adds resonant notches."
        }
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
