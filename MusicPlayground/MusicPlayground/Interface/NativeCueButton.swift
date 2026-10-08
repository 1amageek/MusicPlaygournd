import SwiftUI
import UIKit

struct NativeCueButton: UIViewRepresentable {
    let deck: AudioDeck
    let color: Color
    let name: String
    let activate: @MainActor () async throws -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.addTarget(context.coordinator, action: #selector(Coordinator.down), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.up), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.layer.cornerRadius = 4; button.titleLabel?.font = .systemFont(ofSize: 9, weight: .bold)
        button.setTitle("CUE", for: .normal); button.accessibilityLabel = "Deck \(name) transport CUE"
        button.accessibilityIdentifier = "cue-\(name)"
        updateUIView(button, context: context); return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = deck.loop != nil && !deck.isPreparing
        let active = deck.cue.isPressed
        button.setTitleColor(active ? .black : UIColor(color), for: .normal)
        button.backgroundColor = active ? UIColor(color) : .white.withAlphaComponent(0.09)
        button.accessibilityValue = deck.cue.isPreviewing ? "Previewing" : "Cue"
    }
    static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) { coordinator.up() }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeCueButton
        private var held = false
        private var task: Task<Void, Never>?
        init(_ parent: NativeCueButton) { self.parent = parent }
        @objc func down() {
            guard !held else { return }; held = true
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await parent.activate(); try Task.checkCancellation()
                    guard held else { return }; parent.deck.cue.press()
                } catch is CancellationError { }
                catch { parent.deck.error = error.localizedDescription }
            }
        }
        @objc func up() { held = false; task?.cancel(); task = nil; parent.deck.cue.release() }
    }
}
