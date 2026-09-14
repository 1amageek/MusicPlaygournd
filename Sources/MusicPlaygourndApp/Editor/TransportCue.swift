import MusicPlaygourndCore
import Observation

/// Owns transport cue position and a bounded hold gesture for one deck.
@MainActor @Observable
final class TransportCue {
    private let engine: AudioLoopEngine
    private(set) var cueBeat = 0.0
    private(set) var isPressed = false
    private(set) var isPreviewing = false
    var onError: ((Error) -> Void)?
    var onChange: (() -> Void)?
    private var hold: Task<Void, Never>?
    private var returnBeat = 0.0

    init(engine: AudioLoopEngine) { self.engine = engine }

    func press(shift: Bool = false) {
        guard !isPressed, engine.snapshot().loop != nil else { return }
        let wasPlaying = engine.snapshot().isPlaying
        engine.stop()
        do {
            if shift {
                try seek(to: 0)
                onChange?()
                return
            }
            if !wasPlaying { cueBeat = engine.snapshot().beatPosition }
            returnBeat = cueBeat
            try seek(to: returnBeat)
            isPressed = true
            hold = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                guard let self, self.isPressed else { return }
                do {
                    try self.engine.play()
                    self.isPreviewing = true
                    self.onChange?()
                } catch {
                    self.release()
                    self.onError?(error)
                }
            }
        } catch { onError?(error) }
        onChange?()
    }

    func release() {
        hold?.cancel()
        hold = nil
        guard isPressed else { return }
        isPressed = false
        if isPreviewing {
            engine.stop()
            do { try seek(to: returnBeat) } catch { onError?(error) }
        }
        isPreviewing = false
        onChange?()
    }

    func reset() { release(); cueBeat = 0 }

    private func seek(to beat: Double) throws {
        let snapshot = engine.snapshot()
        guard let loop = snapshot.loop else { throw PlaybackError.noCurrentLoop }
        try engine.seek(bySeconds: (beat - snapshot.beatPosition) * 60 / loop.bpm)
    }
}
