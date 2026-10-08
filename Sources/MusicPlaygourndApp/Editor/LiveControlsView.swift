import MusicPlaygroundUI
import AppKit
import MusicPlaygourndCore
import SwiftMusic
import SwiftUI
import UniformTypeIdentifiers

struct LiveControlsView: View {
    @Bindable var model: SessionModel
    @Binding var maximumTakeMinutes: Int
    @State private var midiExpanded = false

    private var descriptors: [LiveControlDescriptor] { model.controlCatalog?.descriptors ?? [] }
    private var targets: [LiveControlTarget] {
        var seen = Set<LiveControlTarget>()
        return descriptors.compactMap { seen.insert($0.address.target).inserted ? $0.address.target : nil }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 10) {
                trackMeters
                if !model.performanceControlMetadata.isEmpty {
                    performanceControls
                    Divider()
                }
                HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    if !targets.isEmpty { Picker("Controls", selection: Binding(get: { model.selectedControl?.target ?? .master }, set: { target in
                        model.selectedControl = descriptors.first { $0.address.target == target }?.address
                    })) {
                        ForEach(targets, id: \.self) { Text(label($0)).tag($0) }
                    }.accessibilityIdentifier("control-group") }
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(descriptors.filter { $0.address.target == model.selectedControl?.target }, id: \.address) { descriptor in
                            if let presentation = descriptor.presentation {
                                ControlKnob(label: descriptor.label, value: model.controlValue(descriptor), presentation: presentation,
                                    selected: model.selectedControl == descriptor.address, onChange: { value in
                                        model.selectedControl = descriptor.address
                                        perform { try model.setControl(descriptor.address, value: .number(value)) }
                                    }, onRelease: { perform { try model.setControl(descriptor.address, value: nil) } },
                                    onFailure: { model.hostDiagnostic = $0.localizedDescription })
                                .disabled(descriptor.address.target != .master && !model.controlsAvailable)
                                .contextMenu {
                                    Button("MIDI Learn") { perform { try model.beginMIDILearn(descriptor.address) } }
                                        .disabled(model.midiRoute.input == nil)
                                    Button("Remove MIDI Binding") { model.clearMIDILearn(descriptor.address) }
                                }
                            }
                        }
                    }
                    if let visualization = model.controlVisualization {
                        ControlTraceResult(visualization: visualization).frame(height: 64)
                    }
                    Text(model.visualizationStatus).font(.system(size: 9)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("control-visualization-status")
                    if descriptors.isEmpty { Text("Play a score to expose its controls.").foregroundStyle(.secondary) }
                }.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                hostControls.frame(width: 300).disabled(model.isRestoringHostState)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minWidth: 740, alignment: .leading)
        }
        .font(.system(size: 11)).frame(height: midiExpanded ? 540 : 300)
        .task {
            do { try await model.refreshHostDevices() }
            catch is CancellationError { }
            catch { model.hostDiagnostic = error.localizedDescription }
        }
    }

    private var trackMeters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(model.loop?.meters ?? [], id: \.target) { meter in
                    let index = min(meter.peaks.count - 1, max(0, Int(model.beatPosition / (model.loop?.beatCount ?? 1) * Double(meter.peaks.count))))
                    let peak = model.isPlaying && index >= 0 ? meter.peaks[index] : 0
                    HStack(spacing: 5) {
                        Text(meter.label)
                        ProgressView(value: Double(min(1, peak))).frame(width: 48).tint(peak >= 1 ? .red : .mint)
                        Text(peak >= 1 ? "CLIP" : String(format: "%.2f", peak))
                    }.accessibilityLabel("\(meter.label) rendered peak \(peak)")
                }
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }.scrollIndicators(.hidden)
    }

    private var performanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Performance").font(.system(size: 11, weight: .semibold))
                if model.isPerformanceUpdating {
                    ProgressView().controlSize(.mini)
                    Text("Applying…").foregroundStyle(.secondary)
                }
                Spacer()
                if let id = model.performanceControlMetadata.first(where: {
                    if case .double(_, let role) = $0.domain { return role == .beatsPerMinute }
                    return false
                })?.controlID, let value = model.performanceNumber(id) {
                    Text(String(format: "%.0f BPM", value)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.mint)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(model.performanceControlMetadata, id: \.controlID) { metadata in
                        performanceControl(metadata)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .disabled(!model.controlsAvailable || model.isPreparing)
        .accessibilityIdentifier("performance-controls")
    }

    @ViewBuilder
    private func performanceControl(_ metadata: PerformanceControlMetadata) -> some View {
        switch metadata.domain {
        case .double(let range, let role):
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.label).font(.system(size: 9)).lineLimit(1)
                Slider(value: Binding(
                    get: { model.performanceNumber(metadata.controlID) ?? range.lowerBound },
                    set: { value in perform { try model.setPerformanceValue(metadata.controlID, value: .double(value)) } }
                ), in: range)
                Text(role == .beatsPerMinute
                     ? String(format: "%.0f BPM", model.performanceNumber(metadata.controlID) ?? range.lowerBound)
                     : String(format: "%.3g", model.performanceNumber(metadata.controlID) ?? range.lowerBound))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.mint)
            }
            .frame(width: 140)
            .accessibilityIdentifier("performance-\(metadata.controlID)")
        case .position(let xRange, let depthRange):
            let position = model.performancePosition(metadata.controlID)
                ?? SpatialPosition(x: xRange.lowerBound, depth: depthRange.lowerBound)
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.label).font(.system(size: 9)).lineLimit(1)
                Slider(value: Binding(get: { position.x }, set: { x in
                    perform { try model.setPerformancePosition(metadata.controlID, x: x) }
                }), in: xRange).accessibilityLabel("\(metadata.label) X")
                Slider(value: Binding(get: { position.depth }, set: { depth in
                    perform { try model.setPerformancePosition(metadata.controlID, depth: depth) }
                }), in: depthRange).accessibilityLabel("\(metadata.label) Depth")
                Text(String(format: "x %.2f · depth %.2f", position.x, position.depth))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.cyan)
            }
            .frame(width: 140)
            .accessibilityLabel(metadata.label)
            .accessibilityIdentifier("performance-\(metadata.controlID)")
        }
    }

    private var hostControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            MIDIOptions(inputs: model.midiEndpoints.filter { $0.direction == .input }.map { HostChoice(id: $0.id, name: $0.displayName) },
                outputs: model.midiEndpoints.filter { $0.direction == .output }.map { HostChoice(id: $0.id, name: $0.displayName) },
                input: Binding(get: { model.midiRoute.input }, set: { input in
                    var route = model.midiRoute; route.input = input
                    if case .receive = route.clockMode { route.clockMode = input.map { .receive(input: $0) } ?? .off }
                    perform { try await model.configureMIDI(route) }
                }), output: Binding(get: { model.midiRoute.output }, set: { output in
                    var route = model.midiRoute; route.output = output
                    if output == nil { route.sendsLoopNotes = false }
                    if case .send = route.clockMode { route.clockMode = output.map { .send(output: $0) } ?? .off }
                    perform { try await model.configureMIDI(route) }
                }), notes: Binding(get: { model.midiRoute.sendsLoopNotes }, set: { enabled in
                    var route = model.midiRoute; route.sendsLoopNotes = enabled
                    perform { try await model.configureMIDI(route) }
                }), clock: Binding(get: {
                    switch model.midiRoute.clockMode { case .off: "off"; case .send: "send"; case .receive: "receive" }
                }, set: { mode in
                    var route = model.midiRoute
                    switch mode {
                    case "send": route.clockMode = route.output.map { .send(output: $0) } ?? .off
                    case "receive": route.clockMode = route.input.map { .receive(input: $0) } ?? .off
                    default: route.clockMode = .off
                    }
                    perform { try await model.configureMIDI(route) }
                }), refresh: { perform { try await model.refreshHostDevices() } },
                selectedControl: model.selectedControl.flatMap { address in model.controlCatalog?.descriptor(for: address).map { label(address.target) + " · " + $0.label } },
                learning: model.selectedControl != nil && model.learnAddress == model.selectedControl,
                bindingDescription: model.learnedBindings.first { $0.address == model.selectedControl }.map { "Channel \($0.channel) · CC \($0.controller)" },
                learn: { if let selected = model.selectedControl { perform { try model.beginMIDILearn(selected) } } },
                cancelLearn: model.cancelMIDILearn,
                removeBinding: { if let selected = model.selectedControl { model.clearMIDILearn(selected) } }, expanded: $midiExpanded)
            Picker("Audio Unit", selection: Binding(get: {
                if case .loaded(let descriptor, _) = model.hostedEffect { return Optional(descriptor.id) }
                return nil
            }, set: { id in perform { try await model.selectHostedEffect(id) } })) {
                Text("No Audio Unit").tag(Optional<HostedAudioUnitID>.none)
                ForEach(model.audioEffects, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().disabled(model.isLoadingEffect || model.isRecording)
                .accessibilityIdentifier("audio-unit-picker")
            if case .loaded(let descriptor, let bypassed) = model.hostedEffect {
                Toggle("Bypass \(descriptor.name)", isOn: Binding(get: { bypassed }, set: { value in
                    perform { try model.bypassHostedEffect(value) }
                })).toggleStyle(.checkbox)
            }
            HStack {
                Picker("Maximum take", selection: $maximumTakeMinutes) {
                    ForEach([1, 5, 10, 30, 60, 120, 180], id: \.self) { Text("\($0) min").tag($0) }
                }.labelsHidden().disabled(model.isRecording)
                if model.isRecording {
                    Button("Stop & Save") { perform { _ = try await model.stopRecording() } }
                    Button("Discard") { perform { try await model.cancelRecording() } }
                } else {
                    Button("Record") { record() }.disabled(!model.isPlaying)
                }
            }
            HStack {
                Button(model.isExportingStems ? "Cancel Export" : "Export Stems") {
                    if model.isExportingStems { perform { try await model.cancelStemExport() } }
                    else { exportStems() }
                }.disabled(!model.controlsAvailable && !model.isExportingStems)
                Button("Save Settings") {
                    guard let document = model.fileURL else { return }
                    perform { try model.saveHostSettings(for: document) }
                }.disabled(model.fileURL == nil)
            }
        }
    }

    private func label(_ target: LiveControlTarget) -> String {
        switch target {
        case .source(let id): "Source \(id)"
        case .renderNode(let id): "Group \(id)"
        case .track(let id): "Track \(id)"
        case .master: "Master"
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await action() }
            catch is CancellationError { }
            catch { model.hostDiagnostic = error.localizedDescription }
        }
    }

    private func record() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "Take.wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        perform { try model.startRecording(to: destination, maximumDuration: .seconds(maximumTakeMinutes * 60)) }
    }

    private func exportStems() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Stems"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        perform { _ = try await model.exportStems(to: destination) }
    }
}
