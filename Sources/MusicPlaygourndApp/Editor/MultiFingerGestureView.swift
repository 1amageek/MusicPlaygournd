import AppKit
import SwiftUI

/// Registers a bounded control region without intercepting clicks.
struct MultiFingerGestureView: NSViewRepresentable {
    var onMotion: ((Double, Double) -> Void)?
    var onEnd: (() -> Void)?
    var onChange: ((Double) -> Void)?

    func makeNSView(context: Context) -> RegionView { RegionView() }

    func updateNSView(_ view: RegionView, context: Context) {
        view.gesture.onChange = onChange
        view.gesture.onMotion = onMotion
        view.gesture.onEnd = onEnd
    }

    static func dismantleNSView(_ view: RegionView, coordinator: ()) {
        view.gesture.attach(to: nil)
        view.gesture.onChange = nil
        view.gesture.onMotion = nil
        view.gesture.onEnd = nil
    }

    final class RegionView: NSView {
        let gesture = MultiFingerGestureRecognizer()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            gesture.attach(to: window == nil ? nil : self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
