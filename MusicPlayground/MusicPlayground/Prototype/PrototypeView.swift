import AVFoundation
import SwiftUI
import MusicPlaygroundUI

struct PrototypeView: View {
    @State private var model = PlaybackModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var effectInfo = false
    @State private var documents = DocumentWorkspace(files: ProjectFiles(
        projectsDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Projects"),
        dependencyRoot: Bundle.main.resourceURL?.appending(path: "PackageSources/SwiftMusic")))
    @State private var acceptedDocumentID: UUID?

    var body: some View {
        WorkspaceSplitView(visibility: $visibility) {
            DocumentSidebar(workspace: documents, template: DemoMusic.source) { url, deck in
                Task {
                    await documents.openFile(url, deck: deck)
                    if let document = documents.activeDocument, document.url == url { load(document, into: deck) }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                DeckRack { deckA } master: { master } b: { deckB }
                Divider()
                DocumentEditor(workspace: documents,
                    audibleIDs: [model.state == .playing ? acceptedDocumentID : nil, nil],
                    colors: [.mint, .orange], load: { load($0, into: $1) }, visibility: $visibility)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            await documents.start(template: DemoMusic.source)
            if documents.activeDocument?.source == DemoMusic.source { acceptedDocumentID = documents.activeDocument?.id }
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
                }.accessibilityIdentifier("play").accessibilityValue(status)
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
            .accessibilityElement(children: .ignore).accessibilityLabel("Master output")
            .accessibilityValue("\(status) · \(model.eventCount) events · \(model.callbackCount) audio callbacks · peak \(String(format: "%.3f", model.peak))")
            .accessibilityIdentifier("outputEvidence")
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

    // FIXME(INCOMPLETE_IMPLEMENTATION): The prototype adapter currently loads only its build-time score.
    // DocumentEditor and DocumentSidebar invoke this path; independent Deck B transport belongs
    // to the current audio sprint, while arbitrary edited-source compilation is a separate task.
    private func load(_ document: SourceDocument, into deck: Int) {
        if deck == 0, document.source == DemoMusic.source {
            acceptedDocumentID = document.id
            documents.errorMessage = nil
        } else if document.source != DemoMusic.source {
            documents.errorMessage = DocumentFailure.compilerRequired("Loading this edited Swift entry").localizedDescription
        } else {
            documents.errorMessage = "Independent Deck B playback is not connected yet."
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
