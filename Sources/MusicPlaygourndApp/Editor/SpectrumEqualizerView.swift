import SwiftUI
import MusicPlaygourndCore

struct SpectrumEqualizerView: View {
    let spectrum: [Float]
    let isPlaying: Bool
    let bands: [MasterEqualizerBand]
    let onChange: (Int, MasterEqualizerBand) -> Void
    @State private var selected: Int?
    private let colors: [Color] = [.mint, .cyan, .purple]

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 24)
            let height = max(1, geometry.size.height - 48)
            ZStack {
                SpectrumView(bands: spectrum, isPlaying: isPlaying).padding(.horizontal, 12)
                    .opacity(0.6).allowsHitTesting(false)
                Path { path in
                    path.move(to: CGPoint(x: 12, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width - 12, y: geometry.size.height / 2))
                }.stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .allowsHitTesting(false)
                VStack {
                    HStack {
                        Text("EQ  +12 dB")
                        Spacer()
                        if let selected, bands.indices.contains(selected) {
                            Text(String(format: "%.0f Hz  %+.1f dB", bands[selected].frequency, bands[selected].gain))
                        }
                    }
                    Spacer()
                    HStack { Text("20 Hz"); Spacer(); Text("−12 dB"); Spacer(); Text("20 kHz") }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(8).allowsHitTesting(false)
                ForEach(bands.indices, id: \.self) { index in
                    let band = bands[index]
                    let color = colors[index % colors.count]
                    Button { selected = index } label: {
                        ZStack {
                            Circle().fill(color.opacity(0.25)).frame(width: 28, height: 28).blur(radius: 5)
                            Circle().fill(color).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        }.frame(width: 32, height: 32).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onKeyPress(.leftArrow) {
                        onChange(index, .init(frequency: max(20, band.frequency / 1.059463), gain: band.gain))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        onChange(index, .init(frequency: min(20_000, band.frequency * 1.059463), gain: band.gain))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        onChange(index, .init(frequency: band.frequency, gain: min(12, band.gain + 1)))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        onChange(index, .init(frequency: band.frequency, gain: max(-12, band.gain - 1)))
                        return .handled
                    }
                    .position(x: 12 + log10(Double(band.frequency) / 20) / 3 * width,
                              y: 24 + (12 - Double(band.gain)) / 24 * height)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("master-eq"))
                        .onChanged { gesture in
                            selected = index
                            let x = min(1, max(0, (gesture.location.x - 12) / width))
                            let y = min(1, max(0, (gesture.location.y - 24) / height))
                            onChange(index, .init(frequency: Float(20 * pow(1_000, x)), gain: Float(12 - y * 24)))
                        })
                    .accessibilityLabel("EQ band \(index + 1)")
                    .accessibilityValue(String(format: "%.0f hertz, %+.1f decibels", band.frequency, band.gain))
                    .accessibilityAdjustableAction { direction in
                        let delta: Float = direction == .increment ? 1 : -1
                        onChange(index, .init(frequency: band.frequency, gain: min(12, max(-12, band.gain + delta))))
                    }
                    .contextMenu {
                        Button("Reset Band") { onChange(index, MasterEqualizerBand.defaults[index]) }
                    }
                    .help("Drag horizontally for frequency, vertically for gain. One-octave bandwidth. Right-click to reset.")
                }
            }
            .coordinateSpace(name: "master-eq")
        }
    }
}
