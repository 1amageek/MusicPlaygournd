import AppKit
import CoreGraphics

/// Owns foreground pointer capture and routes edge contacts to the two decks.
@MainActor
final class TrackpadEdgeController {
    enum Region: Equatable { case crossfade, a, b }
    private struct Contact {
        let identity: any NSObjectProtocol
        let region: Region
        var point: NSPoint
        var timestamp: Double
        var moved = false
    }

    private static let crossfadeSensitivity = 3.0
    private static var owner: TrackpadEdgeController?
    static var isActive: Bool { owner != nil }
    private(set) var active = false
    var onModeChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onCrossfadeDelta: ((Double) -> Void)?
    var onScratch: ((Region, Double, Double) -> Void)?
    var onRelease: ((Region) -> Void)?
    var onCancel: (() -> Void)?
    private var contacts: [Contact] = []
    private var faderGesture = false
    private var faderPoint: NSPoint?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var touchView: NSView?
    private var cursorHidden = false
    private let keys = PlayModeKeys()
    var onKeyAction: ((PlayModeKeys.Action) -> Void)?

    static func region(at point: NSPoint) -> Region? {
        guard point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        if point.y <= 0.12 { return .crossfade }
        if point.x <= 0.18 { return .a }
        if point.x >= 0.82 { return .b }
        return nil
    }

    func begin(identity: any NSObjectProtocol, point: NSPoint, timestamp: Double) {
        guard !contacts.contains(where: { $0.identity.isEqual(identity) }),
              let region = Self.region(at: point),
              !contacts.contains(where: { $0.region == region }) else { return }
        contacts.append(Contact(identity: identity, region: region, point: point, timestamp: timestamp))
        if region != .crossfade { onStopScratch?(region) }
    }

    func move(identity: any NSObjectProtocol, point: NSPoint, deviceHeight: Double, timestamp: Double) {
        guard let index = contacts.firstIndex(where: { $0.identity.isEqual(identity) }),
              point.x.isFinite, point.y.isFinite, deviceHeight.isFinite, deviceHeight > 0 else { return }
        let old = contacts[index]
        guard timestamp > old.timestamp else { return }
        contacts[index].point = point
        contacts[index].timestamp = timestamp
        if old.region == .crossfade {
            onCrossfadeDelta?(Double(point.x - old.point.x) * Self.crossfadeSensitivity)
        } else {
            let distance = Double(point.y - old.point.y) * deviceHeight
            contacts[index].moved = true
            onScratch?(old.region, distance, min(0.25, max(1.0 / 240, timestamp - old.timestamp)))
        }
    }

    func end(identity: any NSObjectProtocol, timestamp: Double, cancelled: Bool) {
        guard let index = contacts.firstIndex(where: { $0.identity.isEqual(identity) }) else { return }
        let contact = contacts.remove(at: index)
        if contact.region != .crossfade && contact.moved {
            if !cancelled && timestamp - contact.timestamp <= 0.12 { onRelease?(contact.region) }
            else { onStopScratch?(contact.region) }
        }
    }

    var onStopScratch: ((Region) -> Void)?

    func cancelContacts() {
        faderGesture = false
        faderPoint = nil
        contacts.removeAll(keepingCapacity: true)
        onCancel?()
    }

    /// Two fingers own the whole pad until every contact lifts.
    func routeFader(point: NSPoint, touchCount: Int, contactsChanged: Bool = false) -> Bool {
        guard touchCount > 0 else {
            let consumed = faderGesture
            faderGesture = false
            faderPoint = nil
            return consumed
        }
        if touchCount == 2 && !faderGesture {
            cancelContacts()
            faderGesture = true
        }
        guard faderGesture else { return false }
        guard touchCount == 2, point.x.isFinite, point.y.isFinite else {
            faderPoint = nil
            return true
        }
        defer { faderPoint = point }
        guard !contactsChanged, let previous = faderPoint else { return true }
        let dx = point.x - previous.x, dy = point.y - previous.y
        onCrossfadeDelta?(Double(abs(dx) >= abs(dy) ? dx : dy) * Self.crossfadeSensitivity)
        return true
    }

    func start(in window: NSWindow) {
        guard !active else { return }
        guard Self.owner == nil, NSApp.isActive, window.isKeyWindow,
              let content = window.contentView else {
            onError?("Play Mode requires the active project window (app active: \(NSApp.isActive), window key: \(window.isKeyWindow), existing capture: \(Self.owner != nil)).")
            onModeChange?(false)
            return
        }
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        guard result == .success else {
            onError?("Could not capture the trackpad cursor (\(result.rawValue)).")
            onModeChange?(false)
            return
        }
        Self.owner = self
        active = true
        keys.reset()
        touchView = content
        TrackpadTouchDelivery.acquire(content)
        NSCursor.hide()
        cursorHidden = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.gesture, .scrollWheel, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown, .flagsChanged]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.active else { return false }
                if event.type == .flagsChanged {
                    if let action = self.keys.handle(type: event.type, keyCode: event.keyCode, flags: event.modifierFlags) { self.onKeyAction?(action) }
                    return false
                }
                if event.type == .keyDown {
                    if let action = self.keys.handle(type: event.type, keyCode: event.keyCode, flags: event.modifierFlags, repeating: event.isARepeat) { self.onKeyAction?(action) }
                    if event.keyCode == 53 { self.stop(); return true }
                    return !event.modifierFlags.contains(.command)
                }
                if event.type == .gesture { self.handle(event) }
                return true
            }
            return consume ? nil : event
        }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSWindow.willCloseNotification, window as AnyObject),
                               (NSApplication.willResignActiveNotification, NSApp as AnyObject),
                               (NSApplication.willTerminateNotification, NSApp as AnyObject)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        onModeChange?(true)
    }

    func stop() {
        guard active else { return }
        cancelContacts()
        keys.reset()
        let result = CGAssociateMouseAndMouseCursorPosition(1)
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        guard result == .success else {
            onError?("Could not release the cursor (\(result.rawValue)). Press Escape to retry.")
            return
        }
        active = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let touchView { TrackpadTouchDelivery.release(touchView) }
        touchView = nil
        Self.owner = nil
        onModeChange?(false)
    }

    private func handle(_ event: NSEvent) {
        var touchCount = 0
        var centroid = NSPoint.zero
        for touch in event.touches(matching: .touching, in: nil) where !touch.isResting {
            touchCount += 1
            centroid.x += touch.normalizedPosition.x / 2
            centroid.y += touch.normalizedPosition.y / 2
        }
        let changed = !event.touches(matching: [.began, .ended, .cancelled], in: nil).isEmpty
        if routeFader(point: centroid, touchCount: touchCount, contactsChanged: changed) { return }
        for touch in event.touches(matching: .began, in: nil) where !touch.isResting {
            begin(identity: touch.identity, point: touch.normalizedPosition, timestamp: event.timestamp)
        }
        for touch in event.touches(matching: .moved, in: nil) {
            move(identity: touch.identity, point: touch.normalizedPosition,
                 deviceHeight: Double(touch.deviceSize.height), timestamp: event.timestamp)
        }
        for touch in event.touches(matching: [.ended, .cancelled], in: nil) {
            end(identity: touch.identity, timestamp: event.timestamp, cancelled: touch.phase == .cancelled)
        }
    }
}
