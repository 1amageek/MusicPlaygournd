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
            _ = try render(transport, frames: 55_000)
            #expect(!transport.isScratching && transport.snapshot().isPlaying)
            let before = transport.snapshot().beatPosition
            _ = try render(transport, frames: 100)
            #expect(abs(transport.snapshot().beatPosition - before - 200.0 / 44_100) < 0.000001)
            try transport.scratch(bySeconds: -0.1, over: 0.1)
            transport.releaseScratch()
            try transport.scratch(bySeconds: 0.1, over: 0.1)
            let grabbed = transport.snapshot().beatPosition
            _ = try render(transport, frames: 100)
            #expect(transport.snapshot().beatPosition > grabbed)
            transport.endScratch()
            #expect(!transport.isScratching)
        }

        @Test(.timeLimit(.minutes(1)))
        func pausedNativeCoastSoundsThenReleasesOutput() throws {
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
            #expect(!engine.snapshot().isPlaying)
            #expect(!engine.output.audioEngine.isRunning)
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
