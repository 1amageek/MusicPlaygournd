import AppKit
import MusicPlaygourndCore
import SwiftUI
import UniformTypeIdentifiers

struct DeckHeaderView: View {
    @Bindable var workspace: DeckWorkspace
    @State private var colorDeck = [false, false]
    @State private var compressorDeck = [false, false]
    @State private var scopeVisible = false
    @State private var controlsDeck = [false, false]
    @State private var maximumTakeMinutes = 10

    var body: some View {
        GeometryReader { geometry in
            let centerWidth = min(260, max(170, geometry.size.width * 0.22))
            HStack(spacing: 0) {
                deck(workspace.a, index: 0)
                Divider()
                master.frame(width: centerWidth)
                Divider()
                deck(workspace.b, index: 1)
            }
        }
        .frame(height: 208)
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
                Button { workspace.refreshCueDevices(); workspace.cueSettingsVisible = true } label: {
                    Image(systemName: "headphones").font(.system(size: 12))
                }.buttonStyle(.plain).accessibilityLabel("Headphone output settings")
                    .popover(isPresented: $workspace.cueSettingsVisible) { CueSettingsView(workspace: workspace) }
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
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button { colorDeck[index] = true } label: {
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 21, height: 24).background(color, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).accessibilityLabel("Deck \(name) color")
                    .popover(isPresented: $colorDeck[index]) {
                        DeckColorPalette(name: name, selection: Binding(
                            get: { index == 0 ? workspace.colorA : workspace.colorB },
                            set: { workspace.setColor($0, deck: index) }))
                    }
                Menu {
                    Button("Load selected file") { workspace.loadSelected(index) }
                    Button("Open file…") { workspace.selectedDeck = index; model.openDocument() }
                    Divider()
                    Button("Change Deck Color…") { colorDeck[index] = true }
                } label: {
                    Text(model.loadedDocument == nil ? "Load…" : (model.loadedType == "Session" ? (model.project?.name ?? model.loadedType) : model.loadedType))
                        .font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .help(model.loadedDocument?.fileURL?.path ?? "Drop a Swift Music file here")
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying || model.isPlaybackQueued ? "pause.fill" : "play.fill")
                        .font(.system(size: 13)).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.3)).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Deck \(name) play pause")
                    .accessibilityValue(model.isPlaybackQueued ? "Preparing playback" : (model.isPlaying ? "Playing" : "Paused"))
                TextField("BPM", value: Binding(get: { model.displayedBPM }, set: { model.bpm = $0 }), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                    .textFieldStyle(.plain).frame(width: 43).accessibilityLabel("Deck \(name) BPM")
                    .background(MultiFingerGestureView(onChange: { model.adjustTempo(by: $0 * 0.25) }))
                    .help("BPM — use two or three fingers to adjust tempo")
                Button { workspace.tap(index) } label: {
                    Text("TAP").font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 32, height: 25)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.08)))
                }.buttonStyle(.plain)
                    .accessibilityLabel("Deck \(name) tap tempo")
                Button { workspace.sync(index) } label: {
                    Text("SYNC").font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 38, height: 25)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.08)))
                }.buttonStyle(.plain)
                    .disabled(!(index == 0 ? workspace.b : workspace.a).isPlaying)
                Button { workspace.toggleCue(index) } label: {
                    Image(systemName: "headphones").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(workspace.cueDeviceID != nil && workspace.cueDecks.contains(index) ? color : .white.opacity(0.9))
                        .frame(width: 28, height: 25)
                        .background(workspace.cueDeviceID != nil && workspace.cueDecks.contains(index) ? color.opacity(0.22) : .white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.08)))
                }.buttonStyle(.plain).accessibilityLabel("Deck \(name) headphone cue")
                    .accessibilityValue(workspace.cueDeviceID != nil && workspace.cueDecks.contains(index) ? "On" : "Off")
                    .help("Preview this deck in headphones before the crossfader")
                Button { controlsDeck[index] = true } label: {
                    if model.isPreparing { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "ellipsis").frame(width: 14, height: 24) }
                }.buttonStyle(.plain).accessibilityLabel("Deck \(name) controls")
                    .popover(isPresented: $controlsDeck[index]) {
                        LiveControlsView(model: model, maximumTakeMinutes: $maximumTakeMinutes).frame(width: 780, height: 420)
                    }
            }.font(.system(size: 8, weight: .medium)).buttonStyle(.borderless).frame(height: 32)
            HStack(spacing: 8) {
                DeckGainControl(value: index == 0 ? $workspace.gainA : $workspace.gainB, color: color, name: name,
                                valueLabel: (index == 0 ? workspace.gainA : workspace.gainB) == 0 ? "−∞" : String(format: "%.0f dB", 20 * log10(index == 0 ? workspace.gainA : workspace.gainB)))
                    .frame(width: 36)
                SpectrumEqualizerView(spectrum: model.spectrum, isPlaying: model.isPlaying,
                    bands: model.equalizerBands, responses: model.equalizerResponses, onChange: model.setEqualizerBand,
                    compact: true, tint: color)
                    .frame(maxWidth: .infinity).frame(height: 82)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityIdentifier("deck-\(name)-equalizer")
                HeaderXYPad(model: model, bipolar: true, tint: color, name: "Deck \(name)")
                    .frame(width: 104, height: 82)
            }.frame(height: 92)
            Button { compressorDeck[index] = true } label: {
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
                .background(MultiFingerGestureView(reversesHorizontalMotion: true, onMotion: model.scratch, onEnd: model.endScratch, onRelease: model.releaseScratch))
                .help("Scratch with two or three fingers, even while paused. Drag right to rewind, left to advance. Up advances; down rewinds.")
                .popover(isPresented: $compressorDeck[index]) {
                    WaveCompressorView(settings: workspace.a.compressorSettings, snapshot: workspace.a.compressorMeter, onChange: workspace.a.setCompressor, tint: color)
                        .frame(width: 460, height: 300).padding(12)
                }
        }.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
                workspace.receiveDrop(providers, into: index)
            }
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
