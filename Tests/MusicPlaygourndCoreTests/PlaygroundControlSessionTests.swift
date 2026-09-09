import MusicPlayground
import MusicPlaygourndCore
import SwiftMusic
import Testing

@MainActor
struct PlaygroundControlSessionTests {
    @Test(.timeLimit(.minutes(1)))
    func explicitAndAutomaticStateValidateAndSurviveEvaluation() throws {
        let session = PlaygroundControlSession()
        let explicit = SwiftMusic.State(wrappedValue: 0.2)
        func declaration() -> [Double] {
            [slider(explicit, id: "explicit"), slider(0.5, id: "automatic")]
        }
        #expect(try session.evaluate(declaration) == [0.2, 0.5])
        try session.apply(["explicit": 0.8, "automatic": 0.7])
        #expect(explicit.wrappedValue == 0.8)
        #expect(try session.evaluate(declaration) == [0.8, 0.7])
        #expect(throws: SliderDeclarationError.self) { try session.apply(["explicit": 0.1, "automatic": 2]) }
        #expect(explicit.wrappedValue == 0.8)
        #expect(try session.evaluate(declaration) == [0.8, 0.7])
        #expect(throws: SliderDeclarationError.self) { try session.evaluate { slider(-1, id: "bad") } }
        #expect(try session.evaluate(declaration) == [0.8, 0.7])
        let untouched = PlaygroundControlSession()
        #expect(try untouched.evaluate { slider(0.2, id: "initial") } == 0.2)
        #expect(try untouched.evaluate { slider(0.8, id: "initial") } == 0.2)
        let adapter = PerformanceWorkerAdapter(base: SliderMusic(), model: PlaygroundSessionModel())
        let initial = try adapter.prepare(revision: 1, source: "", fallbackBPM: 120, beatsPerBar: 4)
        #expect(initial.session.baseline.samples.contains { abs($0) > 0.001 })
        try adapter.apply(values: ["level": .double(0), "acid": .double(0.8)])
        let muted = try adapter.prepare(revision: 1, source: "", fallbackBPM: 120, beatsPerBar: 4)
        #expect(muted.session.baseline.samples.allSatisfy { $0 == 0 })
        #expect(muted.metadata?.sliders.count == 2)
        try adapter.apply(values: ["level": .double(0.2), "acid": .double(0.8)])
        let changed = try adapter.prepare(revision: 1, source: "", fallbackBPM: 120, beatsPerBar: 4)
        #expect(changed.session.baseline.samples != initial.session.baseline.samples)
    }

    private struct SliderMusic: Music {
        @State private var level = 0.2
        var body: some Sound {
            Synthesizer(.bandLimitedSaw).notes("C3").lowPass("200")
                .gain(slider($level, id: "level"))
                .acidEnvelope(slider(0.3, id: "acid"))
        }
    }
}
