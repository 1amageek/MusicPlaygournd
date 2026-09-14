import AppKit
import SwiftUI

/// Native press/release delivery avoids SwiftUI long-press cancellation gaps.
struct TransportCueButton: NSViewRepresentable {
    let cue: TransportCue?
    let color: Color
    let name: String

    func makeNSView(context: Context) -> CueButton { CueButton() }
    func updateNSView(_ view: CueButton, context: Context) {
        view.cue = cue
        view.tint = NSColor(color)
        view.pressed = cue?.isPressed == true
        view.isEnabled = cue != nil
        view.setAccessibilityLabel("Deck \(name) transport CUE")
        view.toolTip = "CUE: set while paused; return while playing; hold to preview. Shift: track start."
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: CueButton, coordinator: ()) { view.cue?.release() }

    final class CueButton: NSButton {
        var cue: TransportCue?
        var tint = NSColor.controlAccentColor
        var pressed = false
        private var observer: NSObjectProtocol?
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            isBordered = false
            title = "CUE"
            target = self
            action = #selector(activate)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                    object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.cue?.release() }
                    }
            } else { cue?.release() }
        }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            cue?.press(shift: event.modifierFlags.contains(.shift))
        }
        override func mouseUp(with event: NSEvent) { cue?.release() }
        @objc private func activate() {
            // Mouse tracking already owns its press; accessibility activation is a tap.
            guard cue?.isPressed != true else { return }
            cue?.press(shift: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            cue?.release()
        }
        override func draw(_ dirtyRect: NSRect) {
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            if pressed { tint.setFill(); circle.fill() }
            tint.withAlphaComponent(isEnabled ? 0.9 : 0.35).setStroke()
            circle.lineWidth = 1.3
            circle.stroke()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: pressed ? NSColor.black : tint]
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
    }
}
