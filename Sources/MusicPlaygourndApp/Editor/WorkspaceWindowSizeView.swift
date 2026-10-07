import AppKit
import SwiftUI

/// Restores the editing size when entering from the compact welcome screen.
struct WorkspaceWindowSizeView: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> SizingView {
        let view = SizingView()
        view.onWindowChange = onWindowChange
        return view
    }
    func updateNSView(_ view: SizingView, context: Context) {
        view.onWindowChange = onWindowChange
    }

    final class SizingView: NSView {
        var onWindowChange: (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Run after SwiftUI replaces the welcome screen's fixed constraints.
            Task { @MainActor [weak self] in
                guard let self else { return }
                onWindowChange(window)
                guard let window else { return }
                window.setContentSize(NSSize(width: 1280, height: 800))
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
