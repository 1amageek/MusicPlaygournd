import AVFoundation
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct CueOutputTests {
        private func pull(_ ring: CueAudioBuffer, frames: Int = 256) throws -> AVAudioPCMBuffer {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            buffer.frameLength = AVAudioFrameCount(frames)
            #expect(ring.render(frames: frames, into: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)) == noErr)
            return buffer
        }

        @Test(.timeLimit(.minutes(1)))
        func boundedBridgePrimesWrapsAndClears() throws {
            let ring = CueAudioBuffer()
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048))
            input.frameLength = 2048
            for i in 0..<2048 { input.floatChannelData![0][i] = 0.25; input.floatChannelData![1][i] = -0.5 }
            ring.capture(input)
            let silent = try pull(ring)
            #expect(silent.floatChannelData![0][0] == 0)
            ring.reset(enabled: true)
            for _ in 0..<20 { ring.capture(input) }
            let output = try pull(ring)
            #expect(output.floatChannelData![0][255] == 0.25)
            #expect(output.floatChannelData![1][255] == -0.5)
            for _ in 0..<40 { _ = try pull(ring) }
            let exhausted = try pull(ring)
            #expect(exhausted.floatChannelData![0][0] == 0)
            ring.capture(input)
            let resumed = try pull(ring)
            #expect(resumed.floatChannelData![0][0] == 0.25)
            ring.reset(enabled: false)
            let stopped = try pull(ring)
            #expect(stopped.floatChannelData![1][0] == 0)
        }

        @Test(.timeLimit(.minutes(1)))
        func selectedDeviceUsesNativeSourceAndHeadphoneLevel() throws {
            let output = try AudioOutput()
            let main = try CueOutput.device(of: output.audioEngine)
            #expect(throws: PlaybackError.self) { try output.selectCueDevice(main) }
            guard let device = try output.availableCueDevices().first else { return }
            let deck = try AudioLoopEngine(output: output)
            deck.beginUpdate(revision: 1)
            try deck.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                beatCount: 4, samples: [Float](repeating: 0, count: 176_400), events: []), revision: 1)
            try deck.play()
            try output.selectMainOutput(device.id)
            #expect(try output.mainOutputDeviceID() == device.id)
            #expect(output.audioEngine.isRunning && deck.snapshot().isPlaying)
            try output.selectMainOutput(main)
            #expect(try output.mainOutputDeviceID() == main)
            deck.stop()
            try output.selectCueDevice(device.id)
            #expect(throws: PlaybackError.self) { try output.selectMainOutput(device.id) }
            #expect(try output.mainOutputDeviceID() == main)
            defer { output.cueOutput.stop() }
            let engine = try #require(output.cueOutput.engine)
            #expect(try CueOutput.device(of: engine) == device.id)
            engine.stop()
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
            let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048))
            input.frameLength = 2048
            for i in 0..<2048 { input.floatChannelData![0][i] = 0.4; input.floatChannelData![1][i] = -0.2 }
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
            try output.setCueLevel(0.25)
            output.cueOutput.buffer.reset(enabled: true)
            output.cueOutput.buffer.capture(input)
            try engine.start()
            #expect(try engine.renderOffline(256, to: pcm) == .success)
            #expect(abs(pcm.floatChannelData![0][255] - 0.1) < 0.001)
            #expect(abs(pcm.floatChannelData![1][255] + 0.05) < 0.001)
            try output.selectCueDevice(nil)
            #expect(output.cueDeviceID == nil)
        }

        @Test(.timeLimit(.minutes(1)))
        func nativeCueIsIndependentOfCrossfadeAndMainVolume() async throws {
            let output = try AudioOutput()
            let a = try AudioLoopEngine(output: output)
            let b = try AudioLoopEngine(output: output)
            defer { a.stop(); b.stop() }
            for (index, engine) in [a, b].enumerated() {
                var samples = [Float](repeating: 0, count: 176_400)
                for frame in 0..<88_200 { samples[frame * 2 + index] = index == 0 ? 0.25 : 0.5 }
                engine.beginUpdate(revision: 1)
                try engine.submit(loop: PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4,
                    beatCount: 4, samples: samples, events: []), revision: 1)
            }
            try a.prepareOfflineRenderingForTests()
            try output.setCrossfade(1)
            try output.setCue(true, deck: 0)
            output.cueOutput.buffer.reset(enabled: true)
            try a.play(); try b.play()
            for _ in 0..<4 { _ = try a.renderOfflineForTests(frameCount: 4096) }
            try await Task.sleep(for: .milliseconds(80))
            var cue = try pull(output.cueOutput.buffer)
            #expect(abs(cue.floatChannelData![0][255] - 0.25) < 0.01)
            #expect(abs(cue.floatChannelData![1][255]) < 0.0001)
            var main = try a.renderOfflineForTests(frameCount: 4096)
            #expect(abs(main[main.count - 2]) < 0.0001)
            #expect(abs(main[main.count - 1] - 0.5) < 0.01)
            try output.setCueMix(1)
            output.cueOutput.buffer.reset(enabled: true)
            for _ in 0..<4 { _ = try a.renderOfflineForTests(frameCount: 4096) }
            try await Task.sleep(for: .milliseconds(80))
            cue = try pull(output.cueOutput.buffer)
            #expect(abs(cue.floatChannelData![0][255]) < 0.0001)
            #expect(abs(cue.floatChannelData![1][255] - 0.5) < 0.01)
            a.stop(); b.stop()
            try output.setMasterVolume(0)
            output.cueOutput.buffer.reset(enabled: true)
            try a.play(); try b.play()
            for _ in 0..<4 { main = try a.renderOfflineForTests(frameCount: 4096) }
            try await Task.sleep(for: .milliseconds(80))
            #expect(main.allSatisfy { abs($0) < 0.0001 })
            cue = try pull(output.cueOutput.buffer)
            #expect(abs(cue.floatChannelData![1][255] - 0.5) < 0.01)
            #expect(throws: PlaybackError.self) { try output.setCueMix(.nan) }
            #expect(output.cueMix == 1)
            #expect(throws: PlaybackError.self) { try output.setCueLevel(2) }
            #expect(output.cueLevel == 0.5)
            #expect(throws: PlaybackError.self) { try output.selectCueDevice(UInt32.max) }
            #expect(output.cueDeviceID == nil)
        }
    }
}
