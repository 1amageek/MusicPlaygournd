import AppKit
import AVFoundation
import Testing
@testable import MusicPlaygourndCore
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct ScratchInertiaTests {
        private func loop() -> PreparedLoop {
            var pcm = [Float](repeating: 0, count: 176_400)
            for frame in 0..<88_200 {
                pcm[frame * 2] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.3
                pcm[frame * 2 + 1] = -pcm[frame * 2]
            }
            return PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 4, samples: pcm, events: [])
        }

        private func render(_ transport: AudioTransport, frames: Int) throws -> [Float] {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            var samples: [Float] = []
            while samples.count < frames {
                let count = min(1024, frames - samples.count)
                buffer.frameLength = AVAudioFrameCount(count)
                #expect(transport.render(frameCount: count, audioBufferList: buffer.mutableAudioBufferList) == noErr)
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: count))
            }
            return samples
        }

        @Test(.timeLimit(.minutes(1)))
        func staggeredTwoAndThreeFingerLiftPreservesExactlyOneRelease() {
            for (first, second) in [(3, 2), (2, 3)] {
                let gesture = MultiFingerGestureRecognizer()
                var released = 0, cancelled = 0
                var motion: [Double] = []
                gesture.onRelease = { released += 1 }
                gesture.onEnd = { cancelled += 1 }
                gesture.onMotion = { distance, _ in motion.append(distance) }
                gesture.update(point: .zero, touchCount: first, timestamp: 1)
                gesture.update(point: NSPoint(x: 10, y: 0), touchCount: first, timestamp: 1.02)
                gesture.update(point: NSPoint(x: 100, y: 100), touchCount: second, timestamp: 1.04)
                #expect(motion == [10] && cancelled == 0)
                gesture.release(timestamp: 1.05)
                gesture.release(timestamp: 1.06)
                #expect(released == 1 && cancelled == 0)
                gesture.attach(to: nil)
                #expect(cancelled == 1)
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func recentHandVelocitySurvivesServoSettlementButExpiresAfterHolding() throws {
            for direction in [-1.0, 1.0] {
                let transport = AudioTransport()
                transport.beginUpdate(revision: 1)
                try transport.submit(loop: loop(), revision: 1)
                try transport.seek(bySeconds: 1)
                try transport.scratch(bySeconds: direction * 0.02, over: 0.02)
                _ = try render(transport, frames: 2646)
                // Native contacts can deliver a final stationary sample before lift.
                try transport.scratch(bySeconds: 0, over: 0.01)
                _ = try render(transport, frames: 441)
                let before = transport.positionSnapshot().accumulatedBeatPosition
                transport.releaseScratch()
                let samples = try render(transport, frames: 4410)
                let distance = transport.positionSnapshot().accumulatedBeatPosition - before
                print("RELEASE AFTER SETTLEMENT", direction, distance)
                #expect(distance * direction > 0.01)
                #expect(samples.contains { abs($0) > 0.01 })
                transport.endScratch(immediate: true)
                try transport.scratch(bySeconds: direction * 0.02, over: 0.02)
                _ = try render(transport, frames: 10_000)
                transport.releaseScratch()
                #expect(try render(transport, frames: 4410).allSatisfy { $0 == 0 })
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func nativeScratchModeTransitionsDoNotClick() async throws {
            for rate: Float in [0.5, 2] {
                let engine = try AudioLoopEngine()
                defer { engine.stop() }
                var pcm = [Float](repeating: 0, count: 176_400)
                for frame in 0..<88_200 {
                    pcm[frame * 2] = Float(sin(Double(frame) * 2 * .pi * 100 / 44_100)) * 0.3
                    pcm[frame * 2 + 1] = pcm[frame * 2]
                }
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                    beatCount: 4, samples: pcm, events: []), revision: 1)
                try engine.setPlaybackRate(rate)
                try engine.prepareOfflineRenderingForTests()
                try engine.play()
                var samples: [Float] = []
                func capture(_ count: Int) throws {
                    let output = try engine.renderOfflineForTests(frameCount: count)
                    samples.append(contentsOf: stride(from: 0, to: output.count, by: 2).map { output[$0] })
                }
                for _ in 0..<4 { try capture(4096) }
                for _ in 0..<30 {
                    try engine.scratch(bySeconds: 0.005, over: 0.01)
                    try capture(441)
                }
                engine.endScratch()
                try capture(1024)
                try await Task.sleep(for: .milliseconds(30))
                for _ in 0..<4 { try capture(4096) }
                let jump = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
                print("NATIVE SCRATCH mode transition jump", rate, jump)
                #expect(jump < 0.04)
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func nativeScratchPitchFollowsHandSpeedIndependentlyOfDeckTempo() throws {
            for rate: Float in [0.5, 2] {
                let engine = try AudioLoopEngine()
                defer { engine.stop() }
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: loop(), revision: 1)
                try engine.setPlaybackRate(rate)
                try engine.prepareOfflineRenderingForTests()
                for speed in [0.5, 1.0, -2.0] {
                    var samples: [Float] = []
                    for tick in 0..<100 {
                        try engine.scratch(bySeconds: speed * 0.01, over: 0.01)
                        let pcm = try engine.renderOfflineForTests(frameCount: 441)
                        if tick > 20 { samples.append(contentsOf: stride(from: 0, to: pcm.count, by: 2).map { pcm[$0] }) }
                    }
                    let crossings = zip(samples, samples.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
                    let frequency = Double(crossings) * 44_100 / Double(samples.count)
                    print("NATIVE SCRATCH Hz", rate, speed, frequency)
                    #expect(abs(frequency - 440 * abs(speed)) < 8)
                    engine.endScratch()
                    _ = try engine.renderOfflineForTests(frameCount: 1024)
                    _ = engine.snapshot()
                    #expect(engine.masterParametersForTests.rate == rate)
                }
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func waveHorizontalMotionFollowsFingersAndKeepsVerticalDirection() throws {
            for count in [2, 3] {
                for point in [NSPoint(x: 10, y: 0), NSPoint(x: -10, y: 0),
                              NSPoint(x: 0, y: 10), NSPoint(x: 0, y: -10)] {
                    let transport = AudioTransport()
                    transport.beginUpdate(revision: 1)
                    try transport.submit(loop: loop(), revision: 1)
                    try transport.seek(bySeconds: 1)
                    let gesture = MultiFingerGestureRecognizer()
                    gesture.reversesHorizontalMotion = true
                    var failure: Error?
                    gesture.onMotion = { distance, duration in
                        do { try transport.scratch(bySeconds: distance * 0.05, over: duration) }
                        catch { failure = error }
                    }
                    gesture.onRelease = { transport.releaseScratch() }
                    gesture.update(point: .zero, touchCount: count, timestamp: 1)
                    gesture.update(point: point, touchCount: count, timestamp: 1.1)
                    gesture.update(point: NSPoint(x: point.x * 1.1, y: point.y * 1.1), touchCount: count, timestamp: 1.11)
                    #expect(failure == nil)
                    let before = transport.snapshot().beatPosition
                    _ = try render(transport, frames: 100)
                    let held = transport.snapshot().beatPosition
                    let forward = point.x < 0 || point.y > 0
                    #expect(forward ? held > before : held < before)
                    gesture.release(timestamp: 1.12)
                    _ = try render(transport, frames: 100)
                    let released = transport.snapshot().beatPosition
                    #expect(forward ? released > held : released < held)
                }
            }
            let knob = MultiFingerGestureRecognizer()
            var delta = 0.0
            knob.onChange = { delta = $0 }
            knob.update(point: .zero, touchCount: 2, timestamp: 1)
            knob.update(point: NSPoint(x: 10, y: 0), touchCount: 2, timestamp: 1.1)
            #expect(delta == 10)
        }

        @Test(.timeLimit(.minutes(1)))
        func releasedVelocityDecaysAndResumesPlayIntent() throws {
            let transport = AudioTransport()
            transport.beginUpdate(revision: 1)
            try transport.submit(loop: loop(), revision: 1)
            try transport.seek(bySeconds: 1)
            try transport.scratch(bySeconds: -0.1, over: 0.1)
            transport.releaseScratch()
            let start = transport.snapshot().beatPosition
            let audible = try render(transport, frames: 4410)
            let first = transport.snapshot().beatPosition
            #expect(audible.contains { abs($0) > 0.01 })
            _ = try render(transport, frames: 4410)
            let second = transport.snapshot().beatPosition
            #expect(start > first && first > second)
            #expect(first - second < start - first)
            #expect(!transport.snapshot().isPlaying)
            _ = try render(transport, frames: 52_920)
            #expect(!transport.isScratching)
            #expect(try render(transport, frames: 256).allSatisfy { $0 == 0 })
            try transport.startPlayback()
            try transport.scratch(bySeconds: -0.1, over: 0.1)
            transport.releaseScratch()
            let playingReleaseStart = transport.snapshot().beatPosition
            _ = try render(transport, frames: 1000)
            #expect(transport.snapshot().beatPosition < playingReleaseStart)
            _ = try render(transport, frames: 55_000)
            #expect(!transport.isScratching && transport.snapshot().isPlaying)
            let before = transport.snapshot().beatPosition
            _ = try render(transport, frames: 100)
            #expect(abs(transport.snapshot().beatPosition - before - 200.0 / 44_100) < 0.000001)
            try transport.scratch(bySeconds: -0.1, over: 0.1)
            transport.releaseScratch()
            _ = try render(transport, frames: 1000)
            try transport.scratch(bySeconds: 0.1, over: 0.1)
            let grabbed = transport.positionSnapshot().accumulatedBeatPosition
            _ = try render(transport, frames: 1)
            #expect(transport.positionSnapshot().accumulatedBeatPosition < grabbed)
            _ = try render(transport, frames: 1000)
            #expect(transport.snapshot().beatPosition > grabbed)
            transport.endScratch()
            _ = try render(transport, frames: 256)
            #expect(!transport.isScratching)
        }

        @Test(.timeLimit(.minutes(1)))
        func pausedNativeCoastSoundsThenReleasesOutput() async throws {
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop(), revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.scratch(bySeconds: 0.1, over: 0.1)
            engine.releaseScratch()
            let first = try engine.renderOfflineForTests(frameCount: 4096)
            #expect(first.contains { abs($0) > 0.01 })
            for _ in 0..<18 { _ = try engine.renderOfflineForTests(frameCount: 4096) }
            try await Task.sleep(for: .milliseconds(30))
            // Retirement must not depend on a UI snapshot call.
            #expect(!engine.output.audioEngine.isRunning)
            #expect(!engine.snapshot().isPlaying)
        }

        @Test(.timeLimit(.minutes(1)))
        func cancellationClearsMotionWhenNativeOutputHasStopped() throws {
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop(), revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.scratch(bySeconds: 0.1, over: 0.1)
            _ = try engine.renderOfflineForTests(frameCount: 1024)
            engine.output.audioEngine.stop()
            engine.endScratch()
            // Seek rejects active scratch; a stopped graph cannot finish an audio fade.
            try engine.seek(bySeconds: 0.1)
            #expect(!engine.snapshot().isPlaying && !engine.output.audioEngine.isRunning)
        }

        @Test(.timeLimit(.minutes(1)))
        func naturalReleaseAndCancellationHaveSeparateCallbacks() {
            let gesture = MultiFingerGestureRecognizer()
            var released = 0
            var cancelled = 0
            gesture.onRelease = { released += 1 }
            gesture.onEnd = { cancelled += 1 }
            gesture.update(point: .zero, touchCount: 2, timestamp: 1)
            gesture.update(point: NSPoint(x: 10, y: 0), touchCount: 2, timestamp: 1.05)
            gesture.release(timestamp: 1.06)
            #expect(released == 1 && cancelled == 0)
            gesture.release(timestamp: 1.07)
            #expect(released == 1)
            gesture.update(point: .zero, touchCount: 3, timestamp: 1.08)
            #expect(cancelled == 1)
            gesture.update(point: NSPoint(x: 0, y: 10), touchCount: 3, timestamp: 1.1)
            gesture.release(timestamp: 2)
            #expect(released == 1 && cancelled == 2)
            gesture.update(point: .zero, touchCount: 2, timestamp: 3)
            gesture.update(point: NSPoint(x: 0, y: -10), touchCount: 2, timestamp: 3.05)
            gesture.release(timestamp: 3.06)
            gesture.attach(to: nil)
            #expect(released == 2 && cancelled == 3)
        }
    }
}
