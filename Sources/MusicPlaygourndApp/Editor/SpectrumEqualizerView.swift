import SwiftUI
import MusicPlaygourndCore

struct SpectrumEqualizerView: View {
    let spectrum: [Float]
    let isPlaying: Bool
    let bands: [MasterEqualizerBand]
    let responses: [MasterEqualizerResponse]
    let onChange: (Int, MasterEqualizerBand) -> Void
    var compact = false
    var tint: Color? = nil
    @State private var selected: Int? = 1
    private let colors: [Color] = [.mint, .cyan, .purple]

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 24)
            let top = compact ? 8.0 : 24.0
            let height = max(1, geometry.size.height - (compact ? 24 : 48))
            ZStack {
                SpectrumView(bands: spectrum, isPlaying: isPlaying, tint: tint).padding(.horizontal, 12)
                    .padding(.top, top).padding(.bottom, compact ? 16 : 24)
                    .opacity(0.6).allowsHitTesting(false)
                Canvas { context, size in
                    for bandIndex in 0..<(responses.isEmpty ? 0 : responses.count + 1) {
                        var path = Path()
                        for step in 0...192 {
                            let fraction = Double(step) / 192
                            let frequency = 20 * pow(1_000, fraction)
                            let db = bandIndex == responses.count
                                ? responses.reduce(0) { $0 + $1.decibels(at: frequency) }
                                : responses[bandIndex].decibels(at: frequency)
                            let point = CGPoint(x: 12 + fraction * width, y: top + (12 - db) / 24 * height)
                            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        let color = bandIndex == responses.count ? Color.white : (tint ?? colors[bandIndex % colors.count])
                        context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: bandIndex == responses.count ? 1.5 : 1)
                    }
                }.clipped().allowsHitTesting(false)
                Path { path in
                    path.move(to: CGPoint(x: 12, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width - 12, y: geometry.size.height / 2))
                }.stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .allowsHitTesting(false)
                if !compact {
                VStack {
                    HStack {
                        Text("EQ  +12 dB")
                        Spacer()
                        if let selected, bands.indices.contains(selected) {
                            Text(String(format: "%.0f Hz  %+.1f dB", bands[selected].frequency, bands[selected].gain))
                        }
                    }.allowsHitTesting(false)
                    Spacer().allowsHitTesting(false)
                    HStack(spacing: 8) {
                        Text("20 Hz")
                        Spacer()
                        if let selected, bands.indices.contains(selected) {
                            Stepper(value: Binding(get: { Double(bands[selected].q) }, set: {
                                var band = bands[selected]
                                band.q = Float($0)
                                onChange(selected, band)
                            }), in: 0.2...20, step: 0.1) {
                                Text(String(format: "Q %.2f", bands[selected].q))
                            }.fixedSize().accessibilityLabel("Selected EQ band Q")
                        }
                        Button("Reset") {
                            for index in bands.indices { onChange(index, MasterEqualizerBand.defaults[index]) }
                        }.buttonStyle(.plain).accessibilityLabel("Reset all EQ bands")
                        Spacer()
                        Text("20 kHz")
                    }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(8)
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Text("20"); Spacer(); Text("200"); Spacer(); Text("2k"); Spacer(); Text("20k")
                            Button { for index in bands.indices { onChange(index, MasterEqualizerBand.defaults[index]) } } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.plain).accessibilityLabel("Reset all EQ bands")
                        }.font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 8).padding(.bottom, 1)
                }
                ForEach(bands.indices, id: \.self) { index in
                    let band = bands[index]
                    let color = tint ?? colors[index % colors.count]
                    Button { selected = index } label: {
                        ZStack {
                            Circle().fill(color.opacity(0.25)).frame(width: 28, height: 28).blur(radius: 5)
                            Circle().fill(color).frame(width: compact ? 8 : 12, height: compact ? 8 : 12)
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        }.frame(width: compact ? 22 : 32, height: compact ? 22 : 32).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onKeyPress(.leftArrow) {
                        onChange(index, .init(frequency: max(20, band.frequency / 1.059463), gain: band.gain, q: band.q))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        onChange(index, .init(frequency: min(20_000, band.frequency * 1.059463), gain: band.gain, q: band.q))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        onChange(index, .init(frequency: band.frequency, gain: min(12, band.gain + 1), q: band.q))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        onChange(index, .init(frequency: band.frequency, gain: max(-12, band.gain - 1), q: band.q))
                        return .handled
                    }
                    .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("master-eq"))
                        .onChanged { gesture in
                            selected = index
                            let x = min(1, max(0, (gesture.location.x - 12) / width))
                            let y = min(1, max(0, (gesture.location.y - top) / height))
                            onChange(index, .init(frequency: Float(20 * pow(1_000, x)), gain: Float(12 - y * 24), q: band.q))
                        })
                    .position(x: 12 + log10(Double(band.frequency) / 20) / 3 * width,
                              y: top + (12 - Double(band.gain)) / 24 * height)
                    .accessibilityLabel("EQ band \(index + 1)")
                    .accessibilityValue(String(format: "%.0f hertz, %+.1f decibels, Q %.2f", band.frequency, band.gain, band.q))
                    .accessibilityAdjustableAction { direction in
                        let delta: Float = direction == .increment ? 1 : -1
                        onChange(index, .init(frequency: band.frequency, gain: min(12, max(-12, band.gain + delta)), q: band.q))
                    }
                    .contextMenu {
                        ControlGroup {
                            Button("Narrower Q") { onChange(index, .init(frequency: band.frequency, gain: band.gain, q: min(20, band.q * 1.25))) }
                            Button("Wider Q") { onChange(index, .init(frequency: band.frequency, gain: band.gain, q: max(0.2, band.q / 1.25))) }
                        }
                        Button("Reset Band") { onChange(index, MasterEqualizerBand.defaults[index]) }
                    }
                    .help("Drag horizontally for frequency, vertically for gain. Right-click for Q and reset. The expanded view also provides a Q stepper.")
                }
            }
            .coordinateSpace(name: "master-eq")
        }
    }
}
