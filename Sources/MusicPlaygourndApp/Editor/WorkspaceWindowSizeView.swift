import AppKit
import SwiftUI

/// Restores the editing size when entering from the compact welcome screen.
struct WorkspaceWindowSizeView: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) {}

    final class SizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // Run after SwiftUI replaces the welcome screen's fixed constraints.
            Task { @MainActor [weak self] in
                guard let window = self?.window else { return }
                window.setContentSize(NSSize(width: 1160, height: 760))
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
