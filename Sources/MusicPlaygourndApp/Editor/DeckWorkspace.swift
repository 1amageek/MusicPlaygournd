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
    func refresh() { a.refresh(); b.refresh() }
    func loadSelected(_ deck: Int) {
        let model = deck == 0 ? a : b
        let alert = NSAlert()
        alert.messageText = "Load into Deck \(deck == 0 ? "A" : "B")"
        alert.informativeText = "Music type in \(model.activeDocument.name)"
        let name = NSTextField(string: model.loadedType)
        name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = name
        alert.addButton(withTitle: "Load")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try model.loadIntoDeck(model.activeDocument, type: name.stringValue) }
        catch { model.hostDiagnostic = error.localizedDescription }
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
        var failure: Error?
        do { try await a.shutdown() } catch { failure = error }
        do { try await b.shutdown() } catch { failure = failure ?? error }
        if let failure { throw failure }
    }
}
