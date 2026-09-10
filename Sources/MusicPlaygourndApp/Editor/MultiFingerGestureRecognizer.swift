import AppKit

/// Observes region-limited two/three-finger motion without consuming mouse or scroll events.
@MainActor
final class MultiFingerGestureRecognizer {
    private weak var region: NSView?
    private var monitor: Any?
    private var windowObserver: NSObjectProtocol?
    private weak var touchView: NSView?
    var reversesHorizontalMotion = false
    var onChange: ((Double) -> Void)?
    var onMotion: ((Double, Double) -> Void)?
    var onEnd: (() -> Void)?
    var onRelease: (() -> Void)?
    private var coasting = false
    private var firstTimestamp: Double?
    private var lastTimestamp: Double?
    private var lastPoint: NSPoint?
    private var accumulated = NSPoint.zero
    private var lastTouchCount: Int?
    private var horizontal = false
    private var tracking = false

    func attach(to view: NSView?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let touchView { TrackpadTouchDelivery.release(touchView) }
        touchView = nil
        reset()
        region = view
        guard let window = view?.window else { return }
        if let content = window.contentView {
            touchView = content
            TrackpadTouchDelivery.acquire(content)
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .gesture) { [weak self, weak window] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !TrackpadEdgeController.isActive else { self.reset(); return }
                guard let window, self.contains(window.mouseLocationOutsideOfEventStream, in: event.window) else {
                    self.reset()
                    return
                }
                self.update(event)
            }
            return event
        }
    }

    func contains(_ location: NSPoint, in window: NSWindow?) -> Bool {
        guard let region, let window, region.window === window,
              !region.isHiddenOrHasHiddenAncestor else { return false }
        let point = region.convert(location, from: nil)
        return region.bounds.contains(point) && region.visibleRect.contains(point)
    }

    func reset(releasing: Bool = false) {
        let wasTracking = tracking
        let wasCoasting = coasting
        coasting = false
        firstTimestamp = nil
        lastTimestamp = nil
        lastPoint = nil
        lastTouchCount = nil
        accumulated = .zero
        tracking = false
        horizontal = false
        if releasing && wasTracking, let onRelease {
            coasting = true
            onRelease()
        } else if wasTracking || wasCoasting { onEnd?() }
    }

    func release(timestamp: Double) {
        guard tracking else { return }
        reset(releasing: timestamp - (lastTimestamp ?? 0) <= 0.12)
    }

    private func update(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: nil)
        guard touches.count == 2 || touches.count == 3 else {
            if touches.count < 2 && (!event.touches(matching: .ended, in: nil).isEmpty || event.phase == .ended) {
                release(timestamp: event.timestamp)
            } else if !coasting || !event.touches(matching: .cancelled, in: nil).isEmpty || touches.count > 3 {
                reset()
            }
            return
        }
        var point = NSPoint.zero
        for touch in touches {
            point.x += touch.normalizedPosition.x * touch.deviceSize.width / CGFloat(touches.count)
            point.y += touch.normalizedPosition.y * touch.deviceSize.height / CGFloat(touches.count)
        }
        update(point: point, touchCount: touches.count, timestamp: event.timestamp)
    }

    func update(point: NSPoint, touchCount: Int, timestamp: Double = ProcessInfo.processInfo.systemUptime) {
        guard touchCount == 2 || touchCount == 3 else { reset(); return }
        if coasting { reset() }
        if lastTouchCount != touchCount { reset() }
        lastTouchCount = touchCount
        if firstTimestamp == nil { firstTimestamp = timestamp }
        defer { lastPoint = point; lastTimestamp = timestamp }
        guard let previous = lastPoint else { return }
        accumulated.x += point.x - previous.x
        accumulated.y += point.y - previous.y
        if !tracking {
            horizontal = abs(accumulated.x) > abs(accumulated.y)
        }
        let direction: Double = horizontal && reversesHorizontalMotion ? -1 : 1
        let primary = (horizontal ? accumulated.x : accumulated.y) * direction
        let delta = (horizontal ? point.x - previous.x : point.y - previous.y) * direction
        if tracking {
            onChange?(Double(delta))
            onMotion?(Double(delta), min(0.25, max(1.0 / 240, timestamp - (lastTimestamp ?? timestamp))))
        }
        else if abs(primary) >= 8 {
            tracking = true
            onChange?(Double(primary))
            onMotion?(Double(primary), min(0.25, max(1.0 / 240, timestamp - (firstTimestamp ?? timestamp))))
        }
    }
}
