import AppKit
import Testing
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct TrackpadEdgeTests {
        @Test(.timeLimit(.minutes(1)))
        func restingBottomContactMovesAlongsideActiveSideContact() {
            let controller = TrackpadEdgeController()
            var fades: [Double] = []
            var scratches: [Double] = []
            controller.onCrossfadeDelta = { fades.append($0) }
            controller.onScratch = { _, distance, _ in scratches.append(distance) }
            controller.handle(EdgeEvent([
                EdgeTouch(1, .began, NSPoint(x: 0.1, y: 0.5), resting: false),
                EdgeTouch(2, .began, NSPoint(x: 0.5, y: 0.1), resting: true)
            ], time: 1))
            #expect(fades.isEmpty && scratches.isEmpty)
            controller.handle(EdgeEvent([
                EdgeTouch(1, .moved, NSPoint(x: 0.1, y: 0.6), resting: false),
                EdgeTouch(2, .moved, NSPoint(x: 0.6, y: 0.1), resting: false)
            ], time: 1.1))
            #expect(scratches.count == 1)
            #expect(fades.count == 1)
            #expect(abs((fades.first ?? 0) - 0.3) < 0.0001)
        }

        @Test(.timeLimit(.minutes(1)))
        func edgeRoutingLocksContactsAndSeparatesReleaseFromCancellation() {
            let controller = TrackpadEdgeController()
            var fades: [Double] = []
            var scratch: [(TrackpadEdgeController.Region, Double)] = []
            var released: [TrackpadEdgeController.Region] = []
            var stopped: [TrackpadEdgeController.Region] = []
            var cancelled = 0
            controller.onCrossfadeDelta = { fades.append($0) }
            controller.onScratch = { scratch.append(($0, $1)); #expect($2 > 0 && $2 <= 0.25) }
            controller.onRelease = { released.append($0) }
            controller.onStopScratch = { stopped.append($0) }
            controller.onCancel = { cancelled += 1 }
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.5, y: 0.5)) == nil)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0, y: 0)) == .crossfade)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 1, y: 0)) == .crossfade)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.18, y: 0.5)) == .a)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.82, y: 0.5)) == .b)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: CGFloat.nan, y: 0)) == nil)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.181, y: 0.5)) == nil)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.819, y: 0.5)) == nil)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.18, y: 0.20)) == .crossfade)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.82, y: 0.20)) == .crossfade)
            #expect(TrackpadEdgeController.region(at: NSPoint(x: 0.5, y: 0.201)) == nil)
            let a = NSNumber(value: 1), b = NSNumber(value: 2), f = NSNumber(value: 3), center = NSNumber(value: 4)
            controller.begin(identity: a, point: NSPoint(x: 0.05, y: 0.5), timestamp: 1)
            controller.begin(identity: b, point: NSPoint(x: 0.95, y: 0.5), timestamp: 1)
            controller.begin(identity: f, point: NSPoint(x: 0.2, y: 0.05), timestamp: 1)
            controller.begin(identity: center, point: NSPoint(x: 0.5, y: 0.5), timestamp: 1)
            controller.move(identity: center, point: NSPoint(x: 0.01, y: 0.5), deviceHeight: 100, timestamp: 1.1)
            controller.move(identity: a, point: NSPoint(x: 0.95, y: 0.6), deviceHeight: 100, timestamp: 1.1)
            controller.move(identity: b, point: NSPoint(x: 0.05, y: 0.4), deviceHeight: 100, timestamp: 1.1)
            controller.move(identity: f, point: NSPoint(x: 0.8, y: 0.5), deviceHeight: 100, timestamp: 1.1)
            #expect(fades.count == 1 && abs(fades[0] - 1.8) < 0.0001)
            #expect(scratch.count == 2 && cancelled == 0)
            #expect(scratch[0].0 == .a && abs(scratch[0].1 - 10) < 0.0001)
            #expect(scratch[1].0 == .b && abs(scratch[1].1 + 10) < 0.0001)
            controller.end(identity: a, timestamp: 1.11, cancelled: false)
            controller.end(identity: b, timestamp: 1.11, cancelled: true)
            #expect(released == [.a])
            #expect(stopped == [.a, .b, .b])
            controller.cancelContacts()
            controller.move(identity: f, point: .zero, deviceHeight: 100, timestamp: 2)
            #expect(fades.count == 1 && cancelled == 1)

            controller.begin(identity: a, point: NSPoint(x: 0, y: 0.5), timestamp: 3)
            controller.begin(identity: b, point: NSPoint(x: 0, y: 0.6), timestamp: 3)
            controller.move(identity: b, point: NSPoint(x: 0, y: 0.7), deviceHeight: 100, timestamp: 3.1)
            #expect(scratch.count == 2)
            controller.move(identity: a, point: NSPoint(x: 0, y: 0.6), deviceHeight: 100, timestamp: 3.1)
            controller.end(identity: a, timestamp: 4, cancelled: false)
            #expect(released == [.a])
            #expect(stopped.last == .a)
        }

        @Test(.timeLimit(.minutes(1)))
        func crossfadeUsesFastRelativeMotionWithoutTouchDownJumps() {
            let controller = TrackpadEdgeController()
            var deltas: [Double] = []
            controller.onCrossfadeDelta = { deltas.append($0) }
            let finger = NSNumber(value: 1)
            controller.begin(identity: finger, point: NSPoint(x: 0.1, y: 0.05), timestamp: 1)
            #expect(deltas.isEmpty)
            controller.move(identity: finger, point: NSPoint(x: 0.2, y: 0.05), deviceHeight: 100, timestamp: 1.1)
            controller.move(identity: finger, point: NSPoint(x: 0.1, y: 0.05), deviceHeight: 100, timestamp: 1.2)
            #expect(deltas.count == 2)
            #expect(abs(deltas[0] - 0.3) < 0.0001)
            #expect(abs(deltas[1] + 0.3) < 0.0001)
            controller.end(identity: finger, timestamp: 1.3, cancelled: false)
            controller.begin(identity: finger, point: NSPoint(x: 0.8, y: 0.05), timestamp: 2)
            #expect(deltas.count == 2)
            controller.move(identity: finger, point: NSPoint(x: 0.7, y: 0.05), deviceHeight: 100, timestamp: 2.1)
            #expect(abs(deltas[2] + 0.3) < 0.0001)
        }

        @Test(.timeLimit(.minutes(1)))
        func touchDeliveryRestoresOnlyAfterLastOwner() {
            let view = NSView()
            view.allowedTouchTypes = []
            view.wantsRestingTouches = false
            TrackpadTouchDelivery.acquire(view)
            TrackpadTouchDelivery.acquire(view)
            TrackpadTouchDelivery.release(view)
            #expect(view.allowedTouchTypes.contains(.indirect) && view.wantsRestingTouches)
            TrackpadTouchDelivery.release(view)
            #expect(view.allowedTouchTypes.isEmpty && !view.wantsRestingTouches)
        }
    }
}

