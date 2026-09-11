import AppKit
import MusicPlaygourndCore
import Observation
import SwiftUI

/// Composes shared source editing, two independent performers and one output.
@MainActor @Observable
final class DeckWorkspace {
    let a: SessionModel
    let b: SessionModel
    let output: AudioOutput?
    private let documents = SessionDocumentStore()
    var cueSettingsVisible = false
    private(set) var cueDeviceID: UInt32?
    private(set) var cueDecks: Set<Int> = []
    var cueDevices: [CueOutputDevice] = []
    var audioDevices: [CueOutputDevice] = []
    private(set) var mainDeviceID: UInt32?
    func selectMainDevice(_ id: UInt32?) {
        guard let id else { return }
        do {
            guard let output else { throw PlaybackError.audioSetupFailed("Audio output is unavailable.") }
            try output.selectMainOutput(id)
            cueError = nil
        } catch { cueError = error.localizedDescription }
        refreshCueDevices()
    }
    var cueError: String?
    private var lastCueCheck = Date.distantPast
    var cueMix = 0.0 {
        didSet { do { try output?.setCueMix(Float(cueMix)) } catch { cueMix = oldValue; cueError = error.localizedDescription } }
    }
    var cueLevel = 0.5 {
        didSet { do { try output?.setCueLevel(Float(cueLevel)) } catch { cueLevel = oldValue; cueError = error.localizedDescription } }
    }
    func refreshCueDevices() {
        do {
            guard let output else { throw PlaybackError.audioSetupFailed("Audio output is unavailable.") }
            audioDevices = try CueOutputDevice.available()
            mainDeviceID = try output.mainOutputDeviceID()
            try output.validateCueDevice()
            cueDevices = try output.availableCueDevices()
            cueDeviceID = output.cueDeviceID
        } catch { cueDeviceID = output?.cueDeviceID; cueError = error.localizedDescription }
    }
    func selectCueDevice(_ id: UInt32?) {
        do {
            guard let output else { throw PlaybackError.audioSetupFailed("Audio output is unavailable.") }
            try output.selectCueDevice(id)
            cueError = nil
        } catch { cueError = error.localizedDescription }
        cueDeviceID = output?.cueDeviceID
    }
    func toggleCue(_ deck: Int) {
        guard cueDeviceID != nil else { refreshCueDevices(); cueSettingsVisible = true; return }
        do {
            try output?.setCue(!cueDecks.contains(deck), deck: deck)
            cueDecks = output?.cueDecks ?? []
            cueError = nil
        } catch { cueError = error.localizedDescription; cueSettingsVisible = true }
    }
    var hasPlaybackContent: Bool {
        [a, b].contains { $0.hasOpenDocument || $0.loadedDocument != nil || $0.isPlaying || $0.isPlaybackQueued }
    }

    func toggleAllPlayback() {
        let stop = a.isPlaying || a.isPlaybackQueued || b.isPlaying || b.isPlaybackQueued
        for model in [a, b] {
            if !stop || model.isPlaying || model.isPlaybackQueued { model.togglePlayback() }
        }
    }

    var selectedDeck = 0
    var active: SessionModel { selectedDeck == 0 ? a : b }
    var crossfade = 0.5 {
        didSet {
            do { try output?.setCrossfade(Float(crossfade)) }
            catch { crossfade = oldValue; active.hostDiagnostic = error.localizedDescription }
        }
    }
    var masterVolume: Double {
        get { a.masterVolume }
        set { a.masterVolume = newValue }
    }
    var balance: Float = 0 { didSet { do { try output?.setBalance(balance) } catch { balance = oldValue; active.hostDiagnostic = error.localizedDescription } } }
    var space = 0.0 { didSet { do { try output?.setReverb(mix: Float(space)) } catch { space = oldValue; active.hostDiagnostic = error.localizedDescription } } }
    var gainA = 1.0 { didSet { do { try a.setDeckGain(gainA) } catch { gainA = oldValue; a.hostDiagnostic = error.localizedDescription } } }
    var gainB = 1.0 { didSet { do { try b.setDeckGain(gainB) } catch { gainB = oldValue; b.hostDiagnostic = error.localizedDescription } } }
    var colorA: Color
    var colorB: Color
    private var tapsA = TapTempo()
    private var tapsB = TapTempo()

    init() {
        colorA = Self.restoreColor("A", fallback: .blue)
        colorB = Self.restoreColor("B", fallback: Color(red: 0.86, green: 0.62, blue: 0.25))
        let graph: AudioOutput?
        var setupError = ""
        do { graph = try AudioOutput() }
        catch { graph = nil; setupError = error.localizedDescription }
        output = graph
        a = SessionModel(output: graph, deckID: "A", documents: documents, audioEnabled: graph != nil)
        b = SessionModel(output: graph, deckID: "B", documents: documents, audioEnabled: graph != nil)
        do { try graph?.setCrossfade(0.5) }
        catch { setupError = error.localizedDescription }
        if !setupError.isEmpty { a.hostDiagnostic = "Two-deck output failed: " + setupError }
        documents.manifestDidSave = { [weak self] sender, root in
            guard let self else { return }
            let peer = sender === self.a ? self.b : self.a
            if peer.project?.root == root { peer.openProject(at: root, resolveDependencies: true) }
        }
        documents.membershipDidChange = { [weak self] in
            guard let self else { return }
            let retained = self.a.documents + self.b.documents + [self.a.loadedDocument, self.b.loadedDocument].compactMap { $0 }
            self.documents.retain(Set(retained.map(\.id)))
        }
        documents.sourceDidChange = { [weak self] document in
            self?.a.sharedSourceChanged(document)
            self?.b.sharedSourceChanged(document)
        }
    }

