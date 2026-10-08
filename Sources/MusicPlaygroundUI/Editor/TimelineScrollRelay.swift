import SwiftUI
#if os(macOS)
import AppKit
struct TimelineScrollRelay: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) { view.onScroll = onScroll }

    @MainActor final class WheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 21))
        }
    }
}
#else
struct TimelineScrollRelay: View {
    let onScroll: (CGFloat) -> Void
    @State private var previous: CGFloat = 0
    var body: some View {
        Color.clear.contentShape(Rectangle()).gesture(DragGesture().onChanged { event in
            onScroll(event.translation.height - previous); previous = event.translation.height
        }.onEnded { _ in previous = 0 })
    }
}
#endif
