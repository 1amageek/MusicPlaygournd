import Foundation
import SwiftMusic
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    @MainActor
    struct MasterEqualizerTests {
        @Test(.timeLimit(.minutes(1)))
        func bipolarDJFilterChangesNativePCMAndResets() async throws {
            let sound = try SoundCompiler().compile(Synthesizer(.sine).notes("C4 C4 C4 C4"))
            let loop = try LoopRenderer().render(sound, bpm: 120, beatsPerBar: 4)
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop, revision: 1)
            try engine.prepareOfflineRenderingForTests()
            try engine.play()
            func energy() async throws -> Double {
                try await Task.sleep(for: .milliseconds(60))
                var result = 0.0
                for _ in 0..<6 {
                    result = try engine.renderOfflineForTests(frameCount: 2_048).reduce(0) { $0 + Double($1 * $1) }
                }
                return result
            }
            let dry = try await energy()
            try engine.setDJFilter(-1)
            let low = try await energy()
            try engine.setDJFilter(1)
            let high = try await energy()
            try engine.setDJFilter(0)
            let reset = try await energy()
            #expect(dry > 0 && low < dry * 0.01 && high < dry * 0.01)
            #expect(abs(reset / dry - 1) < 0.1)
            #expect(try engine.equalizerResponses().count == 3)
            #expect(throws: PlaybackError.invalidDJFilter(2)) { try engine.setDJFilter(2) }
            #expect(engine.masterParametersForTests.lowPass == nil)
            try engine.setDelayTime(seconds: 60 / 140)
            #expect(abs(engine.delayTimeForTests - 60 / 140) < 0.001)
            #expect(throws: PlaybackError.invalidDelayTime(3)) { try engine.setDelayTime(seconds: 3) }
            #expect(abs(engine.delayTimeForTests - 60 / 140) < 0.001)
            #expect(engine.snapshot().isPlaying && engine.snapshot().revision == 1)
        }

        @Test(.timeLimit(.minutes(1)))
        func liveBandCutsNativePCMAndRejectsInvalidValues() async throws {
            let sound = try SoundCompiler().compile(Synthesizer(.sine).notes("C4 C4 C4 C4"))
            let loop = try LoopRenderer().render(sound, bpm: 120, beatsPerBar: 4)
            let engine = try AudioLoopEngine()
            defer { engine.stop() }
            engine.beginUpdate(revision: 1)
            try engine.submit(loop: loop, revision: 1)
            try engine.prepareOfflineRenderingForTests()
            let initial = try engine.equalizerResponses()
            #expect(initial.count == 3 && initial.allSatisfy { abs($0.decibels(at: 1_000)) < 0.001 })
            try engine.setLowPass(cutoff: 10_000)
            try engine.play()
            func energy() throws -> Double {
                var result = 0.0
                for _ in 0..<4 {
                    result = try engine.renderOfflineForTests(frameCount: 2_048)
                        .reduce(0) { $0 + Double($1 * $1) }
                }
                return result
            }
            let baseline = try energy()
            let value = MasterEqualizerBand(frequency: 261.6256, gain: -12)
            try engine.setEqualizerBand(1, value: value)
            try await Task.sleep(for: .milliseconds(60))
            let filtered = try energy()
            let response = try engine.equalizerResponses()[1]
            #expect(abs(response.decibels(at: 261.6256) + 12) < 0.05)
            #expect(abs(response.decibels(at: 261.6256) - 10 * log10(filtered / baseline)) < 0.5)
            try engine.setEqualizerBand(1, value: .init(frequency: 261.6256, gain: -12, q: 8))
            try await Task.sleep(for: .milliseconds(60))
            let narrow = try engine.equalizerResponses()[1]
            #expect(abs(narrow.decibels(at: 261.6256) + 12) < 0.05)
            #expect(abs(narrow.decibels(at: 400)) < abs(response.decibels(at: 400)) * 0.3)
            try engine.setEqualizerBand(1, value: value)
            #expect(baseline > 0 && filtered < baseline * 0.15 && filtered > baseline * 0.02)
            #expect(engine.snapshot().isPlaying && engine.snapshot().revision == 1)
            #expect(engine.masterParametersForTests.lowPass == 10_000)
            for invalid in [MasterEqualizerBand(frequency: .nan), .init(frequency: 0), .init(frequency: 1_000, gain: 13), .init(frequency: 1_000, q: 0)] {
                #expect(throws: PlaybackError.invalidEqualizerBand) { try engine.setEqualizerBand(1, value: invalid) }
            }
            #expect(throws: PlaybackError.invalidEqualizerBand) { try engine.setEqualizerBand(3, value: value) }
            #expect(engine.equalizerBands[1] == value)
            try engine.setEqualizerBand(1, value: .init(frequency: 1_000))
            func channelEnergy(balance: Float) async throws -> (Double, Double) {
                try engine.setMasterBalance(balance)
                try await Task.sleep(for: .milliseconds(60))
                var pcm: [Float] = []
                for _ in 0..<4 { pcm = try engine.renderOfflineForTests(frameCount: 2_048) }
                var left = 0.0, right = 0.0
                for index in stride(from: 0, to: pcm.count, by: 2) {
                    left += Double(pcm[index] * pcm[index])
                    right += Double(pcm[index + 1] * pcm[index + 1])
                }
                return (left, right)
            }
            let left = try await channelEnergy(balance: -1)
            let right = try await channelEnergy(balance: 1)
            let center = try await channelEnergy(balance: 0)
            #expect(left.0 > 0 && left.1 < left.0 * 0.001)
            #expect(right.1 > 0 && right.0 < right.1 * 0.001)
            #expect(center.0 > 0 && abs(center.0 - center.1) < center.0 * 0.001)
            #expect(throws: PlaybackError.invalidMasterBalance(2)) { try engine.setMasterBalance(2) }
            #expect(engine.masterBalance == 0)
            #expect(engine.snapshot().isPlaying && engine.snapshot().revision == 1)

        }
    }
}
