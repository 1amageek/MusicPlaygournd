import Darwin
import Foundation
import Observation

@MainActor @Observable
final class DeckHost {
    private weak var controls: (any HostControls)?
    private let engine: AudioLoopEngine
    private let activate: @MainActor () async throws -> Void
    private let store: DocumentHostStateStore
    private var service: (any MIDIServiceProtocol)?
    private var events: Task<Void, Never>?
    private var scheduler: Task<Void, Never>?
    private var restoreTask: Task<Void, any Error>?
    private var effectTask: Task<Void, any Error>?
    private var effectRequest = UUID()
    private(set) var isLoadingEffect = false
    private var closed = false
    private var suspended = false
    private var configuring = false
    private var generation: UInt64 = 0
    private var commandGeneration: UInt64 = 0
    private var digest: String?
    private(set) var route = MIDISessionRoute.disabled
    private(set) var endpoints: [MIDIEndpointDescriptor] = []
    private(set) var effects: [HostedAudioUnitDescriptor] = []
    private(set) var snapshot: MIDIServiceSnapshot?
    private(set) var bindings: [DocumentHostStateStore.LearnBinding] = []
    private(set) var learning: LiveControlAddress?
    var error: String?

    init(controls: any HostControls, engine: AudioLoopEngine,
         service: (any MIDIServiceProtocol)? = nil,
         store: DocumentHostStateStore = DocumentHostStateStore(),
         activate: @escaping @MainActor () async throws -> Void) {
        self.controls = controls; self.engine = engine; self.service = service
        self.store = store; self.activate = activate
    }
    func discover() async throws {
        guard !closed else { throw MIDIError.serviceShutDown }
        if service == nil { service = try CoreMIDIService() }
        guard let service else { throw MIDIError.serviceShutDown }
        endpoints = try await service.enumerateEndpoints()
        effects = try engine.discoverAudioEffects()
    }
    func configure(_ next: MIDISessionRoute) async throws {
        guard !closed, !configuring else { throw MIDIError.invalidLoop("MIDI configuration is unavailable or already in progress.") }
        try next.validate(); configuring = true
        defer { configuring = false }
        try await discover()
        guard let service else { throw MIDIError.serviceShutDown }
        for input in next.inputIDs where !endpoints.contains(where: { $0.id == input && $0.direction == .input }) {
            throw MIDIError.endpointNotFound(input)
        }
        if let output = next.output, !endpoints.contains(where: { $0.id == output && $0.direction == .output }) { throw MIDIError.endpointNotFound(output) }
        let token = generation, previous = route
        scheduler?.cancel(); await scheduler?.value; scheduler = nil
        do {
            try await apply(next, replacing: previous, service: service)
            try Task.checkCancellation()
            guard token == generation, !closed else { throw CancellationError() }
            route = next; commandGeneration = 0
            try await resume()
        } catch {
            let original = error
            do { try await apply(previous, replacing: next, service: service) }
            catch { self.error = "MIDI failed: \(original.localizedDescription). Rollback failed: \(error.localizedDescription)" }
            route = previous
            if !closed, !suspended { do { try await resume() } catch { self.error = error.localizedDescription } }
            throw original
        }
    }
    private func apply(_ next: MIDISessionRoute, replacing previous: MIDISessionRoute, service: any MIDIServiceProtocol) async throws {
        for id in previous.inputIDs.subtracting(next.inputIDs) { try await service.disconnectInput(id) }
        for id in next.inputIDs.subtracting(previous.inputIDs) { try await service.connectInput(id) }
        try await service.setOutput(next.output); try await service.setClockMode(next.clockMode)
    }
    func resume() async throws {
        guard !closed else { throw MIDIError.serviceShutDown }
        suspended = false
        guard let service, route != .disabled else { return }
        if events == nil, route.input != nil {
            let stream = try await service.eventStream()
            events = Task { [weak self] in
                for await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    do { try await self.receive(event) } catch { self.error = error.localizedDescription }
                }
            }
        }
        if scheduler == nil {
            scheduler = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    do { try await self.poll(); try await Task.sleep(for: .milliseconds(50)) }
                    catch is CancellationError { return }
                    catch { self.error = error.localizedDescription; return }
                }
            }
        }
    }
    func suspend() async {
        suspended = true; generation &+= 1; learning = nil
        scheduler?.cancel(); effectTask?.cancel(); restoreTask?.cancel()
        if let effectTask {
            do { try await effectTask.value }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
        if let restoreTask {
            do { try await restoreTask.value } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
        await service?.updateClockAnchor(nil)
        await scheduler?.value; scheduler = nil
    }
    func shutdown() async {
        closed = true
        await suspend(); events?.cancel(); await service?.shutdown(); await events?.value
        events = nil; service = nil
    }
    func poll() async throws {
        guard let service, !closed, !suspended else { return }
        acceptedChanged()
        let anchor: PlaybackClockAnchor?
        do { anchor = try engine.playbackClockAnchor() }
        catch PlaybackClockError.unavailable { anchor = nil }
        await service.updateClockAnchor(anchor)
        if let anchor, anchor.isPlaying, let loop = controls?.loop {
            let now = mach_absolute_time()
            let start = now < anchor.presentationHostTime ? anchor.accumulatedBeatPosition : try anchor.beat(atHostTime: now)
            let end = start + anchor.beatsPerMinute / 60 * 0.1
            if route.sendsLoopNotes { try await service.schedule(loop: loop, from: start, through: end, channel: route.channel) }
            if case .send = route.clockMode { try await service.scheduleClock(from: start, through: end) }
        }
        let state = await service.snapshot(); snapshot = state
        switch state.clockHealth {
        case .failed(let message): error = message
        case .disconnected: error = "The MIDI endpoint disconnected."
        default: break
        }
        if case .receive = route.clockMode, let clock = state.receivedClock {
            if let bpm = clock.estimatedBPM, bpm != controls?.bpm { try controls?.setBPM(bpm) }
            if clock.commandGeneration > commandGeneration {
                commandGeneration = clock.commandGeneration
                let token = generation
                switch clock.lastCommand {
                case .start:
                    try await activate(); guard token == generation, !suspended else { throw CancellationError() }
                    try engine.restartFromBeginning()
                case .continue:
                    try await activate(); guard token == generation, !suspended else { throw CancellationError() }
                    try engine.play()
                case .stop: controls?.pause()
                default: break
                }
                controls?.refresh()
            }
        }
    }
    func beginLearn(_ address: LiveControlAddress) throws {
        acceptedChanged()
        guard route.input != nil, events != nil, controls?.catalog?.descriptor(for: address)?.presentation != nil else {
            throw MIDIError.invalidLoop("Select a live input and an accepted scalar control before Learn.")
        }
        learning = address
    }
    func cancelLearn() { learning = nil }
    func clearLearn(_ address: LiveControlAddress) { bindings.removeAll { $0.address == address }; if learning == address { learning = nil } }
    private func acceptedChanged() {
        let next = controls.map { DocumentHostStateStore.sourceDigest($0.acceptedSource) }
        if digest != next || bindings.contains(where: { controls?.catalog?.descriptor(for: $0.address) == nil }) {
            bindings = []; learning = nil; digest = next
        }
    }
    private func receive(_ event: TimestampedMIDIEvent) async throws {
        guard !closed, !suspended else { return }
        acceptedChanged()
        guard event.sourceID == route.input,
              case .controlChange(let channel, let controller, let value) = try event.message.validated() else { return }
        if let address = learning {
            bindings.removeAll { $0.address == address || ($0.endpoint == event.sourceID && $0.channel == channel && $0.controller == controller) }
            guard bindings.count < DocumentHostStateStore.maximumBindingCount else { throw DocumentHostStateStore.Failure.tooLarge }
            bindings.append(.init(endpoint: event.sourceID, channel: channel, controller: controller, address: address)); learning = nil
        }
        guard let binding = bindings.first(where: { $0.endpoint == event.sourceID && $0.channel == channel && $0.controller == controller }),
              let descriptor = controls?.catalog?.descriptor(for: binding.address), let presentation = descriptor.presentation else { return }
        let mapping = try LiveControlPresentation(unit: presentation.unit,
            minimum: binding.range?.lowerBound ?? presentation.minimum, maximum: binding.range?.upperBound ?? presentation.maximum, scale: presentation.scale)
        try await controls?.setControl(binding.address, value: .number(mapping.value(at: Double(value) / 127)))
    }
    func selectEffect(_ id: HostedAudioUnitID?, restoring state: HostedAudioUnitState? = nil) async throws {
        guard !closed, !engine.isRecording else { throw HostedAudioUnitError.graphFailed("Stop recording before selecting an effect.") }
        effectTask?.cancel()
        let token = generation, request = UUID()
        effectRequest = request; isLoadingEffect = true
        let task = Task {
            if let id { try await engine.selectAudioEffect(id, restoring: state) }
            else { try engine.clearAudioEffect() }
        }
        effectTask = task
        defer { if effectRequest == request { isLoadingEffect = false; effectTask = nil } }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard token == generation, !closed else { throw CancellationError() }
        controls?.refresh()
    }
    func bypassEffect(_ value: Bool) throws { try engine.setAudioEffectBypassed(value); controls?.refresh() }
    func save(for document: URL) throws {
        acceptedChanged()
        let effect: HostedAudioUnitState?, bypassed: Bool
        switch engine.audioEffectSnapshot() {
        case .none: effect = nil; bypassed = false
        case .loaded(_, let value): effect = try engine.captureAudioEffectState(); bypassed = value
        }
        try store.save(.init(adoptedSourceDigest: digest, route: route, effect: effect, effectBypassed: bypassed, bindings: bindings), for: document)
    }
    func restore(for document: URL) async throws {
        guard restoreTask == nil, !closed else { throw MIDIError.invalidLoop("Settings restoration is unavailable or already running.") }
        let task = Task { try await restoreSettings(for: document) }
        restoreTask = task
        defer { restoreTask = nil }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func restoreSettings(for document: URL) async throws {
        let token = generation
        guard let state = try store.load(for: document) else { return }
        try await discover()
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        let oldRoute = route
        let oldEffect: HostedAudioUnitState?
        let oldBypass: Bool
        switch engine.audioEffectSnapshot() {
        case .none: oldEffect = nil; oldBypass = false
        case .loaded(_, let bypassed): oldEffect = try engine.captureAudioEffectState(); oldBypass = bypassed
        }
        do {
            if let effect = state.effect {
                try await selectEffect(effect.id, restoring: effect)
                try bypassEffect(state.effectBypassed)
            } else { try engine.clearAudioEffect() }
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            try await configure(state.route)
        } catch {
            let original = error
            guard token == generation else { throw CancellationError() }
            do {
                if let effect = oldEffect { try await selectEffect(effect.id, restoring: effect); try bypassEffect(oldBypass) }
                else { try engine.clearAudioEffect() }
                try await configure(oldRoute)
            } catch { self.error = "Settings failed: \(original.localizedDescription). Rollback failed: \(error.localizedDescription)" }
            throw original
        }
        acceptedChanged()
        if state.adoptedSourceDigest == digest {
            bindings = state.bindings.compactMap { binding in
                guard let descriptor = controls?.catalog?.descriptors.first(where: { $0.address.target == binding.address.target && $0.address.parameter == binding.address.parameter }) else { return nil }
                return .init(endpoint: binding.endpoint, channel: binding.channel, controller: binding.controller, address: descriptor.address, range: binding.range)
            }
            if bindings.count != state.bindings.count { error = "Stale Learn bindings were detached." }
        } else if !state.bindings.isEmpty { error = "Learn bindings belong to a different accepted score." }
    }
}
