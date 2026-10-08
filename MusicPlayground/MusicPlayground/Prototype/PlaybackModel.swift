import Foundation
import Observation
import SwiftMusic

@MainActor @Observable
final class PlaybackModel {
    enum State: Equatable {
        case idle
        case preparing
        case playing
        case stopping
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var eventCount = 0
    private(set) var callbackCount: UInt64 = 0
    private(set) var peak: Float = 0
    private(set) var route = ""
    private let audio: any AudioPlaying
    private var prepared: PreparedLoop?
    private var pending: Task<PreparedLoop, any Error>?
    private var generation: UInt64 = 0

    init(audio: any AudioPlaying = NativeAudioPlayer()) { self.audio = audio }

    func play() async {
        guard state != .preparing, state != .playing, state != .stopping else { return }
        generation &+= 1
        let token = generation
        state = .preparing
        do {
            let loop: PreparedLoop
            if let prepared { loop = prepared }
            else {
                let sound = try SoundCompiler().compile(DemoMusic())
                let render = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try LoopRenderer().render(sound, bpm: 120, beatsPerBar: 4)
                }
                pending = render
                loop = try await withTaskCancellationHandler {
                    try await render.value
                } onCancel: { render.cancel() }
            }
            guard token == generation else { return }
            try Task.checkCancellation()
            pending = nil
            try await audio.start(loop)
            guard token == generation else { return }
            prepared = loop
            eventCount = loop.events.count
            state = .playing
            refreshOutput()
        } catch {
            guard token == generation else { return }
            pending = nil
            if error is CancellationError { state = .idle }
            else { state = .failed(error.localizedDescription) }
        }
    }

    func stop() async {
        guard state != .stopping else { return }
        state = .stopping
        generation &+= 1
        pending?.cancel()
        pending = nil
        do { try await audio.stop(); state = .idle }
        catch { state = .failed(error.localizedDescription) }
        refreshOutput()
    }

    func refreshOutput() {
        callbackCount = audio.meter.callbackCount
        peak = audio.meter.peak
        route = audio.outputDescription
        if state == .playing && !audio.isPlaying {
            Task { await stop() }
        }
    }
}
