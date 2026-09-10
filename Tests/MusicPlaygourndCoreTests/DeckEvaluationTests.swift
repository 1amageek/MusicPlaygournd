import Foundation
import Testing
@testable import MusicPlaygourndApp
@testable import MusicPlaygourndCore

extension NativeHostTests {
    struct DeckEvaluationTests {
        @Test(.timeLimit(.minutes(2)))
        func compilerDiscoversMusicEntriesWithoutStartingWorkers() async throws {
            let host = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let sdk = host.appending(path: ".build/MusicPlaygournd.app/Contents/Resources/RuntimeSDK")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let evaluator = SourceEvaluator(packageURL: host, workspace: root.appending(path: "Worker"), swiftExecutable: "/usr/bin/swift", runtimeSDK: sdk)
            let source = """
            // struct Fake: Music {}
            struct Rhythm: Sound { var body: some Sound { Sample("kick") } }
            struct First: Music { var body: some Sound { Rhythm() } }
            """
            #expect(try await evaluator.musicEntries(source: source) == ["First"])
            #expect(try await evaluator.musicEntries(source: source + "\nstruct Second: SwiftMusic.Music { var body: some Sound { Rhythm() } }") == ["First", "Second"])
            #expect(try await evaluator.musicEntries(source: "struct OnlySound: Sound { var body: some Sound { Sample(\"kick\") } }").isEmpty)
            do {
                _ = try await evaluator.musicEntries(source: "struct Broken: Music { invalid source }")
                Issue.record("Invalid source unexpectedly passed discovery")
            } catch { #expect(await evaluator.workerStateForTests().pid == nil) }
            #expect(await evaluator.workerStateForTests().pid == nil)
            try await evaluator.shutdown()
        }

        @Test(.timeLimit(.minutes(6))) @MainActor
        func sameFileHasIndependentWorkersAndExplicitMusicEntries() async throws {
            let host = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let projectURL = root.appending(path: "Decks")
            try SessionModel.createProject(at: projectURL)
            let source = """
            import SwiftMusic
            import MusicPlayground
            struct Alternate: Music {
                @State private var level = 0.5
                var body: some Sound {
                    Synthesizer(.sine).notes("C3").gain(slider($level, in: 0...1))
                }
            }
            """
            let sources = projectURL.appending(path: "Sources/Decks")
            try "import SwiftMusic\nstruct Session: Music { var body: some Sound { Sample(\"kick\") } }".write(to: sources.appending(path: "Session.swift"), atomically: true, encoding: .utf8)
            let file = sources.appending(path: "Alternate.swift")
            try source.write(to: file, atomically: true, encoding: .utf8)
            let a = SourceEvaluator(packageURL: host, workspace: root.appending(path: "A"), swiftExecutable: "/usr/bin/swift", projectBuildCache: root.appending(path: "BuildA"))
            let b = SourceEvaluator(packageURL: host, workspace: root.appending(path: "B"), swiftExecutable: "/usr/bin/swift", projectBuildCache: root.appending(path: "BuildB"))
            do {
                let project = try await a.openProject(at: projectURL)
                let target = try #require(project.targets.first).selectingEntry("Alternate.swift")
                let request = try ProjectEvaluationRequest(project: project, target: target, buffers: [file: source])
                let first = try await a.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 1, project: request, entryType: "Alternate")
                #expect(await a.adopt(revision: 1))
                let second = try await b.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 1, project: request, entryType: "Alternate")
                #expect(await b.adopt(revision: 1))
                #expect(first.loop.samples.contains { abs($0) > 0.01 })
                let control = try #require(first.performanceControls.first)
                let muted = try await a.renderPerformance(values: [control.controlID: .double(0)], revision: 1, generation: 1)
                #expect(muted.loop.samples.allSatisfy { abs($0) < 0.00001 })
                let values = Dictionary(uniqueKeysWithValues: second.performanceControls.map { ($0.controlID, $0.value) })
                let unchanged = try await b.renderPerformance(values: values, revision: 1, generation: 1)
                #expect(unchanged.loop.samples == second.loop.samples)
                await a.discardPerformance(revision: 1, generation: 1)
                await b.discardPerformance(revision: 1, generation: 1)
                do {
                    _ = try await a.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 2, project: request, entryType: "MissingMusic")
                    Issue.record("A missing Music type unexpectedly compiled")
                } catch { #expect(await a.controlsAvailable(revision: 1)) }
                try await a.shutdown(); try await b.shutdown()
            } catch { try await a.shutdown(); try await b.shutdown(); throw error }
        }
    }
}
