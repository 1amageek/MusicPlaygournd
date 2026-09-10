import AppKit
import SwiftUI

/// Keeps edge-mode capture tied to the workspace's native view lifetime.
struct TrackpadEdgeView: NSViewRepresentable {
    @Binding var enabled: Bool
    let workspace: DeckWorkspace

    func makeNSView(context: Context) -> CaptureView { CaptureView() }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.controller.onModeChange = { enabled = $0 }
        view.controller.onError = { workspace.active.hostDiagnostic = $0 }
        view.controller.onCrossfade = { workspace.crossfade = $0 }
        view.controller.onScratch = { region, distance, duration in
            (region == .a ? workspace.a : workspace.b).scratch(distance: distance, duration: duration)
        }
        view.controller.onRelease = { ($0 == .a ? workspace.a : workspace.b).releaseScratch() }
        view.controller.onStopScratch = { ($0 == .a ? workspace.a : workspace.b).endScratch() }
        view.controller.onCancel = { workspace.a.endScratch(); workspace.b.endScratch() }
        view.requested = enabled
    }

    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.controller.stop() }

    final class CaptureView: NSView {
        let controller = TrackpadEdgeController()
        var requested = false {
            didSet {
                guard requested != oldValue else { return }
                // Capture after SwiftUI finishes updating its bindings.
                Task { @MainActor [weak self] in self?.synchronize() }
            }
        }
        private func synchronize() {
            if requested, let window { controller.start(in: window) }
            else { controller.stop() }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { controller.stop() }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
