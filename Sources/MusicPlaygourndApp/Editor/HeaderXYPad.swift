import SwiftUI

/// Controls the global filter and reverb without editing the score.
struct HeaderXYPad: View {
    @Bindable var model: SessionModel
    var bipolar = false
    var tint: Color = .mint
    var name = "Master"

    private var cutoff: Double {
        guard let descriptor = model.controlCatalog?.descriptors.first(where: { $0.address.target == .master && $0.address.parameter == .lowPassCutoff }) else { return model.lowPass }
        return model.controlValue(descriptor) ?? 20_000
    }
    private var space: Double { model.displayedReverbMix }
    private var x: Double { bipolar ? (model.djFilter + 1) / 2 : min(1, max(0, log(cutoff / 20) / log(1_000))) }
    private var y: Double { min(1, max(0, space)) }

    private func setFilter(_ value: Double) {
        if bipolar { model.setDJFilter(value * 2 - 1) }
        else { model.lowPass = 20 * Foundation.pow(1_000, value) }
    }

    private func reset() {
        setFilter(bipolar ? 0.5 : 1)
        model.reverbMix = 0
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.025))
                    Path { path in
                        for index in 1..<8 {
                            let fraction = Double(index) / 8
                            path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                        }
                        for fraction in [0.25, 0.5, 0.75] {
                            path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                        }
                    }.stroke(.white.opacity(0.05), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: x * geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: x * geometry.size.width, y: geometry.size.height))
                        path.move(to: CGPoint(x: 0, y: (1 - y) * geometry.size.height))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: (1 - y) * geometry.size.height))
                    }.stroke(tint.opacity(0.35), lineWidth: 0.5)
                    Circle().fill(tint).frame(width: 7, height: 7)
                        .position(x: x * geometry.size.width, y: (1 - y) * geometry.size.height)
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.12)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    setFilter(min(1, max(0, event.location.x / max(1, geometry.size.width))))
                    model.reverbMix = min(1, max(0, 1 - event.location.y / max(1, geometry.size.height)))
                })
                .onTapGesture(count: 2) { reset() }
                .contextMenu { Button("Reset Filter and Space", action: reset) }
                .accessibilityRepresentation {
                    VStack {
                        Slider(value: Binding(get: { x }, set: setFilter), in: 0...1).accessibilityLabel("\(name) filter")
                        Slider(value: Binding(get: { y }, set: { model.reverbMix = $0 }), in: 0...1).accessibilityLabel("\(name) space")
                    }
                }
                .accessibilityIdentifier("\(name)-xy-pad")
                .help(bipolar ? "X: low-pass / bypass / high-pass. Y: reverb 0–100%. Double-click to reset." : "X: low-pass 20 Hz–20 kHz. Y: reverb 0–100%. Double-click to reset.")
            }
            HStack {
                Text("FILTER →").fixedSize()
                Spacer()
                Text("SPACE ↑").fixedSize()
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Reset \(name) filter and space")
            }.font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
