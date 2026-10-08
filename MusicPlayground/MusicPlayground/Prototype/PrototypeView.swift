import AVFoundation
import SwiftUI
import MusicPlaygroundUI

struct PrototypeView: View {
    @State private var model = PlaybackModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var selection: String? = "Session.swift"
    @State private var effectInfo = false

    var body: some View {
        WorkspaceSplitView(visibility: $visibility) {
            ProjectSidebar(selection: $selection) {
                Section("Bundled Music") {
                    Label("Session.swift", systemImage: "swift").tag("Session.swift")
                        .accessibilityIdentifier("bundled-source-file")
                }
                Section("Monitor") {
                    Label("Audio Output", systemImage: "speaker.wave.2").tag("Audio Output")
                        .accessibilityIdentifier("audio-output-item")
                }
                Section("Package Dependencies") {
                    Label("SwiftMusic 0.5.1", systemImage: "shippingbox")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Label("Bundled project · read only", systemImage: "lock")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).frame(height: 36)
            }
            .navigationTitle("MusicPlayground")
        } detail: {
            VStack(spacing: 0) {
                DeckRack { deckA } master: { master } b: { deckB }
                Divider()
                EditorPane {
                    HStack(spacing: 8) {
                        SidebarToggle(visibility: $visibility)
                        Divider()
                        Text("A").fontWeight(.bold).foregroundStyle(.mint)
                        Label(selection ?? "No Selection", systemImage: selection == "Session.swift" ? "swift" : "speaker.wave.2")
                        Spacer()
                        Text("Read only").foregroundStyle(.secondary).padding(.trailing, 12)
                    }.font(.system(size: 11))
                } content: {
                    if selection == "Session.swift" {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): The iPad workspace displays bundled read-only source here.
                        // PrototypeView uses this production path; editable source execution needs a real backend
                        // and success/failure verification before editing or compile controls may be enabled.
                        SourceCodeView(source: DemoMusic.source)
                    } else if selection == "Audio Output" {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Audio Output", systemImage: "speaker.wave.2").font(.headline)
                            Text(model.route)
                            Text("44100 Hz · Stereo · Native AVAudioEngine")
                            Text("Output evidence measures the audio graph before speaker volume.")
                                .foregroundStyle(.secondary)
                        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .accessibilityIdentifier("audio-output-detail")
                    } else {
                        Text("No Selection").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Text(status).accessibilityIdentifier("playbackStatus")
                    Spacer()
                    Text("\(model.eventCount) events · \(model.callbackCount) audio callbacks · peak \(model.peak, format: .number.precision(.fractionLength(3)))")
                        .accessibilityIdentifier("outputEvidence")
                }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 12).frame(height: 36)
            }
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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

    private var deckA: some View {
        DeckPanel {
            HStack(spacing: 8) {
                Text("A").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 21, height: 24).background(.mint, in: RoundedRectangle(cornerRadius: 4))
                Text("Session").font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                TransportButton(symbol: "play.fill", label: "Play", enabled: model.state != .preparing && model.state != .playing && model.state != .stopping) {
                    Task { await model.play() }
                }.accessibilityIdentifier("play")
                TransportButton(symbol: "stop.fill", label: "Stop") { Task { await model.stop() } }
                    .accessibilityIdentifier("stop")
            }
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("120").font(.system(size: 22, weight: .medium, design: .rounded))
                    Text("BPM · 4/4").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { effectInfo = true } label: {
                        Text("FX").font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 25)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("iPad FX availability")
                        .accessibilityIdentifier("ipad-fx-info")
                        .popover(isPresented: $effectInfo) {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): iPad has no live FX backend in this production branch.
                            // PrototypeView presents availability only; real DSP adoption and rollback must be
                            // verified before effect controls can become executable.
                            UnavailableEffectView(reason: "Live effects are not implemented in this iPad prototype. macOS uses the shared FX controls with its native DSP backend.")
                        }
                }
                Text("Melody · Bass · Kick · Hat").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(model.state == .preparing ? "Rendering SwiftMusic…" : "Bundled SwiftMusic score")
                    .font(.system(size: 10)).foregroundStyle(.mint)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } wave: {
            LoopWaveView(peaks: model.loopPeaks, position: 0, color: .mint)
        }
    }

    private var master: some View {
        VStack(spacing: 10) {
            Text("MASTER").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Image(systemName: "speaker.wave.2").font(.system(size: 26)).foregroundStyle(.mint)
            ProgressView(value: min(1, Double(model.peak))).tint(.mint)
            Text(model.route).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
        }.padding(12)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The iPad composition currently owns one audio player.
    // PrototypeView displays the shared Deck B slot as unavailable; independent playback and
    // mixing must be verified before this production branch can enable a second transport.
    private var deckB: some View {
        DeckPanel {
            HStack {
                Text("B").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 21, height: 24).background(.orange, in: RoundedRectangle(cornerRadius: 4))
                Text("No music loaded").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } controls: {
            Text("Deck B is unavailable in the iPad prototype.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } wave: {
            Text("No prepared audio").font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
