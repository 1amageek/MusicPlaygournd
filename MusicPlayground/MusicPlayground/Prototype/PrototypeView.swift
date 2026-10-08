import AVFoundation
import SwiftUI

struct PrototypeView: View {
    @State private var model = PlaybackModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Button {
                        Task { await model.play() }
                    } label: {
                        Label(model.state == .preparing ? "Preparing…" : "Play", systemImage: "play.fill")
                            .frame(minWidth: 100, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.state == .preparing || model.state == .playing || model.state == .stopping)
                    .accessibilityIdentifier("play")
                    Button { Task { await model.stop() } } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(minWidth: 100, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("stop")
                    Spacer()
                    Text("120 BPM · 4/4").monospacedDigit()
                }
                Text(status).font(.headline).accessibilityIdentifier("playbackStatus")
                Text("Bundled SwiftMusic score · standalone iPad playback")
                    .foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(DemoMusic.source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                Text(model.route).font(.footnote).foregroundStyle(.secondary)
                Text("\(model.eventCount) events · \(model.callbackCount) audio callbacks · peak \(model.peak, format: .number.precision(.fractionLength(3)))")
                    .font(.footnote.monospacedDigit())
                    .accessibilityIdentifier("outputEvidence")
            }
            .padding(24)
            .navigationTitle("MusicPlayground")
        }
        .tint(.mint)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.stop() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)) { _ in
            Task { await model.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { await model.stop() } }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                model.refreshOutput()
            }
        }
    }

    private var status: String {
        switch model.state {
        case .idle: "Ready"
        case .preparing: "Rendering SwiftMusic…"
        case .playing: "Playing on iPad"
        case .stopping: "Stopping…"
        case .failed(let message): "Error: \(message)"
        }
    }
}
