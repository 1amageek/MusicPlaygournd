import AppKit

/// Shares window touch delivery between control regions and edge mode.
@MainActor
enum TrackpadTouchDelivery {
    private static var users: [ObjectIdentifier: (count: Int, types: NSTouch.TouchTypeMask, resting: Bool)] = [:]

    static func acquire(_ view: NSView) {
        let key = ObjectIdentifier(view)
        var entry = users[key] ?? (0, view.allowedTouchTypes, view.wantsRestingTouches)
        entry.count += 1
        users[key] = entry
        view.allowedTouchTypes.insert(.indirect)
        view.wantsRestingTouches = true
    }

    static func release(_ view: NSView) {
        let key = ObjectIdentifier(view)
        guard var entry = users[key] else { return }
        entry.count -= 1
        if entry.count == 0 {
            view.allowedTouchTypes = entry.types
            view.wantsRestingTouches = entry.resting
            users.removeValue(forKey: key)
        } else { users[key] = entry }
    }
}
