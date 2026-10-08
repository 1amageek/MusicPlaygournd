import SwiftUI
import MusicPlaygroundUI
import UniformTypeIdentifiers

struct NativeDeckView: View {
    @Bindable var audio: AudioWorkspace
    @Bindable var documents: DocumentWorkspace
    let index: Int
    @Binding var color: Color
    @Binding var maximumTakeMinutes: Int
    let load: (SourceDocument, Int) async -> Void
    @State private var openFile = false
    @State private var colorVisible = false
    @State private var fxVisible = false
    @State private var controlsVisible = false
    @State private var compressorVisible = false
    @State private var cueVisible = false
    @Environment(\.self) private var environment
    private var deck: AudioDeck { audio.deck(index) }
    private var peer: AudioDeck { audio.deck(1 - index) }
    private var name: String { index == 0 ? "A" : "B" }

    var body: some View {
        DeckPanel { header } controls: {
            HStack(spacing: 8) {
                DeckGainControl(value: Binding(get: { deck.gain }, set: { value in perform { try deck.setGain(value) } }), color: color, name: name,
                    valueLabel: deck.gain == 0 ? "−∞" : String(format: "%.0f dB", 20 * log10(deck.gain))).frame(width: 36)
                SpectrumEqualizerView(spectrum: deck.spectrum, isPlaying: deck.isPlaying, bands: deck.equalizer, responses: deck.responses,
                    onChange: { band, value in perform { try deck.setEqualizer(band, value) } }, compact: true, tint: color)
                    .frame(maxWidth: .infinity).frame(height: 82)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3)).accessibilityIdentifier("deck-\(name)-equalizer")
                FilterSpacePad(x: (deck.filter + 1) / 2, y: deck.reverb, tint: color, name: "Deck \(name)",
                    onFilterChange: { value in perform { try deck.setFilter(value * 2 - 1) } },
                    onSpaceChange: { value in perform { try deck.setReverb(value) } }).frame(width: 104, height: 82)
            }.frame(height: 92)
        } wave: {
            ZStack {
                LoopWaveView(peaks: deck.peaks, position: position, color: color)
                NativeScratchView(deck: deck, activate: { try await audio.activate() }, open: { compressorVisible = true })
            }.frame(height: 36).contentShape(Rectangle()).accessibilityIdentifier("deck-\(name)-wave")
                .popover(isPresented: $compressorVisible) {
                    WaveCompressorView(settings: audio.compressorSettings, snapshot: audio.compressorMeter,
                        onChange: { value in perform { try audio.setCompressor(value) } }, tint: color)
                        .frame(width: 460, height: 300).padding(12)
                }
        }
        .fileImporter(isPresented: $openFile, allowedContentTypes: [.swiftSource]) { result in
            switch result {
            case .failure(let error): deck.error = error.localizedDescription
            case .success(let url):
                Task {
                    await documents.openFile(url, deck: index)
                    if let document = documents.selectedDocument(in: index), document.url == url { await load(document, index) }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, urls.count == 1 else { return false }
            Task {
                await documents.openFile(url, deck: index)
                if let document = documents.selectedDocument(in: index), document.url == url { await load(document, index) }
            }
            return true
        }
    }
    private var position: Double {
        guard let beats = deck.loop?.beatCount, beats > 0 else { return 0 }
        return deck.beatPosition.truncatingRemainder(dividingBy: beats) / beats
    }
    private var header: some View {
        DeckTransportRow {
            Button { colorVisible = true } label: {
                Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 21, height: 24).background(color, in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Deck \(name) color")
                .popover(isPresented: $colorVisible) { DeckColorPalette(name: name, selection: Binding(get: { color }, set: saveColor)) }
        } load: {
            Menu {
                if let document = documents.selectedDocument(in: index) ?? documents.activeDocument {
                    Button("Load selected file") { Task { await load(document, index) } }
                }
                ForEach(documents.tabs(in: index).filter { $0.url.pathExtension == "swift" && !$0.isReadOnly && $0.name != "Package.swift" }) { document in
                    Button(document.name) { Task { await load(document, index) } }
                }
                Button("Open file…") { openFile = true }
                Button("Change Deck Color…") { colorVisible = true }
            } label: {
                Text(deck.documentID.flatMap { id in documents.documents.first { $0.id == id }?.name } ?? "Load…")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.frame(minWidth: 0, maxWidth: .infinity).layoutPriority(-1).accessibilityLabel("Deck \(name) load")
        } play: {
            TransportButton(symbol: deck.isPlaying ? "pause.fill" : "play.fill", label: "Deck \(name) play pause", value: deck.isPlaying ? "Playing" : "Paused", enabled: !deck.isPreparing && !audio.isStopping && deck.loop != nil) { Task { await performAsync { try await audio.toggle(index) } } }
                .accessibilityIdentifier("play-\(name)")
        } cue: {
            NativeCueButton(deck: deck, color: color, name: name, activate: { try await audio.activate() }).frame(width: 30, height: 30)
        } tempo: {
            TextField("BPM", value: Binding(get: { deck.bpm }, set: { value in perform { try deck.setBPM(value) } }), format: .number.precision(.fractionLength(0)))
                .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit().textFieldStyle(.plain).keyboardType(.decimalPad)
                .frame(width: 43).accessibilityLabel("Deck \(name) BPM")
        } tap: {
            smallButton("TAP", width: 32) { perform { try deck.tap() } }.accessibilityLabel("Deck \(name) tap tempo")
        } sync: {
            smallButton("SYNC", width: 38) { perform { try deck.synchronize(to: peer) } }.disabled(!peer.isPlaying || deck.loop == nil)
                .accessibilityLabel("Deck \(name) sync")
        } headphones: {
            Button {
                if audio.cueDeviceID == nil { cueVisible = true }
                else { perform { try audio.setCue(!audio.cueDecks.contains(index), deck: index) } }
            } label: {
                Image(systemName: "headphones").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(audio.cueDeviceID != nil && audio.cueDecks.contains(index) ? color : .white.opacity(0.9))
                    .frame(width: 28, height: 25).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Deck \(name) headphone cue")
                .popover(isPresented: $cueVisible) { NativeCueSettings(audio: audio) }
        } fx: {
            smallButton("FX", width: 28, active: deck.fx.mix > 0) { fxVisible = true }.accessibilityLabel("Deck \(name) FX").accessibilityValue(deck.fx.mix > 0 ? deck.fx.kind.rawValue : "Off")
                .popover(isPresented: $fxVisible) {
                    EffectView(settings: deck.fx, beats: deck.fxBeats,
                        onChange: { value in perform { try deck.setFX(value) } }, onBeatsChange: { value in perform { try deck.setFXBeats(value) } },
                        onReset: { perform { try deck.resetFX() } }, tint: color, name: name)
                }
        } controls: {
            Button { controlsVisible = true } label: {
                if deck.isPreparing { ProgressView().controlSize(.mini) }
                else { Image(systemName: "ellipsis").frame(width: 14, height: 24).contentShape(Rectangle()) }
            }.buttonStyle(.plain).accessibilityLabel("Deck \(name) controls")
                .popover(isPresented: $controlsVisible) {
                    NativeControlsView(audio: audio, documents: documents, index: index, maximumTakeMinutes: $maximumTakeMinutes)
                        .frame(idealWidth: 780)
                }
        }
    }
    private func smallButton(_ text: String, width: CGFloat, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(active ? color : .primary)
                .frame(width: width, height: 25).background(active ? color.opacity(0.22) : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.08))).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func perform(_ body: () throws -> Void) { do { try body() } catch { deck.error = error.localizedDescription } }
    private func performAsync(_ body: () async throws -> Void) async {
        do { try await body() } catch is CancellationError { } catch { deck.error = error.localizedDescription }
    }
    private func saveColor(_ value: Color) {
        let rgb = value.resolve(in: environment)
        UserDefaults.standard.set([Double(rgb.red), Double(rgb.green), Double(rgb.blue)], forKey: "deck.color." + name)
        color = value
    }
    static func restoreColor(_ name: String, fallback: Color) -> Color {
        guard let rgb = UserDefaults.standard.array(forKey: "deck.color." + name) as? [Double], rgb.count == 3,
              rgb.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return fallback }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}
