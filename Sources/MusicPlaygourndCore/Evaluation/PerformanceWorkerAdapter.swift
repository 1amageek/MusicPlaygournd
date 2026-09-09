import Foundation
import Observation
import MusicPlayground
import SwiftMusic

/// Type-erased retained preparation for one generated PerformanceEntry model.
@MainActor
public final class PerformanceWorkerAdapter<Base: Music, Model: AnyObject & Observable & Sendable>:
    RenderWorkerPerformanceAdapter, Sendable {
    private let sliders = PlaygroundControlSession()
    private let model: Model
    private let observation: PerformanceObservationSession<Base>

    public init(
        base: Base,
        model: Model,
        compiler: SoundCompiler = .init()
    ) {
        self.model = model
        let resolvedMusic = base.performance(model)
        self.observation = PerformanceObservationSession(
            resolvedMusic,
            compiler: compiler,
            // The worker only prepares an explicit complete-set request. An
            // autonomous Observation callback never schedules audio work.
            onChange: {}
        )
    }

    public var controls: [PerformanceControlMetadata] {
        get throws {
            let mapped = try (model as? any PerformanceControllable)?.performanceControlMetadata() ?? []
            let modelID = mapped.first?.modelID ?? "MusicPlayground"
            let result = mapped + sliders.definitions.map {
                PerformanceControlMetadata(modelID: modelID, controlID: $0.id, label: "Slider",
                    domain: .double(range: $0.range, role: .scalar), value: .double($0.value))
            }
            try PerformanceControlMetadata.validate(result)
            return result
        }
    }

    public func currentValues() throws -> [String: PerformanceControlValue] {
        Dictionary(uniqueKeysWithValues: try controls.map { ($0.controlID, $0.value) })
    }

    private func sliderValues(_ values: [String: PerformanceControlValue]) throws -> [String: Double] {
        var result: [String: Double] = [:]
        for definition in sliders.definitions {
            guard case .double(let value) = values[definition.id] else {
                throw PerformanceControlError.valueTypeMismatch(definition.id)
            }
            result[definition.id] = value
        }
        return result
    }

    public func validate(values: [String: PerformanceControlValue]) throws {
        guard Set(values.keys) == Set(try controls.map(\.controlID)) else {
            throw PerformanceControlError.invalidMapping("Expected a complete control value set.")
        }
        let numeric = try sliderValues(values)
        try sliders.validate(numeric)
        if let controllable = model as? any PerformanceControllable {
            try controllable.validatePerformanceControls(values.filter { numeric[$0.key] == nil })
        }
    }

    public func apply(values: [String: PerformanceControlValue]) throws {
        try validate(values: values)
        let numeric = try sliderValues(values)
        if let controllable = model as? any PerformanceControllable {
            try controllable.applyPerformanceControls(values.filter { numeric[$0.key] == nil })
        }
        try sliders.apply(numeric)
    }

    public func prepare(
        revision: UInt64,
        source: String,
        fallbackBPM: Double,
        beatsPerBar: Int
    ) throws -> RenderWorkerPreparation {
        let metadata = try controls
        let bpm = try Self.renderBPM(from: metadata, fallback: fallbackBPM)
        let maximumLiveBeats = Int(min(
            PreparedLoop.maximumBeatCount,
            (PreparedLoop.maximumDurationSeconds * bpm / 60).rounded(.down)
        ))
        guard maximumLiveBeats > 0 else {
            throw SoundCompilationError.invalidPerformance("Performance BPM leaves no renderable horizon.")
        }
        let policy = try LiveLoopPolicy(
            beatsPerBar: beatsPerBar,
            maximumBeats: MusicalTime(numerator: UInt64(maximumLiveBeats), denominator: 1)
        )
        let sound = try sliders.evaluate(source: source) { try observation.prepareDetailed(liveLoop: policy) }
        let semanticMetadata = try EditorSemanticMetadata(
            sound: sound,
            source: source,
            revision: revision,
            sliders: sliders.definitions
        )
        let session = try LoopRenderSession(
            sound: sound,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            revision: revision
        )
        return RenderWorkerPreparation(
            session: session,
            metadata: semanticMetadata,
            source: source,
            performanceControls: try controls,
            performanceAdapter: self
        )
    }

    private static func renderBPM(
        from metadata: [PerformanceControlMetadata],
        fallback: Double
    ) throws -> Double {
        guard fallback.isFinite, (40...240).contains(fallback) else {
            throw SoundCompilationError.invalidPerformance("Fallback BPM is outside the render range.")
        }
        var bpm = fallback
        for control in metadata {
            guard case .double(let value) = control.value else { continue }
            guard case .double(_, let role) = control.domain else { continue }
            if role == .beatsPerMinute {
                bpm = value
                break
            }
        }
        guard bpm.isFinite, (40...240).contains(bpm) else {
            throw SoundCompilationError.invalidPerformance("Performance BPM is outside the render range.")
        }
        return bpm
    }
}
