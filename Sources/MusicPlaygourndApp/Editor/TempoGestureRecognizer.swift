import AppKit

/// Observes three-finger trackpad motion without consuming mouse or scroll events.
@MainActor
final class TempoGestureRecognizer {
    private var monitor: Any?
    private weak var touchView: NSView?
    private var previousTouchTypes: NSTouch.TouchTypeMask = []
    private var previousRestingTouches = false
    var onChange: ((Double) -> Void)?
    private var lastPoint: NSPoint?
    private var accumulated = NSPoint.zero
    private var horizontal = false

    func attach(to window: NSWindow?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let touchView {
            touchView.allowedTouchTypes = previousTouchTypes
            touchView.wantsRestingTouches = previousRestingTouches
        }
        touchView = nil
        reset()
        guard let window else { return }
        if let content = window.contentView {
            touchView = content
            previousTouchTypes = content.allowedTouchTypes
            previousRestingTouches = content.wantsRestingTouches
            content.allowedTouchTypes.insert(.indirect)
            content.wantsRestingTouches = true
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .gesture) { [weak self, weak window] event in
            MainActor.assumeIsolated {
                if let window, event.window === window { self?.update(event) }
            }
            return event
        }
    }

    func reset() {
        lastPoint = nil
        accumulated = .zero
        horizontal = false
    }

    private func update(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: nil)
        guard touches.count == 3 else { reset(); return }
        var point = NSPoint.zero
        for touch in touches {
            point.x += touch.normalizedPosition.x * touch.deviceSize.width / 3
            point.y += touch.normalizedPosition.y * touch.deviceSize.height / 3
        }
        defer { lastPoint = point }
        guard let previous = lastPoint else { return }
        let dx = point.x - previous.x
        accumulated.x += dx
        accumulated.y += point.y - previous.y
        if abs(accumulated.y) >= 8 && abs(accumulated.y) > abs(accumulated.x) * 1.2 {
            reset()
            return
        }
        if horizontal {
            onChange?(Double(dx) * 0.25)
        } else if abs(accumulated.x) >= 8 && abs(accumulated.x) > abs(accumulated.y) * 1.2 {
            horizontal = true
            onChange?(Double(accumulated.x) * 0.25)
        }
    }
}
