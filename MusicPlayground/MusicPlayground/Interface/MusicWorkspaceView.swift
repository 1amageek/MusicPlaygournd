import AVFoundation
import SwiftUI
import MusicPlaygroundUI

struct MusicWorkspaceView: View {
    @State private var audio: AudioWorkspace?
    @State private var startupFailure: String?
    @State private var retry = 0
    @State private var documents = DocumentWorkspace(files: ProjectFiles(
        projectsDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Projects"),
        dependencyRoot: Bundle.main.resourceURL?.appending(path: "PackageSources/SwiftMusic")))
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var colors: [Color] = [NativeDeckView.restoreColor("A", fallback: .blue), NativeDeckView.restoreColor("B", fallback: Color(red: 0.86, green: 0.62, blue: 0.25))]
    @State private var maximumTakeMinutes = 10
    @Environment(\.scenePhase) private var phase

    var body: some View {
        WorkspaceSplitView(visibility: $visibility) {
            DocumentSidebar(workspace: documents, template: DemoMusic.source) { url, index in
                Task {
                    await documents.openFile(url, deck: index)
                    if let document = documents.selectedDocument(in: index), document.url == url { await load(document, into: index) }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if let audio {
                    DeckRack {
                        NativeDeckView(audio: audio, documents: documents, index: 0, color: $colors[0], maximumTakeMinutes: $maximumTakeMinutes, load: load)
                    } master: {
                        NativeMasterView(audio: audio, colors: colors, maximumTakeMinutes: $maximumTakeMinutes)
                    } b: {
                        NativeDeckView(audio: audio, documents: documents, index: 1, color: $colors[1], maximumTakeMinutes: $maximumTakeMinutes, load: load)
                    }
                } else {
                    VStack {
                        if let startupFailure {
                            Text(startupFailure).foregroundStyle(.orange)
                            Button("Retry Audio Setup") { retry += 1 }.contentShape(Rectangle())
                        } else { ProgressView("Preparing audio…") }
                    }.frame(height: 208)
                }
                Divider()
                DocumentEditor(workspace: documents, audibleIDs: audio.map { [$0.a.isPlaying ? $0.a.documentID : nil, $0.b.isPlaying ? $0.b.documentID : nil] } ?? [nil, nil],
                    colors: colors, load: { document, index in Task { await load(document, into: index) } }, audio: audio, visibility: $visibility)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("").toolbar(removing: .sidebarToggle).toolbarVisibility(.hidden, for: .navigationBar)
        }.preferredColorScheme(.dark).tint(.mint)
        .task(id: retry) {
            do {
                if audio == nil { audio = try AudioWorkspace() }
                documents.sourceDidChange = { [weak audio] id, range, replacement in
                    audio?.a.sourceEdited(id: id, range: range, replacement: replacement)
                    audio?.b.sourceEdited(id: id, range: range, replacement: replacement)
                }
                await documents.start(template: DemoMusic.source)
                if let document = documents.activeDocument, document.source == DemoMusic.source, audio?.a.loop == nil {
                    await load(document, into: 0)
                    await load(document, into: 1)
                }
                startupFailure = nil
            } catch { startupFailure = error.localizedDescription }
        }
        .task {
            do {
                while !Task.isCancelled {
                    audio?.refresh()
                    try await Task.sleep(for: .milliseconds(33))
                }
            } catch is CancellationError { }
            catch { audio?.error = error.localizedDescription }
            await stop()
        }
        .onChange(of: phase) { _, value in if value != .active { Task { await stop() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in Task { await stop() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in Task { await stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)) { _ in Task { await stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { await stop() } }
        }
        .alert("Audio", isPresented: Binding(get: { audioError != nil }, set: { if !$0 { clearAudioError() } })) {
            Button("OK") { clearAudioError() }.contentShape(Rectangle())
        } message: { Text(audioError ?? "") }
    }
    private var audioError: String? { audio?.error ?? audio?.a.error ?? audio?.b.error }
    private func clearAudioError() { audio?.error = nil; audio?.a.error = nil; audio?.b.error = nil }
    private func stop() async {
        do { try await audio?.stop() } catch { audio?.error = error.localizedDescription }
    }
    private func load(_ document: SourceDocument, into index: Int) async {
        guard let audio else { return }
        let source = document.source, id = document.id, url = document.url
        do {
            try documents.attach(id, to: index)
            try await audio.deck(index).prepare(id: id, source: source)
            try await audio.hosts[index].restore(for: url)
        } catch is CancellationError { }
        catch { audio.deck(index).error = error.localizedDescription }
    }
}
