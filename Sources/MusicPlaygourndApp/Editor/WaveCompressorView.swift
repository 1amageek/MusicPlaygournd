import SwiftUI
import MusicPlaygourndCore

struct WaveCompressorView: View {
    let settings: MasterCompressorSettings
    let snapshot: MasterCompressorSnapshot
    let onChange: (MasterCompressorSettings) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Compressor", isOn: Binding(get: { settings.enabled }, set: {
                    var value = settings; value.enabled = $0; onChange(value)
                }))
                .toggleStyle(.switch).controlSize(.mini)
                .accessibilityIdentifier("compressor-enabled")
                Spacer()
                Text(String(format: "GR  −%.1f dB", snapshot.gainReduction))
                    .monospacedDigit().foregroundStyle(.mint)
                    .accessibilityLabel("Gain reduction")
                Button("Reset") { onChange(.defaults) }
                    .buttonStyle(.plain).accessibilityLabel("Reset compressor")
                    .accessibilityIdentifier("compressor-reset")
            }.font(.system(size: 11))

            GeometryReader { geometry in
                let halfHeight = max(1, (geometry.size.height - 36) / 2)
                let center = geometry.size.height / 2
                let threshold = pow(10, settings.threshold / 20)
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        var axis = Path()
                        axis.move(to: CGPoint(x: 0, y: center))
                        axis.addLine(to: CGPoint(x: size.width, y: center))
                        context.stroke(axis, with: .color(.white.opacity(0.12)), lineWidth: 1)
                        for (values, isInput) in [(snapshot.inputEnvelope, true), (snapshot.outputEnvelope, false)] {
                            let count = values.count / 2
                            var wave = Path()
                            for index in 0..<count {
                                let x = CGFloat(index) / CGFloat(max(1, count - 1)) * size.width
                                wave.move(to: CGPoint(x: x, y: center - CGFloat(min(1, max(-1, values[index * 2]))) * halfHeight))
                                wave.addLine(to: CGPoint(x: x, y: center - CGFloat(min(1, max(-1, values[index * 2 + 1]))) * halfHeight))
                            }
                            if isInput {
                                context.stroke(wave, with: .color(.white.opacity(0.24)), lineWidth: 1)
                            } else {
                                context.addFilter(.shadow(color: .mint.opacity(0.45), radius: 3))
                                context.stroke(wave, with: .linearGradient(Gradient(colors: [.mint, .cyan, .indigo]),
                                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1)
                            }
                        }
                    }.allowsHitTesting(false)
                    ForEach([-1.0, 1.0], id: \.self) { direction in
                        let y = center + direction * threshold * halfHeight
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(.mint.opacity(settings.enabled ? 0.9 : 0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .allowsHitTesting(false)
                    }
                    Circle().fill(.mint).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        .position(x: geometry.size.width - 12, y: center - threshold * halfHeight)
                        .allowsHitTesting(false)
                    HStack {
                        Text(String(format: "THRESHOLD  %.1f dBFS", settings.threshold))
                        Spacer()
                        Text("PRE").foregroundStyle(.secondary)
                        Text("POST").foregroundStyle(.mint)
                    }.font(.system(size: 9, design: .monospaced)).padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    let amplitude = min(1, max(0.001, abs(event.location.y - center) / halfHeight))
                    change(\.threshold, to: max(-60, min(0, 20 * log10(amplitude))))
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Compressor threshold")
                .accessibilityValue(String(format: "%.1f dBFS", settings.threshold))
                .accessibilityIdentifier("compressor-threshold")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: change(\.threshold, to: min(0, settings.threshold + 1))
                    case .decrement: change(\.threshold, to: max(-60, settings.threshold - 1))
                    @unknown default: break
                    }
                }
                .help("Drag the waveform vertically to set the compression threshold. Pre/post traces use the same frames, before master volume.")
            }
            HStack(spacing: 20) {
                control("Ratio", keyPath: \.ratio, range: 1...20, unit: ":1")
                control("Attack", keyPath: \.attackMilliseconds, range: 0.1...200, unit: " ms", logarithmic: true)
                control("Release", keyPath: \.releaseMilliseconds, range: 10...2000, unit: " ms", logarithmic: true)
            }
        }.padding(12)
    }

    private func change(_ keyPath: WritableKeyPath<MasterCompressorSettings, Double>, to number: Double) {
        var value = settings
        value[keyPath: keyPath] = number
        value.enabled = true
        onChange(value)
    }

    private func control(_ title: String, keyPath: WritableKeyPath<MasterCompressorSettings, Double>,
                         range: ClosedRange<Double>, unit: String, logarithmic: Bool = false) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", settings[keyPath: keyPath]) + unit).monospacedDigit()
            }.font(.system(size: 10))
            Slider(value: Binding(
                get: { logarithmic ? log(settings[keyPath: keyPath]) : settings[keyPath: keyPath] },
                set: { change(keyPath, to: min(range.upperBound, max(range.lowerBound, logarithmic ? exp($0) : $0))) }
            ), in: logarithmic ? log(range.lowerBound)...log(range.upperBound) : range)
            .controlSize(.small).tint(.mint)
            .accessibilityLabel("Compressor " + title)
            .accessibilityValue(String(format: "%.1f", settings[keyPath: keyPath]) + unit)
        }
    }
}
