import SwiftUI
import UIKit

struct NativeScratchView: UIViewRepresentable {
    let deck: AudioDeck
    let activate: @MainActor () async throws -> Void
    let open: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 3
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: pan); view.addGestureRecognizer(pan); view.addGestureRecognizer(tap)
        view.isAccessibilityElement = true; view.accessibilityLabel = "Waveform, drag to scratch; double tap to open master compressor"
        view.accessibilityTraits = .button
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Scratch forward", target: context.coordinator, selector: #selector(Coordinator.accessibleForward)),
            UIAccessibilityCustomAction(name: "Scratch backward", target: context.coordinator, selector: #selector(Coordinator.accessibleBackward)),
            UIAccessibilityCustomAction(name: "Open master compressor", target: context.coordinator, selector: #selector(Coordinator.accessibleOpen))]
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self; view.accessibilityValue = "\(deck.peaks.count) PCM peak bins" }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.cancel() }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeScratchView
        private var task: Task<Void, Never>?
        private var held = false
        private var ready = false
        private var previous = CGPoint.zero
        private var pending = CGPoint.zero
        private var time = 0.0
        init(_ parent: NativeScratchView) { self.parent = parent }
        @objc func tap() { parent.open() }
        @objc func accessibleOpen() -> Bool { parent.open(); return true }
        @objc func accessibleForward() -> Bool { accessibleScratch(0.15) }
        @objc func accessibleBackward() -> Bool { accessibleScratch(-0.15) }
        private func accessibleScratch(_ seconds: Double) -> Bool {
            guard parent.deck.loop != nil, !held else { return false }
            task?.cancel()
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await parent.activate(); try Task.checkCancellation()
                    try parent.deck.scratch(seconds: seconds, duration: 0.1)
                    parent.deck.releaseScratch()
                } catch is CancellationError { }
                catch { parent.deck.error = error.localizedDescription }
            }
            return true
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard parent.deck.loop != nil else { return }
                held = true; ready = false; previous = .zero; pending = .zero; time = ProcessInfo.processInfo.systemUptime
                task = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await parent.activate(); try Task.checkCancellation()
                        guard held else { return }; ready = true; move()
                    } catch is CancellationError { }
                    catch { parent.deck.error = error.localizedDescription }
                }
            case .changed: pending = gesture.translation(in: gesture.view); if held && ready { move() }
            case .ended:
                pending = gesture.translation(in: gesture.view); if held && ready { move(); parent.deck.releaseScratch() }
                held = false; ready = false; task?.cancel(); task = nil
            case .cancelled, .failed: cancel()
            default: break
            }
        }
        private func move() {
            let now = ProcessInfo.processInfo.systemUptime, dx = pending.x - previous.x, dy = pending.y - previous.y
            guard dx != 0 || dy != 0 else { return }
            do { try parent.deck.scratch(seconds: Double(-dx - dy) * 0.005, duration: max(0.001, now - time)) }
            catch { parent.deck.error = error.localizedDescription; cancel() }
            previous = pending; time = now
        }
        func cancel() { held = false; ready = false; task?.cancel(); task = nil; parent.deck.endScratch() }
    }
}
