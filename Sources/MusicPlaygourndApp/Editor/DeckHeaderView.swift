import AppKit
import MusicPlaygourndCore
import SwiftUI
import UniformTypeIdentifiers

struct DeckHeaderView: View {
    @Bindable var workspace: DeckWorkspace
    @State private var colorDeck: Int?
    @State private var eqDeck: Int?
    @State private var compressorDeck: Int?
    @State private var scopeVisible = false
    @State private var controlsDeck: Int?
    @State private var maximumTakeMinutes = 10

    var body: some View {
        HStack(spacing: 16) {
            deck(workspace.a, index: 0)
            Divider()
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Text("MASTER").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    Slider(value: $workspace.masterVolume, in: 0...1).controlSize(.mini).tint(.gray)
                        .accessibilityLabel("Master volume")
                    Button(action: record) { Image(systemName: workspace.a.isRecording ? "stop.circle" : "record.circle") }
                        .buttonStyle(.plain).accessibilityLabel("Record master")
                        .disabled(!workspace.a.isPlaying && !workspace.b.isPlaying && !workspace.a.isRecording)
                }
                Button { scopeVisible = true } label: {
                    VectorscopeView(samples: workspace.a.outputSamples)
                        .frame(height: 70).frame(maxWidth: .infinity)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityLabel("Master vectorscope")
                    .popover(isPresented: $scopeVisible) {
                        VectorscopeControlView(samples: workspace.a.outputSamples, balance: workspace.balance,
                            space: workspace.space, onBalanceChange: { workspace.balance = $0 }, onSpaceChange: { workspace.space = $0 })
                            .frame(width: 440, height: 360).padding(12)
                    }
                HStack {
                    Text("A").foregroundStyle(workspace.colorA)
                    Slider(value: $workspace.crossfade, in: 0...1).tint(.gray)
                        .accessibilityLabel("A B crossfader").accessibilityIdentifier("crossfader")
                    Text("B").foregroundStyle(workspace.colorB)
                }.font(.system(size: 11, weight: .semibold))
            }.frame(width: 210)
            Divider()
            deck(workspace.b, index: 1)
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(height: 140)
            .background(.black.opacity(0.18))
    }

    private func deck(_ model: SessionModel, index: Int) -> some View {
        let color = index == 0 ? workspace.colorA : workspace.colorB
        let name = index == 0 ? "A" : "B"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("Blue") { workspace.setColor(.blue, deck: index) }
                    Button("Mint") { workspace.setColor(.mint, deck: index) }
                    Button("Violet") { workspace.setColor(.purple, deck: index) }
                    Button("Amber") { workspace.setColor(Color(red: 0.86, green: 0.62, blue: 0.25), deck: index) }
                    Button("Rose") { workspace.setColor(.pink, deck: index) }
                    Divider()
                    Button("Custom…") { colorDeck = index }
                } label: {
                    Text(name).fontWeight(.bold).foregroundStyle(color)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Deck \(name) color")
                .popover(isPresented: Binding(get: { colorDeck == index }, set: { if !$0 { colorDeck = nil } })) {
                    ColorPicker("Deck \(name)", selection: Binding(get: { color }, set: { workspace.setColor($0, deck: index) }), supportsOpacity: false)
                        .padding(16).frame(width: 220)
                }
                Menu {
                    Button("Load selected file…") { workspace.loadSelected(index) }
                    Button("Open file…") { workspace.selectedDeck = index; model.openDocument() }
                } label: {
                    Text(model.loadedDocument?.name ?? "Load a Music file").lineLimit(1)
                }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { controlsDeck = index } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel("Deck \(name) controls")
                    .popover(isPresented: Binding(get: { controlsDeck == index }, set: { if !$0 { controlsDeck = nil } })) {
                        LiveControlsView(model: model, maximumTakeMinutes: $maximumTakeMinutes).frame(width: 780, height: 420)
                    }
            }.font(.system(size: 11))
            HStack(spacing: 8) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17))
                        .frame(width: 34, height: 34).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel("Deck \(name) play pause")
                TextField("BPM", value: Binding(get: { model.displayedBPM }, set: { model.bpm = $0 }), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 22, design: .monospaced)).textFieldStyle(.plain).frame(width: 49)
                    .accessibilityLabel("Deck \(name) BPM")
                    .background(MultiFingerGestureView(onChange: { model.adjustTempo(by: $0 * 0.25) }))
                Button("TAP") { workspace.tap(index) }.accessibilityLabel("Deck \(name) tap tempo")
                Button("Sync") { workspace.sync(index) }.disabled(!(index == 0 ? workspace.b : workspace.a).isPlaying)
                Button("EQ") { eqDeck = index }
                    .popover(isPresented: Binding(get: { eqDeck == index }, set: { if !$0 { eqDeck = nil } })) {
                        SpectrumEqualizerView(spectrum: model.spectrum, isPlaying: model.isPlaying,
                            bands: model.equalizerBands, responses: model.equalizerResponses, onChange: model.setEqualizerBand)
                            .frame(width: 440, height: 260).padding(12)
                    }
            }.controlSize(.small)
            Button { compressorDeck = index } label: {
              Canvas { context, size in
                let values = model.deckSamples
                let frames = values.count / 2
                guard frames > 0 else { return }
                var wave = Path()
                let count = max(1, Int(size.width))
                for x in 0..<count {
                    let first = x * frames / count
                    let last = min(frames, (x + 1) * frames / count)
                    var peak: Float = 0
                    for frame in first..<last { peak = max(peak, abs(values[frame * 2]), abs(values[frame * 2 + 1])) }
                    let height = min(1, CGFloat(peak) * 4) * size.height * 0.5
                    wave.move(to: CGPoint(x: CGFloat(x), y: size.height / 2 - height))
                    wave.addLine(to: CGPoint(x: CGFloat(x), y: size.height / 2 + height))
                }
                context.stroke(wave, with: .color(color), lineWidth: 1)
              }.frame(height: 25).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Deck \(name) waveform, open master compressor")
                .background(MultiFingerGestureView(onMotion: model.scratch, onEnd: model.endScratch))
                .help("Scratch with two or three fingers, even while paused. Right/up forward, left/down reverse.")
                .popover(isPresented: Binding(get: { compressorDeck == index }, set: { if !$0 { compressorDeck = nil } })) {
                    WaveCompressorView(settings: workspace.a.compressorSettings, snapshot: workspace.a.compressorMeter, onChange: workspace.a.setCompressor)
                        .frame(width: 460, height: 300).padding(12)
                }
            HStack {
                Text(!model.diagnostic.isEmpty || !model.hostDiagnostic.isEmpty ? "Issue · open Logs" : model.isPreparing ? "Preparing…" : String(format: "BEAT %.1f", model.beatPosition))
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("GAIN").font(.system(size: 8)).foregroundStyle(.secondary)
                Slider(value: index == 0 ? $workspace.gainA : $workspace.gainB, in: 0...1)
                    .controlSize(.mini).tint(color).frame(width: 85).accessibilityLabel("Deck \(name) gain")
            }
        }.frame(maxWidth: .infinity)
    }

    private func record() {
        let model = workspace.a
        if model.isRecording {
            Task { do { _ = try await model.stopRecording() } catch { model.hostDiagnostic = error.localizedDescription } }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "Mix.wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.startRecording(to: url, maximumDuration: .seconds(maximumTakeMinutes * 60)) }
        catch { model.hostDiagnostic = error.localizedDescription }
    }
}
