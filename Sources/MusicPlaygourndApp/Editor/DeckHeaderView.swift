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
        GeometryReader { geometry in
            let centerWidth = min(280, max(190, geometry.size.width * 0.24))
            HStack(spacing: 0) {
                deck(workspace.a, index: 0)
                Divider()
                master.frame(width: centerWidth)
                Divider()
                deck(workspace.b, index: 1)
            }
        }
        .frame(height: 164)
        .background(LinearGradient(colors: [Color(red: 0.055, green: 0.07, blue: 0.08), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
    }

    private var master: some View {
        VStack(spacing: 7) {
            Button { scopeVisible = true } label: {
                DeckVectorscopeView(samplesA: workspace.a.deckSamples, samplesB: workspace.b.deckSamples,
                                    colorA: workspace.colorA, colorB: workspace.colorB)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.13)))
            }.buttonStyle(.plain).accessibilityLabel("A and B vectorscopes")
                .popover(isPresented: $scopeVisible) {
                    VectorscopeControlView(samples: workspace.a.deckSamples, balance: workspace.balance,
                        space: workspace.space, onBalanceChange: { workspace.balance = $0 }, onSpaceChange: { workspace.space = $0 },
                        samplesB: workspace.b.deckSamples, colorA: workspace.colorA, colorB: workspace.colorB)
                        .frame(width: 440, height: 360).padding(12)
                }
            HStack(spacing: 10) {
                Text("A").foregroundStyle(workspace.colorA)
                GeometryReader { geometry in
                    let travel = max(1, geometry.size.width - 12)
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [workspace.colorA, workspace.colorB], startPoint: .leading, endPoint: .trailing)).frame(height: 5)
                        Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 14).offset(x: geometry.size.width / 2)
                        RoundedRectangle(cornerRadius: 3).fill(.white.gradient).frame(width: 12, height: 24)
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1).offset(x: workspace.crossfade * travel)
                    }.frame(height: 28).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { workspace.crossfade = min(1, max(0, ($0.location.x - 6) / travel)) })
                        .onTapGesture(count: 2) { workspace.crossfade = 0.5 }
                }.frame(height: 28)
                    .accessibilityElement().accessibilityLabel("A B crossfader")
                    .accessibilityValue(String(format: "%.0f percent B", workspace.crossfade * 100))
                    .accessibilityAdjustableAction { direction in
                        workspace.crossfade = min(1, max(0, workspace.crossfade + (direction == .increment ? 0.05 : -0.05)))
                    }.accessibilityAction(named: "Center") { workspace.crossfade = 0.5 }
                    .accessibilityIdentifier("crossfader")
                Text("B").foregroundStyle(workspace.colorB)
            }.font(.system(size: 15, weight: .bold))
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $workspace.masterVolume, in: 0...1).controlSize(.mini).tint(.gray)
                    .background(MultiFingerGestureView(onChange: { workspace.masterVolume = min(1, max(0, workspace.masterVolume + $0 * 0.01)) }))
                    .frame(maxWidth: .infinity).accessibilityLabel("Master volume")
                Button(action: record) { Image(systemName: workspace.a.isRecording ? "stop.circle.fill" : "record.circle") }
                    .buttonStyle(.plain).accessibilityLabel("Record master")
                    .disabled(!workspace.a.isPlaying && !workspace.b.isPlaying && !workspace.a.isRecording)
            }
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func deck(_ model: SessionModel, index: Int) -> some View {
        let color = index == 0 ? workspace.colorA : workspace.colorB
        let name = index == 0 ? "A" : "B"
        let duration = model.loop?.beatCount ?? 0
        let position = duration > 0 ? model.beatPosition.truncatingRemainder(dividingBy: duration) / duration : 0
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
                    let values = model.loopPeaks
                    guard !values.isEmpty, size.width >= 1, size.height > 0 else { return }
                    var wave = Path()
                    for x in 0..<max(1, Int(size.width)) {
                        let peak = Self.waveformPeak(values, at: position + Double(x) / size.width - 0.5)
                        let height = min(1, CGFloat(peak) * 2) * size.height * 0.5
                        wave.move(to: CGPoint(x: CGFloat(x), y: size.height / 2 - height))
                        wave.addLine(to: CGPoint(x: CGFloat(x), y: size.height / 2 + height))
                    }
                    context.stroke(wave, with: .linearGradient(Gradient(colors: [color.opacity(0.5), color, color.opacity(0.5)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)), lineWidth: 1)
                    let x = size.width / 2
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white))
                }.frame(height: 36).contentShape(Rectangle())
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

    static func waveformPeak(_ peaks: [Float], at phase: Double) -> Float {
        guard !peaks.isEmpty, phase.isFinite else { return 0 }
        let offset = (phase - floor(phase)) * Double(peaks.count)
        let index = min(peaks.count - 1, Int(offset))
        let fraction = Float(offset - Double(index))
        return peaks[index] + (peaks[(index + 1) % peaks.count] - peaks[index]) * fraction
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
