import SwiftUI
import MusicPlaygroundUI
import UniformTypeIdentifiers

struct NativeControlsView: View {
    @Bindable var audio: AudioWorkspace
    @Bindable var documents: DocumentWorkspace
    let index: Int
    @Binding var maximumTakeMinutes: Int
    private var selected: LiveControlAddress? {
        get { deck.selectedControl }
        nonmutating set { deck.selectedControl = newValue }
    }
    @State private var visualization: PreparedControlVisualization?
    @State private var visualizationStatus = "Select an accepted control."
    @State private var visualizationTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var chooseExport = false
    @State private var midiExpanded = false
    @State private var saved: URL?
    private var deck: AudioDeck { audio.deck(index) }
    private var host: DeckHost { audio.hosts[index] }
    private var descriptors: [LiveControlDescriptor] { deck.catalog?.descriptors ?? [] }
    private var targets: [LiveControlTarget] {
        var seen: Set<LiveControlTarget> = []
        return descriptors.compactMap { seen.insert($0.address.target).inserted ? $0.address.target : nil }
    }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 10) {
                meters
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !targets.isEmpty {
                            Picker("Controls", selection: Binding(get: { selected?.target ?? .master }, set: { target in
                                selected = descriptors.first { $0.address.target == target }?.address
                            })) { ForEach(targets, id: \.self) { Text(label($0)).tag($0) } }.accessibilityIdentifier("control-group")
                        }
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(descriptors.filter { $0.address.target == selected?.target }, id: \.address) { descriptor in
                                if let presentation = descriptor.presentation {
                                    ControlKnob(label: descriptor.label, value: deck.controlValue(descriptor), presentation: presentation,
                                        selected: selected == descriptor.address,
                                        onChange: { value in selected = descriptor.address; perform { try await deck.setControl(descriptor.address, value: .number(value)) } },
                                        onRelease: { perform { try await deck.setControl(descriptor.address, value: nil) } },
                                        onFailure: { host.error = $0.localizedDescription })
                                        .contextMenu {
                                            Button("MIDI Learn") { perform { try host.beginLearn(descriptor.address) } }.disabled(host.route.input == nil)
                                            Button("Remove MIDI Binding") { host.clearLearn(descriptor.address) }
                                        }
                                }
                            }
                        }
                        if let visualization { ControlTraceView(value: visualization).frame(height: 64) }
                        Text(visualizationStatus).font(.system(size: 9)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("control-visualization-status")
                        if descriptors.isEmpty { Text("Play a score to expose its controls.").foregroundStyle(.secondary) }
                    }.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    hostControls.frame(width: 300)
                }
                if let error = host.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                if let saved { ShareLink("Save or Share \(saved.lastPathComponent)", item: saved).contentShape(Rectangle()) }
            }.padding(.horizontal, 20).padding(.vertical, 14).frame(minWidth: 740, alignment: .leading)
        }.font(.system(size: 11)).frame(height: midiExpanded ? 540 : 300)
        .task {
            do { try await host.discover() } catch is CancellationError { } catch { host.error = error.localizedDescription }
            if selected == nil { selected = descriptors.first?.address }
            updateVisualization()
        }
        .onChange(of: selected) { _, _ in updateVisualization() }
        .onChange(of: deck.overrides) { _, _ in updateVisualization() }
        .onChange(of: deck.catalog) { _, _ in
            if let selected, deck.catalog?.descriptor(for: selected) == nil { self.selected = descriptors.first?.address }
        }
        .onDisappear { visualizationTask?.cancel(); exportTask?.cancel() }
        .fileImporter(isPresented: $chooseExport, allowedContentTypes: [.folder]) { result in
            switch result {
            case .failure(let error): host.error = error.localizedDescription
            case .success(let directory):
                exportTask = Task {
                    guard directory.startAccessingSecurityScopedResource() else { host.error = "The destination folder is not accessible."; return }
                    defer { directory.stopAccessingSecurityScopedResource(); exportTask = nil }
                    do {
                        let destination = directory.appending(path: "Stems-" + UUID().uuidString)
                        _ = try await deck.export(to: destination); saved = destination
                    } catch is CancellationError { }
                    catch { host.error = error.localizedDescription }
                }
            }
        }
    }
    private var meters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(deck.loop?.meters ?? [], id: \.target) { meter in
                    let position = deck.beatPosition.truncatingRemainder(dividingBy: deck.loop?.beatCount ?? 1)
                    let bin = min(meter.peaks.count - 1, max(0, Int(position / (deck.loop?.beatCount ?? 1) * Double(meter.peaks.count))))
                    let peak = deck.isPlaying && bin >= 0 ? meter.peaks[bin] : 0
                    HStack(spacing: 5) {
                        Text(meter.label)
                        ProgressView(value: Double(min(1, peak))).frame(width: 48).tint(peak >= 1 ? .red : .mint)
                        Text(peak >= 1 ? "CLIP" : String(format: "%.2f", peak))
                    }.accessibilityLabel("\(meter.label) rendered peak \(peak)")
                }
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }.scrollIndicators(.hidden)
    }
    private var hostControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            MIDIOptions(inputs: host.endpoints.filter { $0.direction == .input }.map { HostChoice(id: $0.id, name: $0.displayName) },
                outputs: host.endpoints.filter { $0.direction == .output }.map { HostChoice(id: $0.id, name: $0.displayName) },
                input: Binding(get: { host.route.input }, set: { input in
                    var route = host.route; route.input = input
                    if case .receive = route.clockMode { route.clockMode = input.map { .receive(input: $0) } ?? .off }
                    perform { try await host.configure(route) }
                }), output: Binding(get: { host.route.output }, set: { output in
                    var route = host.route; route.output = output
                    if output == nil { route.sendsLoopNotes = false }
                    if case .send = route.clockMode { route.clockMode = output.map { .send(output: $0) } ?? .off }
                    perform { try await host.configure(route) }
                }), notes: Binding(get: { host.route.sendsLoopNotes }, set: { value in
                    var route = host.route; route.sendsLoopNotes = value; perform { try await host.configure(route) }
                }), clock: Binding(get: {
                    switch host.route.clockMode { case .off: "off"; case .send: "send"; case .receive: "receive" }
                }, set: { value in
                    var route = host.route
                    switch value {
                    case "send": route.clockMode = route.output.map { .send(output: $0) } ?? .off
                    case "receive": route.clockMode = route.input.map { .receive(input: $0) } ?? .off
                    default: route.clockMode = .off
                    }
                    perform { try await host.configure(route) }
                }), refresh: { perform { try await host.discover() } },
                selectedControl: selected.flatMap { address in deck.catalog?.descriptor(for: address).map { label(address.target) + " · " + $0.label } },
                learning: selected != nil && host.learning == selected,
                bindingDescription: host.bindings.first { $0.address == selected }.map { "Channel \($0.channel) · CC \($0.controller)" },
                learn: { if let selected { perform { try host.beginLearn(selected) } } },
                cancelLearn: host.cancelLearn,
                removeBinding: { if let selected { host.clearLearn(selected) } }, expanded: $midiExpanded)
            Picker("Audio Unit", selection: Binding(get: {
                if case .loaded(let descriptor, _) = deck.hosted { return Optional(descriptor.id) }; return nil
            }, set: { id in perform { try await host.selectEffect(id) } })) {
                Text("No Audio Unit").tag(Optional<HostedAudioUnitID>.none)
                ForEach(host.effects, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().disabled(host.isLoadingEffect || audio.isRecording).accessibilityIdentifier("audio-unit-picker")
            if case .loaded(let descriptor, let bypassed) = deck.hosted {
                Toggle("Bypass \(descriptor.name)", isOn: Binding(get: { bypassed }, set: { value in perform { try host.bypassEffect(value) } }))
                    .toggleStyle(.switch).controlSize(.mini)
            }
            HStack {
                Picker("Maximum take", selection: $maximumTakeMinutes) {
                    ForEach([1, 5, 10, 30, 60, 120, 180], id: \.self) { Text("\($0) min").tag($0) }
                }.labelsHidden().disabled(audio.isRecording)
                if audio.isRecording {
                    Button("Stop & Save") { perform { saved = try await audio.output.stopRecording().destination; audio.refresh() } }.contentShape(Rectangle())
                    Button("Discard") { perform { try await audio.output.cancelRecording(); audio.refresh() } }.contentShape(Rectangle())
                } else {
                    Button("Record") { perform {
                        let destination = try Self.exportDestination(name: "Take", extension: "wav")
                        try audio.output.startRecording(MasterRecordingRequest(destination: destination, maximumDuration: .seconds(maximumTakeMinutes * 60)))
                        audio.refresh()
                    } }.contentShape(Rectangle()).disabled(!audio.a.isPlaying && !audio.b.isPlaying)
                }
            }
            HStack {
                Button(exportTask == nil ? "Export Stems" : "Cancel Export") {
                    if let exportTask { exportTask.cancel() } else { chooseExport = true }
                }.contentShape(Rectangle()).disabled(deck.loop == nil && exportTask == nil)
                Button("Save Settings") {
                    if let id = deck.documentID, let document = documents.documents.first(where: { $0.id == id }) {
                        perform { try host.save(for: document.url) }
                    }
                }.contentShape(Rectangle()).disabled(deck.documentID == nil)
            }
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task { do { try await action() } catch is CancellationError { } catch { host.error = error.localizedDescription } }
    }
    private func label(_ target: LiveControlTarget) -> String {
        switch target { case .master: "Master"; case .track(let id): "Track \(id)"; case .source(let id): "Source \(id)"; case .renderNode(let id): "Group \(id)" }
    }
    private func updateVisualization() {
        visualizationTask?.cancel(); visualization = nil
        guard let address = selected else { visualizationStatus = "Select an accepted control."; return }
        visualizationTask = Task {
            do {
                let value = try await deck.visualization(for: address)
                try Task.checkCancellation(); guard selected == address else { return }
                visualization = value; visualizationStatus = "\(address.parameter) · \(value.traces.count) voices"
            } catch is CancellationError { }
            catch ControlVisualizationError.unsupported { visualizationStatus = "This control has no render trajectory." }
            catch { visualizationStatus = error.localizedDescription }
        }
    }
    static func exportDestination(name: String, extension suffix: String) throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Recordings")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name + "-" + UUID().uuidString).appendingPathExtension(suffix)
    }
}
