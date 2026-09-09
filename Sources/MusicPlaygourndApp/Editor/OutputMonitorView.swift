import SwiftUI
import MusicPlaygourndCore

struct OutputMonitorView: View {
    let bands: [Float]
    let samples: [Float]
    let isPlaying: Bool
    let performance: PlaybackPerformanceSnapshot?
    let resetDiagnostics: () -> Void

    private enum Monitor: String, CaseIterable, Identifiable {
        case wave = "Wave", spectrum = "Spectrum", vectorscope = "Vectorscope"
        var id: Self { self }
    }

    @State private var presented: Monitor?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Monitor.allCases) { monitor in
                Button { presented = monitor } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        plot(monitor).frame(height: 22)
                        Text(monitor.rawValue.uppercased())
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open " + monitor.rawValue)
                .accessibilityIdentifier("monitor-" + monitor.rawValue.lowercased())
                .popover(isPresented: Binding(
                    get: { presented == monitor },
                    set: { if !$0 { presented = nil } }
                )) {
                    VStack(spacing: 16) {
                        HStack {
                            Text(monitor.rawValue).font(.headline)
                            Spacer()
                            Button { presented = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Close " + monitor.rawValue)
                        }
                        plot(monitor)
                            .frame(height: monitor == .vectorscope ? 360 : 220)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        if monitor == .wave { meters }
                    }
                    .padding(20).frame(width: 480)
                }
            }
        }.frame(height: 36)
    }

    @ViewBuilder
    private func plot(_ monitor: Monitor) -> some View {
        switch monitor {
        case .wave: WaveformView(samples: samples)
        case .spectrum: SpectrumView(bands: bands, isPlaying: isPlaying)
        case .vectorscope: VectorscopeView(samples: samples)
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