// Immutable snapshots emulate AppKit's new touch object for each event.
private final class EdgeTouch: NSTouch, @unchecked Sendable {
    let token: NSNumber
    let touchPhase: NSTouch.Phase
    let point: NSPoint
    let restingFlag: Bool
    init(_ id: Int, _ phase: NSTouch.Phase, _ point: NSPoint, resting: Bool) {
        token = NSNumber(value: id)
        touchPhase = phase
        self.point = point
        self.restingFlag = resting
        super.init()
    }
    override var identity: any NSObjectProtocol & NSCopying { token }
    override var phase: NSTouch.Phase { touchPhase }
    override var normalizedPosition: NSPoint { point }
    override var isResting: Bool { restingFlag }
    override var deviceSize: NSSize { NSSize(width: 140, height: 100) }
}

// The event owns immutable, Sendable touch snapshots.
private final class EdgeEvent: NSEvent, @unchecked Sendable {
    let snapshots: Set<NSTouch>
    let time: Double
    init(_ touches: Set<NSTouch>, time: Double) {
        snapshots = touches
        self.time = time
        super.init()
    }
    required init?(coder: NSCoder) { return nil }
    override var timestamp: TimeInterval { time }
    override func touches(matching phase: NSTouch.Phase, in view: NSView?) -> Set<NSTouch> {
        snapshots.filter { !phase.intersection($0.phase).isEmpty }
    }
}