    func tap(_ deck: Int) {
        let bpm = deck == 0 ? tapsA.tap() : tapsB.tap()
        if let bpm { (deck == 0 ? a : b).bpm = bpm }
    }
    func sync(_ deck: Int) {
        let target = deck == 0 ? a : b
        do { try target.synchronize(to: deck == 0 ? b : a) }
        catch { target.hostDiagnostic = error.localizedDescription }
    }
    func setColor(_ color: Color, deck: Int) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent], forKey: "deck.color.\(deck == 0 ? "A" : "B")")
        if deck == 0 { colorA = color } else { colorB = color }
    }
    private static func restoreColor(_ name: String, fallback: Color) -> Color {
        guard let values = UserDefaults.standard.array(forKey: "deck.color.\(name)") as? [Double],
              values.count == 3, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return fallback }
        return Color(red: values[0], green: values[1], blue: values[2])
    }
    func refresh() {
        let master = output?.outputMeter()
        a.refresh(masterCapture: master); b.refresh(masterCapture: master)
        if cueDeviceID != nil && Date().timeIntervalSince(lastCueCheck) >= 1 {
            lastCueCheck = Date()
            refreshCueDevices()
        }
    }
    private var isClosing = false
    private var loadTasks: [Int: Task<Void, Never>] = [:]
    private(set) var discovering: Set<Int> = []

    func receiveDrop(_ providers: [NSItemProvider], into deck: Int) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.canLoadObject(ofClass: NSURL.self) else { return false }
        provider.loadObject(ofClass: NSURL.self) { [weak self] object, error in
            let url = object as? URL
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, !self.isClosing else { return }
                guard let url, url.isFileURL, url.pathExtension == "swift" else {
                    (deck == 0 ? self.a : self.b).hostDiagnostic = message ?? "Drop one local Swift Music file onto this deck."
                    return
                }
                self.loadFile(url, into: deck)
            }
        }
        return true
    }

    func loadSelected(_ deck: Int) {
        let model = deck == 0 ? a : b
        load(model.activeDocument, into: deck)
    }

    func loadFile(_ url: URL, into deck: Int) {
        let model = deck == 0 ? a : b
        do {
            try model.openDocument(at: url)
            selectedDeck = deck
            load(model.activeDocument, into: deck)
        } catch { model.hostDiagnostic = error.localizedDescription }
    }

    func load(_ document: SessionDocument, into deck: Int) {
        loadTasks[deck]?.cancel()
        let model = deck == 0 ? a : b
        let source = document.source
        discovering.insert(deck)
        loadTasks[deck] = Task { [weak self] in
            do {
                let names = try await model.musicEntries(in: document)
                try Task.checkCancellation()
                guard let self else { return }
                guard document.source == source else {
                    throw EvaluationError.invalidSource("Source changed while finding Music entries. Load it again.")
                }
                guard let first = names.first else { throw EvaluationError.invalidSource("This file contains no Music entry.") }
                var entry = first
                if names.count > 1 {
                    let alert = NSAlert()
                    alert.messageText = "Load into Deck \(deck == 0 ? "A" : "B")"
                    alert.informativeText = "Choose a Music entry in \(document.name)."
                    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
                    picker.addItems(withTitles: names)
                    alert.accessoryView = picker
                    alert.addButton(withTitle: "Load")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { self.discovering.remove(deck); return }
                    entry = names[picker.indexOfSelectedItem]
                }
                if let url = document.fileURL { try model.openDocument(at: url) }
                try model.loadIntoDeck(document, type: entry)
                self.discovering.remove(deck)
            } catch is CancellationError {
                // A superseding request owns the deck's loading indicator.
            } catch {
                self?.discovering.remove(deck)
                model.hostDiagnostic = error.localizedDescription
            }
        }
    }
    func confirmAllDocuments() -> Bool {
        var seen: Set<UUID> = []
        for model in [a, b] {
            if !model.confirmAllDocuments(decision: { document in
                if !seen.insert(document.id).inserted { return .discard }
                return model.closeDecision(for: document)
            }) { return false }
        }
        return true
    }
    func shutdown() async throws {
        isClosing = true
        try output?.selectCueDevice(nil)
        for task in loadTasks.values { task.cancel() }
        for task in loadTasks.values { await task.value }
        loadTasks.removeAll()
        var failure: Error?
        do { try await a.shutdown() } catch { failure = error }
        do { try await b.shutdown() } catch { failure = failure ?? error }
        if let failure { throw failure }
    }
}
