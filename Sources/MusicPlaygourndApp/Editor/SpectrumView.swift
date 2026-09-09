import SwiftUI
import MusicPlaygourndCore

struct SpectrumView: View {
    let bands: [Float]
    let samples: [Float]
    let isPlaying: Bool
    var performance: PlaybackPerformanceSnapshot? = nil
    var resetDiagnostics: () -> Void = {}

    @State private var diagnosticsPresented = false

    var body: some View {
        Button { diagnosticsPresented = true } label: {
        VStack(spacing: 5) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
            Canvas { context, size in
                let frames = samples.count / 2
                let columns = max(1, min(512, Int(size.width)))
                for channel in 0..<2 {
                    var wave = Path()
                    for column in 0..<columns {
                        let start = column * frames / columns
                        let end = (column + 1) * frames / columns
                        guard start < end else { continue }
                        var low: Float = 0
                        var high: Float = 0
                        for frame in start..<end {
                            let value = samples[frame * 2 + channel]
                            if value.isFinite { low = min(low, value); high = max(high, value) }
                        }
                        let x = Double(column) / Double(columns) * size.width
                        let center = size.height * 0.5
                        wave.move(to: CGPoint(x: x, y: center - min(1, Double(high) * 4) * size.height * 0.47))
                        wave.addLine(to: CGPoint(x: x, y: center - max(-1, Double(low) * 4) * size.height * 0.47))
                    }
                    context.stroke(wave, with: .color(channel == 0 ? .mint : .cyan.opacity(0.65)), lineWidth: 1)
                }
            }.clipped().frame(height: 30).accessibilityLabel("Stereo master output waveform")
                .help("Latest 8,192 stereo PCM frames (186 milliseconds at 44.1 kHz). Display amplitude ×4; audio level is unchanged.")
            Text("MASTER OUTPUT").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            VStack(alignment: .leading, spacing: 5) {
            Canvas { context, size in
                let plotHeight = size.height
                for db in [-18, -48, -78] {
                    let y = Double(-db) / 90 * plotHeight
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.white.opacity(0.055)))
                }
                let width = size.width / Double(max(1, bands.count))
                for (index, db) in bands.enumerated() {
                    let height = max(0, Double(db + 90) / 90 * plotHeight)
                    let rect = CGRect(x: Double(index) * width, y: plotHeight - height, width: max(1, width - 2), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .linearGradient(
                        Gradient(colors: [.cyan.opacity(0.25), .mint]), startPoint: CGPoint(x: 0, y: plotHeight), endPoint: .zero))
                }

            }
            .frame(height: 30)
            .accessibilityLabel("Master output spectrum, 20 hertz to 20 kilohertz, \(isPlaying ? "playing" : "paused")")
            Text(performance?.clipped == true ? "SPECTRUM · CLIP" : "SPECTRUM")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(performance?.clipped == true ? Color.orange : .secondary)
            }.frame(maxWidth: .infinity)
        }.frame(height: 44)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Output diagnostics")
        .accessibilityIdentifier("output-diagnostics")
        .popover(isPresented: $diagnosticsPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("OUTPUT DIAGNOSTICS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                meters
            }.padding(16).frame(width: 420)
        }
    }
    private var meters: some View {
        HStack(spacing: 14) {
            if let performance {
                Text(performance.callbackLoad.map { String(format: "SOURCE CPU %.1f%%", $0 * 100) } ?? "SOURCE CPU —")
                    .help("Source callback time divided by its audio duration; excludes Audio Unit and system CPU.")
                Text("DROPOUTS \(performance.dropoutCount)")
                Text(performance.peak.map { String(format: "MASTER %.2f", $0) } ?? "MASTER —")
                Text(performance.clipped ? "CLIP" : "OK").foregroundStyle(performance.clipped ? .red : .mint)
                Button("Reset", action: resetDiagnostics).buttonStyle(.plain)
            } else { Text("Master telemetry unavailable") }
        }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).frame(height: 18)
    }

}
