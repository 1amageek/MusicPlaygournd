import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns global music controls in the native window toolbar.
struct MusicHeaderView: View {
    @Bindable var model: SessionModel
    @State private var controlsPresented = false
    @State private var maximumTakeMinutes = 10

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.primary)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("play-toggle")
                    .disabled(!model.hasOpenDocument && !model.isPlaying)
                Button(action: record) {
                    Image(systemName: model.isRecording ? "stop.circle" : "record.circle")
                        .font(.system(size: 18)).foregroundStyle(model.isRecording ? Color.red : .secondary)
                }.buttonStyle(.plain).disabled(!model.isPlaying && !model.isRecording)
                    .accessibilityLabel(model.isRecording ? "Stop and save recording" : "Record")
                    .accessibilityIdentifier("record-toggle")
                VStack(alignment: .leading, spacing: 2) {
                    Text("BPM").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                        .foregroundStyle(.secondary)
                    TextField("BPM", value: Binding(get: { model.displayedBPM }, set: { model.bpm = $0 }), format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain).frame(width: 60)
                        .accessibilityLabel("Tempo in BPM").accessibilityIdentifier("tempo-field")
                }
                .background(TempoGestureView(onChange: { model.adjustTempo(by: $0) }))
                VStack(alignment: .leading, spacing: 5) {
                    Text("TIME").fixedSize().font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                        .foregroundStyle(.secondary)
                    Picker("Meter", selection: $model.beatsPerBar) {
                        ForEach(2...7, id: \.self) { Text("\($0)/4").tag($0) }
                    }.labelsHidden().controlSize(.small).frame(width: 62)
                        .onChange(of: model.beatsPerBar) { _, _ in model.scheduleEvaluation() }
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 32)
            OutputMonitorView(bands: model.spectrum, samples: model.outputSamples, isPlaying: model.isPlaying,
                performance: model.performance,
                resetDiagnostics: model.resetPerformanceDiagnostics,
                space: model.displayedReverbMix, onSpaceChange: { model.reverbMix = $0 },
                balance: model.masterBalance, onBalanceChange: model.setMasterBalance,
                equalizerResponses: model.equalizerResponses, equalizerBands: model.equalizerBands, onEqualizerChange: model.setEqualizerBand)
                .frame(minWidth: 120, idealWidth: 220, maxWidth: .infinity)
            VStack(spacing: 5) {
                HStack {
                    Text("MASTER")
                    Spacer()
                    Text(model.masterVolume == 0 ? "−∞ dB" : String(format: "%.0f dB", 20 * log10(model.masterVolume)))
                }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Slider(value: $model.masterVolume, in: 0...1)
                    .controlSize(.small).tint(.gray)
                    .accessibilityLabel("Master volume")
                    .accessibilityIdentifier("master-volume")
            }.frame(width: 80)
            HeaderXYPad(model: model).frame(minWidth: 90, idealWidth: 140, maxWidth: 160).frame(height: 40)
            Button { controlsPresented = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                    .frame(width: 32, height: 38)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).accessibilityLabel("Controls")
                .accessibilityIdentifier("editor-controls")
                .popover(isPresented: $controlsPresented, arrowEdge: .bottom) {
                    LiveControlsView(model: model, maximumTakeMinutes: $maximumTakeMinutes)
                        .frame(width: 780, height: 420)
                }
        }.frame(minWidth: 600, idealWidth: 820, maxWidth: 1100).frame(height: 40)
    }

    private func record() {
        if model.isRecording {
            Task { @MainActor in
                do { _ = try await model.stopRecording() }
                catch { model.hostDiagnostic = error.localizedDescription }
            }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "Take.wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try model.startRecording(to: destination, maximumDuration: .seconds(maximumTakeMinutes * 60)) }
        catch { model.hostDiagnostic = error.localizedDescription }
    }

}
