import AppKit
import SwiftUI

/// Limits tempo gestures to the BPM label and field without intercepting clicks.
struct TempoGestureView: NSViewRepresentable {
    var onChange: (Double) -> Void

    func makeNSView(context: Context) -> RegionView { RegionView() }

    func updateNSView(_ view: RegionView, context: Context) {
        view.gesture.onChange = onChange
    }

    static func dismantleNSView(_ view: RegionView, coordinator: ()) {
        view.gesture.attach(to: nil)
        view.gesture.onChange = nil
    }

    final class RegionView: NSView {
        let gesture = TempoGestureRecognizer()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            gesture.attach(to: window == nil ? nil : self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
