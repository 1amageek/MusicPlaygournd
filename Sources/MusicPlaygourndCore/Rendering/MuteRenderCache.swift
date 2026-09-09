import Synchronization

/// Retains immutable, mute-independent PCM for one complete non-mute control state.
internal final class MuteRenderCache: Sendable {
    struct Snapshot: Sendable {
        let key: [LiveControlAddress: LiveControlValue]
        let buffers: [Int: StereoBuffer]
        let sourcePeaks: [[Float]]
    }

    private let state = Mutex<Snapshot?>(nil)

    func snapshot(for key: [LiveControlAddress: LiveControlValue]) -> Snapshot? {
        state.withLock { $0?.key == key ? $0 : nil }
    }

    func store(_ snapshot: Snapshot) {
        state.withLock { $0 = snapshot }
    }
}
