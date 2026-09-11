import AppKit
import MusicPlayground
import MusicPlaygourndCore
import Observation
import SwiftMusic
import UniformTypeIdentifiers

@MainActor @Observable
final class SessionModel {
    static let maximumOpenDocuments = 32
    private(set) var fileBrowser = SessionFileBrowser()
    private(set) var project: SwiftPackageProject?
    var projectTarget: SwiftPackageProject.Target?
    private var deckIdentity = ""
    private var loadedManifest: String?
    private var projectCompletion: ProjectCompletionService?
    private var projectTask: Task<Void, Never>?
    private var projectRequestID = UUID()

    var documentStore: SessionDocumentStore?
    private(set) var loadedDocument: SessionDocument?
    private(set) var loadedType = "Session"

    private var projectBuffers: [URL: String] {
        if let documentStore { return documentStore.buffers }
        return Dictionary(uniqueKeysWithValues: documents.compactMap { document in
            guard !document.isReadOnly, let url = document.fileURL else { return nil }
            return (url, document.source)
        })
    }

    private var isProjectDocument: Bool {
        guard let root = project?.root, let fileURL else { return false }
        return activeDocument.isReadOnly || fileURL.path.hasPrefix(root.path + "/")
    }
    private(set) var documents = [SessionDocument(source: SessionModel.initialSource)]
    private var activeDocumentIndex = 0
    var activeDocument: SessionDocument { documents[activeDocumentIndex] }
    var activeDocumentID: UUID { activeDocument.id }
    var hasOpenDocument: Bool { fileURL != nil }
    private var revisionDocuments: [UInt64: UUID] = [:]
    var audibleDocumentID: UUID? { currentRevision.flatMap { revisionDocuments[$0] } }
    var editorLoop: PreparedLoop? { audibleDocumentID == activeDocumentID ? loop : nil }
    var source: String {
        get { activeDocument.source }
        set { guard !activeDocument.isReadOnly else { return }; activeDocument.source = newValue; diagnosticRange = nil }
    }
    private(set) var masterBalance: Float = 0

    func setMasterBalance(_ value: Float) {
        do {
            guard let engine else { throw PlaybackError.audioSetupFailed(audioError) }
            try engine.setMasterBalance(value)
            masterBalance = engine.masterBalance
        } catch { hostDiagnostic = error.localizedDescription }
    }

    private(set) var equalizerResponses: [MasterEqualizerResponse] = []
    private(set) var equalizerBands = MasterEqualizerBand.defaults
    private(set) var compressorSettings = MasterCompressorSettings.defaults
    private(set) var compressorMeter = MasterCompressorSnapshot.empty

    func setCompressor(_ value: MasterCompressorSettings) {
        do {
            guard let engine else { throw PlaybackError.audioSetupFailed(audioError) }
            try engine.setCompressor(value)
            compressorSettings = engine.compressorSettings
            compressorMeter = engine.compressorSnapshot()
        } catch { hostDiagnostic = error.localizedDescription }
    }


    func setEqualizerBand(_ index: Int, value: MasterEqualizerBand) {
        do {
            guard let engine else { throw PlaybackError.audioSetupFailed(audioError) }
            try engine.setEqualizerBand(index, value: value)
            equalizerBands = engine.equalizerBands
        } catch { hostDiagnostic = error.localizedDescription }
    }

    private var outputVolume = 1.0
    var masterVolume: Double {
        get { engine.map { Double($0.output.masterVolume) } ?? outputVolume }
        set {
            do {
                guard let engine else { throw EvaluationError.invalidResult(audioError) }
                try engine.setMasterVolume(Float(newValue))
                outputVolume = newValue
            } catch { hostDiagnostic = error.localizedDescription }
        }
    }
    func formatSource(_ source: String) async throws -> String { try await evaluator.format(source: source) }

    private var masterBPM = 140.0
    var bpm: Double {
        get { performanceBPMControlID.flatMap { performanceNumber($0) } ?? masterBPM }
        set {
            guard newValue.isFinite, (40...240).contains(newValue) else {
                diagnostic = "Tempo must be between 40 and 240 BPM."
                return
            }
            if let performanceBPMControlID {
                do { try setPerformanceValue(performanceBPMControlID, value: .double(newValue)) }
                catch { diagnostic = error.localizedDescription }
                return
            }
            masterBPM = newValue
            do {
                try engine?.setPlaybackRate(Float(newValue / (loop?.bpm ?? 120)))
                masterControlValues.removeValue(forKey: .playbackRate)
            } catch { diagnostic = error.localizedDescription }
        }
    }
    func adjustTempo(by delta: Double) {
        guard delta.isFinite else { return }
        var value = displayedBPM
        var range = 40.0...240.0
        if let id = performanceBPMControlID {
            let values = pendingPerformanceIntent?.values ?? activePerformanceIntent?.values
                ?? performanceTransaction?.values ?? performanceValues
            if case .double(let pending) = values[id] { value = pending }
            if let metadata = performanceControlMetadata.first(where: { $0.controlID == id }),
               case .double(let allowed, _) = metadata.domain {
                let lower = max(range.lowerBound, allowed.lowerBound)
                let upper = min(range.upperBound, allowed.upperBound)
                guard lower <= upper else { return }
                range = lower...upper
            }
        }
        bpm = min(range.upperBound, max(range.lowerBound, value + delta))
    }

    private(set) var djFilter = 0.0
    private var djDelayBPM: Double?

    func setDJFilter(_ value: Double) {
        do {
            guard let engine else { throw PlaybackError.audioSetupFailed(audioError) }
            try engine.setDJFilter(Float(value))
            djFilter = value
        } catch { hostDiagnostic = error.localizedDescription }
    }

    var lowPass = 20_000.0 {
        didSet {
            do { try engine?.setLowPass(cutoff: lowPass >= 19_999 ? nil : Float(lowPass)); masterControlValues.removeValue(forKey: .lowPassCutoff) }
            catch { lowPass = oldValue; diagnostic = error.localizedDescription }
        }
    }
    var delayMix = 0.0 {
        didSet {
            do { try engine?.setDelay(mix: Float(delayMix)); masterControlValues.removeValue(forKey: .delayMix) }
            catch { delayMix = oldValue; diagnostic = error.localizedDescription }
        }
    }
    var displayedReverbMix: Double {
        guard let descriptor = controlCatalog?.descriptors.first(where: {
            $0.address.target == .master && $0.address.parameter == .reverbMix
        }) else { return reverbMix }
        return controlValue(descriptor) ?? reverbMix
    }

    var reverbMix = 0.0 {
        didSet {
            do { try engine?.setReverb(mix: Float(reverbMix)); masterControlValues.removeValue(forKey: .reverbMix) }
            catch { reverbMix = oldValue; diagnostic = error.localizedDescription }
        }
    }
    var outputSamples = [Float]()
    var deckSamples = [Float]()
    var beatsPerBar = 4
    var diagnostic = "" { didSet { diagnosticRange = nil } }
    var status = "No project open"
    var preparationProgress = ""
    var isOpeningPackage = false
    var isPreparing = false
    var isPlaying = false
    private(set) var isRecording = false
    private(set) var isExportingStems = false
    private var stemExportTask: Task<StemExportSnapshot, Error>?
    private var stemExportID = UUID()
    private var isShuttingDown = false
    var loop: PreparedLoop? {
        didSet {
            // One bounded overview per adopted PCM buffer; animation only reads these bins.
            guard let loop else { loopPeaks = []; return }
            let frames = loop.samples.count / 2
            let count = min(512, frames)
            loopPeaks = (0..<count).map { bin in
                var peak: Float = 0
                for frame in (bin * frames / count)..<((bin + 1) * frames / count) {
                    peak = max(peak, abs(loop.samples[frame * 2]), abs(loop.samples[frame * 2 + 1]))
                }
                return peak
            }
        }
    }
    private(set) var loopPeaks: [Float] = []
    var beatPosition = 0.0
    var currentRevision: UInt64?
    var revision: UInt64 = 0
    var selectionLine: Int?
    var selectionRange: NSRange?
    private(set) var diagnosticRange: NSRange?
    private(set) var completionSites: [EditorSemanticMetadata.SampleCompletionSite] = []
    private var completionSource = ""
    private var candidateMetadata: [UInt64: EditorSemanticMetadata] = [:]
    var selectionToken = 0
    var fileURL: URL? {
        get { activeDocument.fileURL }
        set { activeDocument.fileURL = newValue }
    }
    var hasUnsavedChanges: Bool {
        get { activeDocument.isDirty }
        set { activeDocument.isDirty = newValue }
    }
    var inlineLayout = true
    var bottomLayout = false
    var audioError = ""
    var completionStatus = ""
    var highlightingStatus = ""
    var rowLines: [Int: Int] = [:]
    var resultLines: [Int: Int] = [:]
    private var spectrumSequence: UInt64?
    private var spectrumPlaying = false
    var spectrum = [Float](repeating: -90, count: SpectrumAnalyzer.bandCount)
    private var lineMaps: [UInt64: SourceLineMap] = [:]
    private var analyzer: SpectrumAnalyzer?
    private var engine: AudioLoopEngine?
    private var midiService: (any MIDIServiceProtocol)?
    private(set) var midiRoute = MIDISessionRoute.disabled
    private(set) var midiSnapshot: MIDIServiceSnapshot?
    private var midiSchedulingTask: Task<Void, Never>?
    private var midiConfigurationInProgress = false
    private var midiClosed = false
    private var lastMIDICommandGeneration: UInt64 = 0
    private var lastMIDIHealth: MIDIClockHealth?
    private let evaluator: SourceEvaluator
    private let completionService: SwiftCompletionService
    private var evaluationTask: Task<Void, Never>?
    private var wantsPlayback = false
    var isPlaybackQueued: Bool { wantsPlayback && !isPlaying }
    private(set) var controlCatalog: LiveControlCatalog?
    private(set) var controlsAvailable = false
    private(set) var overrideGeneration: UInt64 = 0
    private(set) var candidateCatalogs: [UInt64: LiveControlCatalog] = [:]
    private(set) var performanceControlMetadata: [PerformanceControlMetadata] = []
    private(set) var performanceValues: [String: PerformanceControlValue] = [:]
    private(set) var candidatePerformanceControls: [UInt64: [PerformanceControlMetadata]] = [:]
    private(set) var candidatePerformanceTransferIssues: [UInt64: PerformanceControlError] = [:]
    private var candidateSwitchBanks: [UInt64: PreparedSwitchBank] = [:]
    private var candidateSwitchSources: [UInt64: String] = [:]
    private var switchBank: PreparedSwitchBank?
    private var switchSource = ""
    private var selectedSwitchVariant = 0
    private var pendingSwitch: (index: Int, generation: UInt64, confirmed: Bool)?
    private var variantOverrides: [Int: [LiveControlAddress: LiveControlValue]] = [:]
    private var switchTask: Task<Void, Never>?
    private(set) var switchSelections: [Int] = []

    var switches: [SwitchControl] {
        guard audibleDocumentID == activeDocumentID, source == switchSource else { return [] }
        return switchBank?.controls ?? []
    }

    var switchesEnabled: Bool {
        !switches.isEmpty && !isPreparing && !isShuttingDown
    }

    var activeSwitchRanges: [NSRange] {
        switches.enumerated().flatMap { index, control in
            guard switchSelections.indices.contains(index) else { return [NSRange]() }
            let selected = switchSelections[index]
            return control.sites.compactMap { $0.caseRanges.indices.contains(selected) ? $0.caseRanges[selected] : nil }
        }
    }

    func selectSwitch(control: Int, choice: Int) {
        guard switchesEnabled, let bank = switchBank, let revision = currentRevision,
              let engine, bank.controls.indices.contains(control),
              bank.controls[control].cases.indices.contains(choice), requestedGeneration < UInt64.max else { return }
        var selection = bank.variants[pendingSwitch?.index ?? selectedSwitchVariant].selection
        selection[control] = choice
        guard let index = bank.variants.firstIndex(where: { $0.selection == selection }),
              index != (pendingSwitch?.index ?? selectedSwitchVariant) else { return }
        let generation = requestedGeneration + 1
        do { try engine.selectSwitchLoop(index: index, revision: revision, generation: generation) }
        catch { hostDiagnostic = error.localizedDescription; return }
        hostRestoreTask?.cancel()
        if controlsAvailable { variantOverrides[selectedSwitchVariant] = lastRenderedOverrides }
        pendingSwitch = (index, generation, false)
        requestedGeneration = generation
        let previousControl = controlTask
        previousControl?.cancel()
        controlTask = nil
        visualizationTask?.cancel()
        controlVisualization = nil
        controlsAvailable = false
        selectedControl = nil
        xyX = nil
        xyY = nil
        if !learnedBindings.isEmpty { hostDiagnostic = "MIDI Learn bindings were detached after the switch changed." }
        learnedBindings.removeAll()
        learnAddress = nil
        let previousSwitch = switchTask
        previousSwitch?.cancel()
        switchTask = Task { [weak self, evaluator] in
            await previousControl?.value
            await previousSwitch?.value
            do {
                try Task.checkCancellation()
                let accepted = try await evaluator.selectSwitchVariant(index: index, revision: revision, generation: generation)
                guard accepted else { throw EvaluationError.invalidResult("The switch worker rejected the selection.") }
                guard let self, !Task.isCancelled, self.currentRevision == revision,
                      self.pendingSwitch?.index == index, self.pendingSwitch?.generation == generation else { return }
                self.pendingSwitch?.confirmed = true
                self.switchTask = nil
                self.refresh()
            } catch is CancellationError { }
            catch {
                guard let self, self.currentRevision == revision, self.requestedGeneration == generation else { return }
                self.switchTask = nil
                self.hostDiagnostic = "Switch audio is active; controls are unavailable: \(error.localizedDescription)"
            }
        }
        refresh()
    }

    private var overrides: [LiveControlAddress: LiveControlValue] = [:]
    private var lastRenderedGeneration: UInt64 = 0
    private var lastRenderedOverrides: [LiveControlAddress: LiveControlValue] = [:]
    private var requestedGeneration: UInt64 = 0
    private var controlTask: Task<Void, Never>?
    private var adoptionTask: Task<Void, Never>?
    private var controlHealthTask: Task<Void, Never>?
    private var lastControlHealthCheck = ContinuousClock.now
    var selectedControl: LiveControlAddress? {
        didSet { if oldValue != selectedControl { requestControlVisualization() } }
    }
    private(set) var controlVisualization: PreparedControlVisualization?
    private(set) var visualizationStatus = "Choose a score control to inspect its trajectories."
    private var visualizationTask: Task<Void, Never>?
    private var selectionGeneration: UInt64 = 0
    var xyX: LiveControlAddress?
    var xyY: LiveControlAddress?
    var hostDiagnostic = ""
    private(set) var learnAddress: LiveControlAddress?
    private(set) var learnedBindings: [DocumentHostStateStore.LearnBinding] = []
    private(set) var midiEndpoints: [MIDIEndpointDescriptor] = []
    private(set) var audioEffects: [HostedAudioUnitDescriptor] = []
    private(set) var hostedEffect = HostedAudioUnitSnapshot.none
    private(set) var isLoadingEffect = false
    private(set) var performance: PlaybackPerformanceSnapshot?
    private var masterControlValues: [LiveControlParameter: LiveControlValue] = [:]
    private var midiEventTask: Task<Void, Never>?
    private var effectTask: Task<Void, Error>?
    private var effectRequestID = UUID()
    private var hostRestoreTask: Task<Void, Never>?
    private var pendingHostState: DocumentHostStateStore.State?
    private var adoptedSourceDigest: String?
    private(set) var candidateSourceDigests: [UInt64: String] = [:]
    private let hostStateStore: DocumentHostStateStore
    private(set) var isRestoringHostState = false

    private struct PerformanceIntent {
        let allowsIntermediateAdoption: Bool
        let revision: UInt64
        let generation: UInt64
        let values: [String: PerformanceControlValue]
    }

    private struct PerformanceTransaction {
        let revision: UInt64
        let generation: UInt64
        let values: [String: PerformanceControlValue]
        let evaluation: RetainedEvaluation
    }

    private var requestedPerformanceGeneration: UInt64 = 0
    private var pendingPerformanceIntent: PerformanceIntent?
    private var activePerformanceIntent: PerformanceIntent?
    private var performanceTask: Task<Void, Never>?
    private var performanceConfirmationTask: Task<Void, Never>?
    private var performanceTransaction: PerformanceTransaction?
    private var deferredEvaluation = false
    private var deferredEvaluationImmediate = false
    private var publishedPerformanceGeneration: UInt64 = 0
    private var reservedPerformanceToken: PerformanceReplacementToken?
    internal var performanceReservationDidPrepare: (() async -> Void)?
    private var requiresEvaluatorReset = false
    private var evaluatorResetTask: Task<Void, Never>?

    init(output: AudioOutput? = nil, deckID: String = "", documents store: SessionDocumentStore? = nil, audioEnabled: Bool = true) {
        documentStore = store
        deckIdentity = deckID
        hostStateStore = DocumentHostStateStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "MusicPlaygournd/HostState" + deckID))
        let bundle = Bundle.main
        let package = bundle.resourceURL?.appending(path: "SwiftMusic/MusicPlaygournd")
        let sourcePackage = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let packageURL = package.flatMap { FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path) ? $0 : nil } ?? sourcePackage
        // Workers remain process-local; SwiftPM build products survive app restarts.
        let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MusicPlaygournd/Evaluation-\(ProcessInfo.processInfo.processIdentifier)-\(deckID)")
        let swift = bundle.object(forInfoDictionaryKey: "SwiftExecutable") as? String ?? "/usr/bin/swift"
        evaluator = SourceEvaluator(packageURL: packageURL, workspace: cache, swiftExecutable: swift,
            runtimeSDK: bundle.object(forInfoDictionaryKey: "SwiftExecutable") == nil ? nil : bundle.resourceURL?.appending(path: "RuntimeSDK"),
            projectBuildCache: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "MusicPlaygournd/ProjectBuild" + deckID))
        completionService = SwiftCompletionService(packageURL: packageURL,
            workspace: cache.deletingLastPathComponent().appending(path: "Completion-\(ProcessInfo.processInfo.processIdentifier)-\(deckID)"),
            sourceKitLSPExecutable: URL(fileURLWithPath: swift).deletingLastPathComponent().appending(path: "sourcekit-lsp").path,
            hostModuleDirectory: bundle.object(forInfoDictionaryKey: "SwiftExecutable") == nil
                ? bundle.executableURL?.deletingLastPathComponent() : bundle.resourceURL?.appending(path: "RuntimeSDK"))
        do { analyzer = try SpectrumAnalyzer() }
        catch { diagnostic = "Spectrum analyzer could not initialize: \(error)" }
        do {
            guard audioEnabled else { throw PlaybackError.audioSetupFailed("Shared output is unavailable.") }
            engine = try output.map { try AudioLoopEngine(output: $0) } ?? AudioLoopEngine()
        }
        catch { audioError = error.localizedDescription; diagnostic = audioError }
    }

    init(evaluator: SourceEvaluator, completionService: SwiftCompletionService, engine: AudioLoopEngine,
         midiService: (any MIDIServiceProtocol)? = nil, hostStateStore: DocumentHostStateStore = DocumentHostStateStore()) {
        self.hostStateStore = hostStateStore
        self.evaluator = evaluator
        self.completionService = completionService
        self.engine = engine
        self.midiService = midiService
        do { analyzer = try SpectrumAnalyzer() }
        catch { diagnostic = "Spectrum analyzer could not initialize: \(error)" }
    }

    var syntaxContext: String {
        "\(project?.root.path ?? ""):\(projectRequestID):\(fileURL?.path ?? "")"
    }

    func previewSemanticTokens(source: String) async throws -> [SwiftSemanticToken] {
        try await completionService.semanticTokens(source: source)
    }

    func semanticTokens(source: String) async throws -> [SwiftSemanticToken] {
        if let fileURL, fileURL.pathExtension != "swift" { return [] }
        if isProjectDocument, let projectCompletion, let fileURL {
            return try await projectCompletion.semanticTokens(source: source, file: fileURL, buffers: projectBuffers)
        }
        return try await completionService.semanticTokens(source: source)
    }

    func completions(source: String, utf16Offset: Int) async throws -> [SwiftCompletion] {
        if isProjectDocument, let projectCompletion, let fileURL {
            return try await projectCompletion.completions(source: source, utf16Offset: utf16Offset, file: fileURL, buffers: projectBuffers)
        }
        if source == self.source, source == completionSource, let site = completionSites.first(where: {
            utf16Offset >= $0.contentRange.location && utf16Offset <= NSMaxRange($0.contentRange)
        }), NSMaxRange(site.contentRange) <= source.utf16.count {
            let prefix = (source as NSString).substring(with: NSRange(location: site.contentRange.location,
                length: utf16Offset - site.contentRange.location))
            return site.values.filter { $0.hasPrefix(prefix) }.map {
                SwiftCompletion(label: $0, detail: "Sample bank", insertion: $0, replacementRange: site.contentRange)
            }
        }
        return try await completionService.completions(source: source, utf16Offset: utf16Offset)
    }

    func sharedSourceChanged(_ document: SessionDocument) {
        guard document.name != "Package.swift" else { return }
        if document === loadedDocument || document.fileURL.map({ url in project.map { url.path.hasPrefix($0.root.path + "/") } ?? false }) == true {
            scheduleEvaluation()
        }
    }

    func musicEntries(in document: SessionDocument) async throws -> [String] {
        guard !document.isReadOnly, let url = document.fileURL, url.pathExtension == "swift", document.name != "Package.swift" else {
            throw EvaluationError.invalidSource("Select a writable Swift Music source.")
        }
        var request: ProjectEvaluationRequest?
        if let project {
            guard let target = project.targets.first(where: { url.path.hasPrefix(project.root.appending(path: $0.path).path + "/") }) else {
                throw EvaluationError.invalidSource("The file is outside this project's Swift targets.")
            }
            let relative = String(url.path.dropFirst(project.root.appending(path: target.path).path.count + 1))
            request = try ProjectEvaluationRequest(project: project, target: target.selectingEntry(relative), buffers: projectBuffers)
        }
        return try await evaluator.musicEntries(source: document.source, project: request)
    }

    func loadIntoDeck(_ document: SessionDocument, type: String = "Session") throws {
        guard !document.isReadOnly, let url = document.fileURL, url.pathExtension == "swift" else {
            throw EvaluationError.invalidSource("Select a writable Swift Music source.")
        }
        if let project {
            guard let target = project.targets.first(where: { url.path.hasPrefix(project.root.appending(path: $0.path).path + "/") }) else {
                throw EvaluationError.invalidSource("The file is outside this project's Swift targets.")
            }
            let relative = String(url.path.dropFirst(project.root.appending(path: target.path).path.count + 1))
            projectTarget = try target.selectingEntry(relative)
        }
        if loadedDocument !== document || loadedType != type { loadHostSettings(for: url) }
        loadedDocument = document
        loadedType = type
        documentStore?.membershipDidChange?()
        rememberProjectNavigation()
        scheduleEvaluation(immediate: true)
    }

    func synchronize(to reference: SessionModel) throws {
        guard let engine, let other = reference.engine else { throw PlaybackClockError.unavailable }
        guard performanceBPMControlID == nil else {
            throw EvaluationError.invalidSource("Sync requires deck tempo; this Music controls its own BPM.")
        }
        try engine.synchronize(to: other)
        masterBPM = reference.displayedBPM
    }

    func setDeckGain(_ value: Double) throws {
        guard let engine else { throw PlaybackError.audioSetupFailed(audioError) }
        try engine.setDeckGain(Float(value))
    }

    func sourceChanged() {
        guard !activeDocument.isReadOnly else { return }
        hasUnsavedChanges = true
        updateRowLines()
        if let documentStore { documentStore.sourceDidChange?(activeDocument) }
        else if !isProjectManifest(activeDocument) { scheduleEvaluation() }
    }

    private func isProjectManifest(_ document: SessionDocument) -> Bool {
        guard let root = project?.root else { return false }
        return document.fileURL == root.appending(path: "Package.swift")
    }

    func scheduleEvaluation(immediate: Bool = false) {
        guard hasOpenDocument || loadedDocument != nil, loadedDocument != nil || !activeDocument.isReadOnly || project != nil else { return }
        if requiresEvaluatorReset {
            deferredEvaluation = true
            deferredEvaluationImmediate = deferredEvaluationImmediate || immediate
            status = "Performance update in progress · edit queued"
            if performanceTask == nil { resumeDeferredEvaluationIfPossible() }
            return
        }
        if performanceTask != nil || performanceTransaction != nil || performanceConfirmationTask != nil {
            deferredEvaluation = true
            deferredEvaluationImmediate = deferredEvaluationImmediate || immediate
            status = "Performance update in progress · edit queued"
            return
        }
        refresh()
        evaluationTask?.cancel()
        guard revision < UInt64.max else { diagnostic = "Revision limit reached. Reopen the app."; return }
        revision += 1
        let requested = revision
        revisionDocuments = revisionDocuments.filter { $0.key == currentRevision || $0.key == requested - 1 }
        revisionDocuments[requested] = activeDocumentID
        lineMaps = lineMaps.filter { $0.key == currentRevision }
        engine?.beginUpdate(revision: requested)
        // Reconcile adoption after atomically clearing pending audio: a bar may have
        // adopted the previous candidate between the earlier snapshot and beginUpdate.
        refresh()
        let projectRequest: ProjectEvaluationRequest?
        let text: String
        do {
            if (isProjectDocument || documentStore != nil), let project, let target = projectTarget {
                let entry = project.entryURL(for: target)
                text = try projectBuffers[entry] ?? String(contentsOf: entry, encoding: .utf8)
                projectRequest = try ProjectEvaluationRequest(project: project, target: target, buffers: projectBuffers)
                revisionDocuments[requested] = loadedDocument?.id ?? documents.first(where: { $0.fileURL == entry })?.id
            } else {
                let entryURL = loadedDocument?.fileURL ?? fileURL
                guard entryURL == nil || entryURL?.pathExtension == "swift" else {
                    isPreparing = false
                    status = "Select a Swift session to play"
                    return
                }
                text = loadedDocument?.source ?? source
                revisionDocuments[requested] = loadedDocument?.id ?? activeDocumentID
                projectRequest = nil
            }
        } catch { diagnostic = error.localizedDescription; isPreparing = false; if loop == nil { wantsPlayback = false }; return }
        let tempo = 120.0
        let entryType = loadedType
        let meter = beatsPerBar
        diagnostic = ""
        diagnosticRange = nil
        isPreparing = true
        preparationProgress = "Preparing package build…"
        status = loop == nil ? "Preparing your first loop…" : "Preparing edit · current loop continues"
        evaluationTask = Task { [weak self, evaluator] in
            do {
                if !immediate { try await Task.sleep(for: .milliseconds(150)) }
                await self?.adoptionTask?.value
                let evaluation = try await evaluator.evaluateRetained(source: text, bpm: tempo, beatsPerBar: meter, revision: requested, project: projectRequest, entryType: entryType, progress: { [weak self] message in
                    await MainActor.run {
                        guard let self, self.revision == requested, !self.isOpeningPackage else { return }
                        self.preparationProgress = message
                    }
                })
                let candidate = evaluation.loop
                try Task.checkCancellation()
                guard let self, requested == self.revision else { return }
                guard let engine = self.engine else { throw EvaluationError.invalidResult(self.audioError) }
                let rows = evaluation.switchBank?.variants.flatMap { $0.loop.rows } ?? candidate.rows
                self.lineMaps[requested] = SourceLineMap(source: text, lines: rows.flatMap { [$0.anchor?.line, $0.resultLine].compactMap { $0 } })
                self.candidateSwitchBanks = evaluation.switchBank.map { [requested: $0] } ?? [:]
                self.candidateSwitchSources = evaluation.switchBank == nil ? [:] : [requested: text]
                if !evaluation.switchIssues.isEmpty { self.hostDiagnostic = evaluation.switchIssues.joined(separator: "\n") }
                self.candidateCatalogs = [requested: evaluation.catalog]
                self.candidateMetadata = [requested: evaluation.metadata]
                self.candidatePerformanceControls = [requested: evaluation.performanceControls]
                if let issue = evaluation.performanceTransferIssue {
                    self.candidatePerformanceTransferIssues = [requested: issue]
                } else {
                    self.candidatePerformanceTransferIssues = [:]
                }
                self.candidateSourceDigests = [requested: DocumentHostStateStore.sourceDigest(text)]
                try engine.submit(loop: candidate, revision: requested)
                if self.wantsPlayback { try engine.play() }
                self.isPreparing = false
                self.status = "Ready · waiting for the next bar"
                self.refresh()
            } catch is CancellationError {
                // A newer revision owns the UI and pending state.
            } catch {
                guard let self, requested == self.revision else { return }
                self.isPreparing = false
                if self.loop == nil { self.wantsPlayback = false }
                self.diagnostic = error.localizedDescription
                if case EvaluationError.compilerDiagnostic(_, let range) = error, self.source == text {
                    self.diagnosticRange = range?.utf16Range
                }
                self.status = self.loop == nil ? "Fix the error to start" : "Edit failed · previous loop continues"
            }
        }
    }

    func prepareInitialSource() {
        guard revision == 0, !isPreparing, loop == nil else { return }
        scheduleEvaluation(immediate: true)
    }

    func scratch(distance: Double, duration: Double) {
        guard let engine, loop != nil else { return }
        do {
            try engine.scratch(bySeconds: distance * 0.05, over: duration)
        } catch { diagnostic = error.localizedDescription }
    }

    func releaseScratch() { engine?.releaseScratch() }

    func endScratch() {
        engine?.endScratch()
        refresh()
    }

    func togglePlayback() {
        guard hasOpenDocument || loadedDocument != nil || isPlaying else { return }
        guard let engine else { diagnostic = audioError; return }
        if isPlaying || wantsPlayback {
            wantsPlayback = false
            engine.stop()
        } else {
            wantsPlayback = true
            if loop == nil {
                if !isPreparing { scheduleEvaluation(immediate: true) }
                return
            }
            do { try engine.play() }
            catch { diagnostic = error.localizedDescription; wantsPlayback = false }
        }
        refresh()
    }

    func refresh(masterCapture: OutputMeterSnapshot? = nil) {
        guard let snapshot = engine?.snapshot() else { return }
        isPlaying = snapshot.isPlaying
        isRecording = engine?.isRecording ?? false
        beatPosition = snapshot.beatPosition
        if currentRevision != snapshot.revision {
            hostRestoreTask?.cancel()
            switchTask?.cancel()
            switchTask = nil
            switchBank = nil
            switchSource = ""
            switchSelections = []
            pendingSwitch = nil
            variantOverrides = [:]
            currentRevision = snapshot.revision
            loop = snapshot.loop
            overrideGeneration = snapshot.overrideGeneration
            requestedGeneration = 0
            overrides.removeAll()
            lastRenderedOverrides.removeAll()
            lastRenderedGeneration = 0
            requestedPerformanceGeneration = 0
            pendingPerformanceIntent = nil
            performanceTransaction = nil
            performanceConfirmationTask?.cancel()
            performanceConfirmationTask = nil
            performanceControlMetadata = []
            performanceValues = [:]
            publishedPerformanceGeneration = snapshot.performanceGeneration
            controlTask?.cancel()
            visualizationTask?.cancel()
            controlVisualization = nil
            controlsAvailable = false
            controlCatalog = nil
            adoptionTask?.cancel()
            if let adoptedRevision = snapshot.revision,
               let catalog = candidateCatalogs[adoptedRevision] {
                let performanceControls = candidatePerformanceControls[adoptedRevision] ?? []
                let transferIssue = candidatePerformanceTransferIssues[adoptedRevision]
                adoptionTask = Task { [weak self, evaluator] in
                    let adopted = await evaluator.adopt(revision: adoptedRevision)
                    let available = await evaluator.controlsAvailable(revision: adoptedRevision)
                    guard let self, self.currentRevision == adoptedRevision, !Task.isCancelled else { return }
                    guard adopted, available else {
                        self.diagnostic = "The adopted loop has no live render worker. Audio continues."
                        return
                    }
                    do {
                        self.performanceControlMetadata = performanceControls
                        self.performanceValues = Dictionary(uniqueKeysWithValues: performanceControls.map { ($0.controlID, $0.value) })
                        self.controlCatalog = try self.catalogWithMasters(catalog, revision: adoptedRevision)
                        if self.performanceBPMControlID != nil {
                            try self.engine?.setPlaybackRate(1)
                        } else if case .number(let rate) = self.masterControlValues[.playbackRate] {
                            try self.engine?.setPlaybackRate(Float(rate))
                        } else {
                            try self.engine?.setPlaybackRate(Float(self.masterBPM / (self.loop?.bpm ?? 120)))
                        }
                        if let bank = self.candidateSwitchBanks[adoptedRevision] {
                            try self.engine?.installSwitchLoops(bank.variants.map(\.loop), initialIndex: bank.initialIndex, revision: adoptedRevision)
                            self.switchBank = bank
                            self.switchSource = self.candidateSwitchSources[adoptedRevision] ?? ""
                            self.selectedSwitchVariant = bank.initialIndex
                            self.switchSelections = bank.variants[bank.initialIndex].selection
                        }
                        self.controlsAvailable = true
                        self.adoptedControlsDidChange(revision: adoptedRevision)
                        if let transferIssue {
                            self.hostDiagnostic = transferIssue.localizedDescription
                        }
                    } catch { self.diagnostic = error.localizedDescription }
                }
            }
            candidateSwitchBanks = candidateSwitchBanks.filter { $0.key == currentRevision || $0.key == revision }
            candidateSwitchSources = candidateSwitchSources.filter { $0.key == currentRevision || $0.key == revision }
            lineMaps = lineMaps.filter { $0.key == currentRevision || $0.key == revision }
            candidatePerformanceControls = candidatePerformanceControls.filter { $0.key == currentRevision || $0.key == revision }
            candidatePerformanceTransferIssues = candidatePerformanceTransferIssues.filter { $0.key == currentRevision || $0.key == revision }
            updateRowLines()
        }
        if overrideGeneration != snapshot.overrideGeneration {
            overrideGeneration = snapshot.overrideGeneration
            loop = snapshot.loop
            updateRowLines()
            requestControlVisualization()
        }
        if let bank = switchBank, let revision = currentRevision, let index = snapshot.switchVariantIndex,
           bank.variants.indices.contains(index) {
            selectedSwitchVariant = index
            switchSelections = bank.variants[index].selection
            if let pending = pendingSwitch, pending.confirmed, pending.index == index,
               pending.generation == snapshot.overrideGeneration {
                do {
                    controlCatalog = try catalogWithMasters(bank.variants[index].catalog, revision: revision)
                    candidateMetadata[revision] = bank.variants[index].metadata
                    completionSites = bank.variants[index].metadata.completionSites
                    completionSource = source
                    overrides = variantOverrides[index] ?? [:]
                    lastRenderedOverrides = overrides
                    lastRenderedGeneration = pending.generation
                    pendingSwitch = nil
                    controlsAvailable = true
                } catch { hostDiagnostic = error.localizedDescription }
            }
        }
        if let transaction = performanceTransaction,
           snapshot.revision == transaction.revision,
           snapshot.performanceGeneration == transaction.generation,
           performanceConfirmationTask == nil {
            let revision = transaction.revision
            let generation = transaction.generation
            performanceConfirmationTask = Task { [weak self, evaluator] in
                let confirmed = await evaluator.confirmPerformance(revision: revision, generation: generation)
                guard let self else { return }
                self.finishPerformanceConfirmation(revision: revision, generation: generation, confirmed: confirmed)
            }
        }
        if controlsAvailable, controlHealthTask == nil, let currentRevision,
           lastControlHealthCheck.duration(to: .now) >= .seconds(1) {
            lastControlHealthCheck = .now
            controlHealthTask = Task { [weak self, evaluator] in
                let available = await evaluator.controlsAvailable(revision: currentRevision)
                guard let self else { return }
                defer { self.controlHealthTask = nil }
                guard !Task.isCancelled, self.currentRevision == currentRevision else { return }
                if !available {
                    self.controlsAvailable = false
                    self.diagnostic = "The live render worker stopped. Audio continues; evaluate a new edit to restore controls."
                }
            }
        }
        if snapshot.loop != nil, let engine {
            if djDelayBPM != displayedBPM {
                do { try engine.setDelayTime(seconds: 60 / displayedBPM); djDelayBPM = displayedBPM }
                catch { hostDiagnostic = error.localizedDescription }
            }
            do {
                let responses = try engine.equalizerResponses()
                if responses != equalizerResponses { equalizerResponses = responses }
            } catch { hostDiagnostic = error.localizedDescription }
        }
        if let capture = masterCapture ?? engine?.outputMeter() {
            compressorMeter = engine?.compressorSnapshot() ?? .empty
            outputSamples = capture.interleavedSamples
            let deckCapture = engine?.deckMeter()
            deckSamples = deckCapture?.interleavedSamples ?? []
            performance = capture.performance
            hostedEffect = engine?.audioEffectSnapshot() ?? .none
            let sequence = documentStore == nil ? capture.sequence : deckCapture?.sequence
            if let analyzer, sequence != spectrumSequence || isPlaying != spectrumPlaying {
                spectrumSequence = sequence
                spectrumPlaying = isPlaying
                spectrum = analyzer.analyze(interleavedSamples: documentStore == nil ? outputSamples : deckSamples,
                    sampleRate: capture.sampleRate, isPlaying: isPlaying)
            }
        }
        if !isPreparing, diagnostic.isEmpty, snapshot.revision == revision {
            status = isPlaying ? "Live · edit freely" : "Paused"
        }
    }

    var rowMuteStates: [Int: Bool] {
        guard audibleDocumentID == activeDocumentID, controlsAvailable, !isPreparing else { return [:] }
        return Dictionary(uniqueKeysWithValues: (controlCatalog?.descriptors ?? []).compactMap { descriptor in
            guard descriptor.address.parameter == .trackMute,
                  case .track(let id) = descriptor.address.target else { return nil }
            return (id, controlValue(descriptor) == 1)
        })
    }

    func toggleTrackMute(_ id: Int) {
        guard let muted = rowMuteStates[id], let revision = currentRevision else { return }
        do {
            try setControl(.init(revision: revision, target: .track(id), parameter: .trackMute),
                           value: .number(muted ? 0 : 1))
        } catch { hostDiagnostic = error.localizedDescription }
    }

    /// A nil value releases this address back to its score or persistent master target.
    func setControl(_ address: LiveControlAddress, value: LiveControlValue?) throws {
        try setControls([address: value])
    }

    /// Applies one complete score override generation for a knob or XY gesture.
    func setControls(_ updates: [LiveControlAddress: LiveControlValue?]) throws {
        guard !updates.isEmpty else { return }
        guard let currentRevision else { throw EvaluationError.invalidResult("No adopted score.") }
        for address in updates.keys {
            guard address.revision == currentRevision else {
                throw LiveControlError.staleRevision(expected: currentRevision, actual: address.revision)
            }
            guard controlCatalog?.descriptor(for: address) != nil else { throw LiveControlError.unknownAddress(address) }
        }
        if let master = updates.first(where: { $0.key.target == .master }) {
            guard updates.count == 1 else { throw LiveControlError.invalidCatalog("XY pairs require score controls.") }
            try applyMaster(master.key, value: master.value)
            masterControlValues[master.key.parameter] = master.value
            return
        }
        guard performanceTask == nil, performanceTransaction == nil,
              performanceConfirmationTask == nil else {
            throw EvaluationError.invalidResult("Wait for the performance update to become audible.")
        }
        guard controlsAvailable else { throw EvaluationError.invalidResult("Live controls are unavailable. Audio continues.") }
        guard requestedGeneration < UInt64.max else { throw EvaluationError.invalidResult("Control generation limit reached.") }
        var next = overrides
        for (address, value) in updates { next[address] = value }
        overrides = next
        requestedGeneration += 1
        let generation = requestedGeneration
        let values = overrides.map { LiveControlOverride(address: $0.key, value: $0.value) }
        controlTask?.cancel()
        controlTask = Task { [weak self, evaluator] in
            do {
                let rendered = try await evaluator.render(overrides: values, revision: currentRevision, generation: generation)
                try Task.checkCancellation()
                guard let self, self.currentRevision == currentRevision,
                      self.requestedGeneration == generation, let engine = self.engine else { return }
                try engine.replace(loop: rendered, revision: currentRevision, generation: generation)
                self.lastRenderedGeneration = generation
                self.lastRenderedOverrides = Dictionary(uniqueKeysWithValues: values.map { ($0.address, $0.value) })
                self.controlTask = nil
                self.refresh()
            } catch is CancellationError { }
            catch {
                let available = await evaluator.controlsAvailable(revision: currentRevision)
                guard let self, self.currentRevision == currentRevision,
                      self.requestedGeneration == generation else { return }
                self.controlTask = nil
                self.controlTask = nil
                self.controlsAvailable = available
                self.overrides = self.lastRenderedOverrides
                self.diagnostic = error.localizedDescription
            }
        }
    }

    /// Applies one complete performance-model value set. The source and undo stack never change.
    func setPerformanceValue(_ controlID: String, value: PerformanceControlValue, continuous: Bool = false) throws {
        var values = pendingPerformanceIntent?.values ?? activePerformanceIntent?.values
            ?? performanceTransaction?.values ?? performanceValues
        guard values[controlID] != nil else { throw PerformanceControlError.unknownControl(controlID) }
        values[controlID] = value
        try requestPerformanceValues(values, continuous: continuous)
    }

    /// Applies both axes of one declared position control as one performance generation.
    func setPerformancePosition(_ controlID: String, x: Double? = nil, depth: Double? = nil) throws {
        let values = pendingPerformanceIntent?.values ?? activePerformanceIntent?.values
            ?? performanceTransaction?.values ?? performanceValues
        guard case .position(let position) = values[controlID] else {
            throw PerformanceControlError.valueTypeMismatch(controlID)
        }
        try setPerformanceValue(controlID, value: .position(SpatialPosition(
            x: x ?? position.x, depth: depth ?? position.depth)))
    }

    func performanceValue(_ controlID: String) -> PerformanceControlValue? {
        performanceValues[controlID]
    }

    func performanceNumber(_ controlID: String) -> Double? {
        guard case .double(let value) = performanceValues[controlID] else { return nil }
        return value
    }

    func performancePosition(_ controlID: String) -> SpatialPosition? {
        guard case .position(let value) = performanceValues[controlID] else { return nil }
        return value
    }

    var isPerformanceUpdating: Bool {
        performanceTask != nil || performanceTransaction != nil || performanceConfirmationTask != nil
    }

    private func requestPerformanceValues(_ values: [String: PerformanceControlValue], continuous: Bool = false) throws {
        guard !isShuttingDown, !requiresEvaluatorReset else { throw CancellationError() }
        guard let revision = currentRevision, revision == self.revision, !isPreparing else {
            throw EvaluationError.invalidResult("Wait for the current score to finish loading before changing performance controls.")
        }
        guard controlsAvailable, !performanceControlMetadata.isEmpty else {
            throw EvaluationError.invalidResult("Performance controls are unavailable. Audio continues.")
        }
        guard controlTask == nil, lastRenderedGeneration == overrideGeneration else {
            throw EvaluationError.invalidResult("Wait for the current score controls to become audible.")
        }
        try PerformanceControlMetadata.validate(performanceControlMetadata.map { metadata in
            guard let value = values[metadata.controlID] else { return metadata }
            return PerformanceControlMetadata(modelID: metadata.modelID, controlID: metadata.controlID,
                label: metadata.label, domain: metadata.domain, value: value)
        })
        let knownIDs = Set(performanceControlMetadata.map(\.controlID))
        guard Set(values.keys) == knownIDs else {
            let missing = knownIDs.subtracting(values.keys).sorted().first
            let unknown = Set(values.keys).subtracting(knownIDs).sorted().first
            throw missing.map(PerformanceControlError.missingValue) ?? unknown.map(PerformanceControlError.unknownControl)
                ?? PerformanceControlError.invalidMapping("control set is incomplete")
        }
        guard requestedPerformanceGeneration < UInt64.max else {
            throw EvaluationError.invalidResult("Performance generation limit reached.")
        }
        requestedPerformanceGeneration += 1
        let intent = PerformanceIntent(allowsIntermediateAdoption: continuous, revision: revision, generation: requestedPerformanceGeneration, values: values)
        pendingPerformanceIntent = intent
        if performanceTask == nil, performanceTransaction == nil {
            pendingPerformanceIntent = nil
            startPerformance(intent)
        } else if !continuous {
            performanceTask?.cancel()
        }
    }

    private func startPerformance(_ intent: PerformanceIntent) {
        guard performanceTask == nil, performanceTransaction == nil else { return }
        activePerformanceIntent = intent
        status = "Rendering performance update…"
        performanceTask = Task { @MainActor [weak self] in
            await self?.runPerformance(intent)
            self?.performanceTaskFinished(intent.generation)
        }
    }

    private func runPerformance(_ intent: PerformanceIntent) async {
        guard currentRevision == intent.revision, revision == intent.revision, !isPreparing,
              let engine else { return }
        var reservedToken: PerformanceReplacementToken?
        do {
            try Task.checkCancellation()
            let scoreOverrides = lastRenderedOverrides.map { LiveControlOverride(address: $0.key, value: $0.value) }
            let rendered = try await evaluator.renderPerformance(values: intent.values,
                overrides: scoreOverrides, revision: intent.revision, generation: intent.generation)
            try Task.checkCancellation()
            guard currentRevision == intent.revision, revision == intent.revision,
                  (intent.allowsIntermediateAdoption || requestedPerformanceGeneration == intent.generation) else {
                await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
                return
            }
            reservedToken = try engine.preparePerformanceReplacement(loop: rendered.loop,
                revision: intent.revision, generation: intent.generation)
            self.reservedPerformanceToken = reservedToken
            await performanceReservationDidPrepare?()
            try Task.checkCancellation()
            guard !requiresEvaluatorReset, !isShuttingDown else { throw CancellationError() }

            // Once the worker ACK is requested, cancellation cannot abandon the transaction.
            let acknowledged = await evaluator.adoptPerformance(revision: intent.revision, generation: intent.generation)
            guard let token = reservedToken else {
                await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
                return
            }
            guard self.reservedPerformanceToken == token else {
                await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
                return
            }
            guard acknowledged else {
                _ = engine.discardPerformanceReplacement(token)
                self.reservedPerformanceToken = nil
                await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
                throw EvaluationError.invalidResult("The performance worker rejected the requested generation.")
            }
            guard engine.commitPerformanceReplacement(token) else {
                self.reservedPerformanceToken = nil
                controlsAvailable = false
                diagnostic = "The performance replacement reservation expired; edit the score to restore controls."
                return
            }
            self.performanceTransaction = PerformanceTransaction(revision: intent.revision,
                generation: intent.generation, values: intent.values, evaluation: rendered)
            self.status = "Performance update · waiting for fade"
            self.reservedPerformanceToken = nil
            reservedToken = nil
        } catch is CancellationError {
            if let reservedToken {
                _ = engine.discardPerformanceReplacement(reservedToken)
                if self.reservedPerformanceToken == reservedToken { self.reservedPerformanceToken = nil }
            }
            await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
        } catch {
            if let reservedToken {
                _ = engine.discardPerformanceReplacement(reservedToken)
                if self.reservedPerformanceToken == reservedToken { self.reservedPerformanceToken = nil }
            }
            await evaluator.discardPerformance(revision: intent.revision, generation: intent.generation)
            guard currentRevision == intent.revision, revision == intent.revision,
                  requestedPerformanceGeneration == intent.generation else { return }
            diagnostic = error.localizedDescription
            if case EvaluationError.compilerDiagnostic(_, let range) = error,
               adoptedSourceDigest == DocumentHostStateStore.sourceDigest(source) {
                diagnosticRange = range?.utf16Range
            }
            status = "Performance update failed · previous loop continues"
        }
    }

    private func performanceTaskFinished(_ generation: UInt64) {
        guard activePerformanceIntent?.generation == generation else { return }
        activePerformanceIntent = nil
        performanceTask = nil
        guard performanceTransaction == nil else { return }
        guard let pending = pendingPerformanceIntent, pending.generation == requestedPerformanceGeneration else {
            resumeDeferredEvaluationIfPossible()
            return
        }
        pendingPerformanceIntent = nil
        startPerformance(pending)
    }

    private func finishPerformanceConfirmation(revision: UInt64, generation: UInt64, confirmed: Bool) {
        guard let transaction = performanceTransaction,
              transaction.revision == revision, transaction.generation == generation else { return }
        performanceConfirmationTask = nil
        guard confirmed else {
            performanceTransaction = nil
            controlsAvailable = false
            diagnostic = "The performance worker and playback snapshot disagreed; controls remain unavailable."
            status = "Performance update could not be confirmed · previous values retained"
            resumeDeferredEvaluationIfPossible()
            return
        }
        let previousLoop = loop
        let previousCatalog = controlCatalog
        let previousPerformanceControls = performanceControlMetadata
        let previousPerformanceValues = performanceValues
        let nextLoop = transaction.evaluation.loop
        let nextPerformanceControls = transaction.evaluation.performanceControls
        performanceControlMetadata = nextPerformanceControls
        performanceValues = Dictionary(uniqueKeysWithValues: nextPerformanceControls.map { ($0.controlID, $0.value) })
        let nextCatalog: LiveControlCatalog
        do {
            nextCatalog = try catalogWithMasters(transaction.evaluation.catalog, revision: revision)
        } catch {
            performanceControlMetadata = previousPerformanceControls
            performanceValues = previousPerformanceValues
            performanceTransaction = nil
            controlsAvailable = false
            diagnostic = error.localizedDescription
            status = "Performance update could not be confirmed · previous values retained"
            return
        }
        let graphChanged = !controlLayoutMatches(previousCatalog, nextCatalog)
            || !rowProvenanceMatches(previousLoop, nextLoop)
        loop = nextLoop
        if adoptedSourceDigest == DocumentHostStateStore.sourceDigest(source) {
            lineMaps[revision] = SourceLineMap(source: source,
                lines: nextLoop.rows.flatMap { [$0.anchor?.line, $0.resultLine].compactMap { $0 } })
        }
        controlCatalog = nextCatalog
        candidateCatalogs[revision] = transaction.evaluation.catalog
        candidateMetadata[revision] = transaction.evaluation.metadata
        completionSource = source
        completionSites = adoptedSourceDigest == DocumentHostStateStore.sourceDigest(source)
            ? transaction.evaluation.metadata.completionSites : []
        candidatePerformanceControls[revision] = nextPerformanceControls
        candidatePerformanceTransferIssues.removeValue(forKey: revision)
        if graphChanged {
            overrides.removeAll()
            lastRenderedOverrides.removeAll()
            lastRenderedGeneration = overrideGeneration
            reconcilePerformanceHandles(after: nextCatalog)
        }
        updateRowLines()
        publishedPerformanceGeneration = generation
        performanceTransaction = nil
        requestControlVisualization()
        refresh()
        status = isPlaying ? "Live · edit freely" : "Paused"
        if let pending = pendingPerformanceIntent {
            pendingPerformanceIntent = nil
            startPerformance(pending)
        } else {
            resumeDeferredEvaluationIfPossible()
        }
    }

    private func controlLayoutMatches(_ previous: LiveControlCatalog?, _ next: LiveControlCatalog) -> Bool {
        guard let previous, previous.descriptors.count == next.descriptors.count else { return false }
        return zip(previous.descriptors, next.descriptors).allSatisfy { old, new in
            old.address == new.address && old.label == new.label
        }
    }

    private func rowProvenanceMatches(_ previous: PreparedLoop?, _ next: PreparedLoop) -> Bool {
        guard let previous, previous.rows.count == next.rows.count else { return false }
        return zip(previous.rows, next.rows).allSatisfy { old, new in
            old.sourceID == new.sourceID
                && old.label == new.label
                && old.anchor == new.anchor
                && old.patternText == new.patternText
                && old.resultLine == new.resultLine
        }
    }

    private func reconcilePerformanceHandles(after catalog: LiveControlCatalog) {
        if let selectedControl,
           selectedControl.target != .master || catalog.descriptor(for: selectedControl) == nil {
            self.selectedControl = nil
        }
        xyX = nil
        xyY = nil
        let previousBindingCount = learnedBindings.count
        learnedBindings.removeAll { binding in
            binding.address.target != .master || catalog.descriptor(for: binding.address) == nil
        }
        if previousBindingCount != learnedBindings.count {
            hostDiagnostic = "MIDI Learn bindings were detached after the performance graph changed."
        }
        if let learnAddress,
           learnAddress.target != .master || catalog.descriptor(for: learnAddress) == nil {
            self.learnAddress = nil
        }
        controlVisualization = nil
        visualizationStatus = "Choose a score control to inspect its trajectories."
    }

    private func resumeDeferredEvaluationIfPossible() {
        guard deferredEvaluation, performanceTask == nil, performanceTransaction == nil,
              performanceConfirmationTask == nil else { return }
        let immediate = deferredEvaluationImmediate
        deferredEvaluation = false
        deferredEvaluationImmediate = false
        if requiresEvaluatorReset {
            deferredEvaluation = true
            deferredEvaluationImmediate = immediate
            guard evaluatorResetTask == nil else { return }
            evaluatorResetTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.evaluationTask?.value
                await self.controlTask?.value
                await self.adoptionTask?.value
                do { try await self.evaluator.shutdown() }
                catch {
                    self.diagnostic = error.localizedDescription
                    self.evaluatorResetTask = nil
                    self.deferredEvaluation = false
                    return
                }
                self.requiresEvaluatorReset = false
                self.evaluatorResetTask = nil
                guard !self.isShuttingDown else { return }
                self.resumeDeferredEvaluationIfPossible()
            }
            return
        }
        scheduleEvaluation(immediate: immediate)
    }

    private func catalogWithMasters(_ catalog: LiveControlCatalog, revision: UInt64) throws -> LiveControlCatalog {
        let hasPerformanceBPM = performanceControlMetadata.contains { metadata in
            if case .double(_, let role) = metadata.domain { return role == .beatsPerMinute }
            return false
        }
        let masters: [(LiveControlParameter, String, LiveControlBaseline)] = [
            (.lowPassCutoff, "Master Filter", lowPass >= 19_999 ? .bypassed : .scalar(lowPass)),
            (.delayMix, "Master Delay", .scalar(delayMix)),
            (.reverbMix, "Master Reverb", .scalar(reverbMix))
        ]
        let tempo: [(LiveControlParameter, String, LiveControlBaseline)] = hasPerformanceBPM
            ? [] : [(.playbackRate, "Master Tempo", .scalar(masterBPM / (loop?.bpm ?? 120)))]
        return try LiveControlCatalog(descriptors: catalog.descriptors + (tempo + masters).map {
            LiveControlDescriptor(address: .init(revision: revision, target: .master, parameter: $0.0),
                                  label: $0.1, baseline: $0.2,
                                  presentation: try .suggested(for: $0.0))
        })
    }

    private func applyMaster(_ address: LiveControlAddress, value: LiveControlValue?) throws {
        guard let engine else { throw EvaluationError.invalidResult(audioError) }
        let number: Double?
        switch value {
        case .number(let scalar):
            guard scalar.isFinite else { throw LiveControlError.invalidValue(address) }
            number = scalar
        case .bypassed:
            guard address.parameter == .lowPassCutoff else { throw LiveControlError.invalidValue(address) }
            number = nil
        case nil: number = nil
        }
        switch address.parameter {
        case .playbackRate: try engine.setPlaybackRate(Float(number ?? masterBPM / (loop?.bpm ?? 120)))
        case .lowPassCutoff:
            let cutoff = value == .bypassed ? nil : (number ?? (lowPass >= 19_999 ? nil : lowPass))
            try engine.setLowPass(cutoff: cutoff.map(Float.init))
        case .delayMix: try engine.setDelay(mix: Float(number ?? delayMix))
        case .reverbMix: try engine.setReverb(mix: Float(number ?? reverbMix))
        default: throw LiveControlError.unsupportedAddress(address)
        }
    }

    var activeTokens: [Int: Set<Int>] {
        guard audibleDocumentID == activeDocumentID else { return [:] }
        guard isPlaying, let loop else { return [:] }
        var tokens: [Int: Set<Int>] = [:]
        for event in loop.events where event.gain > 0 && event.isActive(at: beatPosition, in: loop.beatCount) {
            if let index = event.patternStepIndex { tokens[event.sourceID, default: []].insert(index) }
        }
        return tokens
    }

    var inlineSliders: [SliderDefinition] {
        guard audibleDocumentID == activeDocumentID, let currentRevision,
              adoptedSourceDigest == DocumentHostStateStore.sourceDigest(source) else { return [] }
        return (candidateMetadata[currentRevision]?.sliders ?? []).filter {
            $0.fileID == "Session.swift" || $0.fileID.hasSuffix("/Session.swift")
        }
    }

    var inlineSliderValues: [String: Double] {
        let values = pendingPerformanceIntent?.values ?? activePerformanceIntent?.values
            ?? performanceTransaction?.values ?? performanceValues
        return values.reduce(into: [:]) { result, item in
            if case .double(let value) = item.value { result[item.key] = value }
        }
    }

    func setInlineSlider(_ id: String, value: Double) {
        do { try setPerformanceValue(id, value: .double(value), continuous: true) }
        catch { hostDiagnostic = error.localizedDescription }
    }

    func beforeEdit(range: NSRange, replacement: String) {
        diagnosticRange = nil
        selectionRange = nil
        if source != completionSource || range.location < 0 || range.length < 0 || range.location > source.utf16.count
            || range.length > source.utf16.count - range.location {
            completionSites = []
            completionSource = ""
        } else {
            completionSource = (source as NSString).replacingCharacters(in: range, with: replacement)
        }
        let delta = replacement.utf16.count - range.length
        completionSites = completionSites.compactMap { site in
            var content = site.contentRange
            if range.location >= content.location, NSMaxRange(range) <= NSMaxRange(content),
                    !replacement.contains(where: { $0 == "\"" || $0 == "\\" || $0.isNewline }) {
                content.length += delta
            } else { return nil }
            guard content.length >= 0 else { return nil }
            do { return try .init(sourceID: site.sourceID, contentRange: content, values: site.values) }
            catch { hostDiagnostic = error.localizedDescription; return nil }
        }
        for key in Array(lineMaps.keys) { lineMaps[key]?.applyEdit(range: range, replacement: replacement) }
    }

    private func updateRowLines() {
        rowLines = [:]
        resultLines = [:]
        guard audibleDocumentID == activeDocumentID, let loop, let currentRevision, let map = lineMaps[currentRevision] else { return }
        for row in loop.rows {
            guard let anchor = row.anchor,
                  anchor.fileID == "Session.swift" || anchor.fileID.hasSuffix("/Session.swift") else { continue }
            if let line = map.currentLine(for: anchor.line, in: source) { rowLines[row.sourceID] = line }
            if let end = row.resultLine, let result = map.currentLine(for: end, in: source) {
                resultLines[row.sourceID] = result
            }
        }
    }

    func revealDiagnostic() {
        guard let diagnosticRange else { return }
        selectionRange = diagnosticRange
        selectionToken += 1
    }

    func revealTrack(_ name: String) {
        selectionRange = nil
        let literal = "Track(\"\(name)\""
        guard let range = source.range(of: literal) else { return }
        selectionLine = source[..<range.lowerBound].filter { $0 == "\n" }.count + 1
        selectionToken += 1
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at root: URL, resolveDependencies: Bool = false) {
        if resolveDependencies { evaluationTask?.cancel(); isPreparing = false }
        let retainedTarget = project?.root == root ? projectTarget?.name : nil
        projectTask?.cancel()
        let request = UUID()
        projectRequestID = request
        isOpeningPackage = true
        preparationProgress = "Loading package…"
        status = "Opening package…"
        projectTask = Task {
            defer { if projectRequestID == request { isOpeningPackage = false } }
            do {
                let manifest = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
                let loaded = try await evaluator.openProject(at: root, resolveDependencies: resolveDependencies, progress: { [weak self] message in
                    await MainActor.run {
                        guard let self, self.projectRequestID == request else { return }
                        self.preparationProgress = message
                    }
                })
                try Task.checkCancellation()
                guard projectRequestID == request else { return }
                let listing = SessionFileBrowser()
                try listing.load(loaded.root)
                let selectedPath = UserDefaults.standard.string(forKey: "project.selected." + deckIdentity + loaded.root.path)
                let restored = UserDefaults.standard.stringArray(forKey: "project.tabs." + deckIdentity + loaded.root.path) ?? []
                let savedEntry = UserDefaults.standard.string(forKey: "deck.entry." + deckIdentity + loaded.root.path)
                let defaultEntry = deckIdentity == "B" && loaded.targets[0].sources.contains("Trance.swift")
                    ? loaded.root.appending(path: loaded.targets[0].path).appending(path: "Trance.swift")
                    : loaded.entryURL(for: loaded.targets[0])
                let entry = savedEntry.flatMap { path -> URL? in
                    let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                    return loaded.targets.contains { target in target.sources.contains { loaded.root.appending(path: target.path).appending(path: $0) == url } } ? url : nil
                } ?? defaultEntry
                var requestedURLs = restored.filter { $0.hasPrefix(loaded.root.path + "/") && FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
                if !requestedURLs.contains(entry) { requestedURLs.append(entry) }
                var newDocuments: [SessionDocument] = []
                for url in requestedURLs where !documents.contains(where: { $0.fileURL == url }) {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    guard text.utf8.count <= 65_536 else { throw EvaluationError.invalidSource("Source exceeds 64 KiB.") }
                    newDocuments.append(try documentStore?.open(url) ?? SessionDocument(source: text, fileURL: url))
                }
                guard documents.count + newDocuments.count <= Self.maximumOpenDocuments else { throw DocumentFailure.tabLimit }
                if let sources = listing.entries.first(where: { $0.url.lastPathComponent == "Sources" }) {
                    try listing.toggle(sources)
                    for target in loaded.targets {
                        if let item = listing.entries.first(where: { $0.url.resolvingSymlinksInPath().path == loaded.root.appending(path: target.path).resolvingSymlinksInPath().path }) { try listing.toggle(item) }
                    }
                }
                let nextCompletion = await completionService.projectService(root: loaded.root)
                try Task.checkCancellation()
                guard projectRequestID == request else { try await nextCompletion.shutdown(); return }
                if let projectCompletion { try await projectCompletion.shutdown() }
                try Task.checkCancellation()
                guard projectRequestID == request else { try await nextCompletion.shutdown(); return }
                newDocuments.removeAll { candidate in documents.contains { $0.fileURL == candidate.fileURL } }
                guard documents.count + newDocuments.count <= Self.maximumOpenDocuments else { throw DocumentFailure.tabLimit }
                rememberProjectNavigation()
                projectCompletion = nextCompletion
                project = loaded
                loadedManifest = manifest
                projectTarget = loaded.targets.first(where: { $0.name == retainedTarget }) ?? loaded.targets.first
                fileBrowser = listing
                documents.append(contentsOf: newDocuments)
                let selected = selectedPath.flatMap { path in documents.first(where: { $0.fileURL?.path == path }) }
                    ?? documents.first(where: { $0.fileURL == entry })
                if loadedDocument?.fileURL != entry { loadHostSettings(for: entry) }
                loadedDocument = documents.first { $0.fileURL == entry }
                if let target = loaded.targets.first(where: { entry.path.hasPrefix(loaded.root.appending(path: $0.path).path + "/") }) {
                    projectTarget = try target.selectingEntry(String(entry.path.dropFirst(loaded.root.appending(path: target.path).path.count + 1)))
                }
                loadedType = UserDefaults.standard.string(forKey: "deck.type." + deckIdentity + loaded.root.path) ?? (entry.lastPathComponent == "Trance.swift" ? "Trance" : "Session")
                if let selected { selectDocument(selected.id) }
                scheduleEvaluation(immediate: true)
            } catch is CancellationError { }
            catch { fileBrowser.errorMessage = error.localizedDescription; diagnostic = error.localizedDescription }
        }
    }

    private func rememberProjectNavigation() {
        guard let root = project?.root else { return }
        let paths = documents.filter { !$0.isReadOnly }.compactMap(\.fileURL).filter { $0.path.hasPrefix(root.path + "/") }.map(\.path)
        UserDefaults.standard.set(paths, forKey: "project.tabs." + deckIdentity + root.path)
        if let loadedDocument, let url = loadedDocument.fileURL {
            UserDefaults.standard.set(url.path, forKey: "deck.entry." + deckIdentity + root.path)
            UserDefaults.standard.set(loadedType, forKey: "deck.type." + deckIdentity + root.path)
        }
        if isProjectDocument { UserDefaults.standard.set(fileURL?.path, forKey: "project.selected." + deckIdentity + root.path) }
    }

    func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = "MyLiveSet"
        panel.prompt = "Create"
        guard panel.runModal() == .OK, let root = panel.url else { return }
        do {
            try Self.createProject(at: root)
            openProject(at: root)
        } catch {
            fileBrowser.errorMessage = error.localizedDescription
            NSAlert(error: error).runModal()
        }
    }

    static func createProject(at root: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: root.path) else { throw SessionFileBrowser.Failure.fileExists }
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let name = String(reflecting: root.lastPathComponent)
            let sources = root.appending(path: "Sources").appending(path: root.lastPathComponent)
            try manager.createDirectory(at: sources.appending(path: "Resources"), withIntermediateDirectories: true)
            try manager.createDirectory(at: root.appending(path: "Recordings"), withIntermediateDirectories: false)
            let manifest = """
            // swift-tools-version: 6.4

            import PackageDescription

            let package = Package(
                name: \(name),
                platforms: [
                    .macOS(.v15)
                ],
                products: [
                    .library(
                        name: \(name),
                        targets: [\(name)]
                    )
                ],
                dependencies: [
                    .package(
                        url: "https://github.com/1amageek/SwiftMusic.git",
                        exact: "0.5.0"
                    )
                ],
                targets: [
                    .target(
                        name: \(name),
                        dependencies: [
                            .product(
                                name: "SwiftMusic",
                                package: "SwiftMusic"
                            )
                        ],
                        resources: [
                            .copy("Resources")
                        ]
                    )
                ]
            )

            """
            try manifest.write(to: root.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
            try initialSource.write(to: sources.appending(path: "Session.swift"), atomically: true, encoding: .utf8)
            try tranceSource.write(to: sources.appending(path: "Trance.swift"), atomically: true, encoding: .utf8)
            try "Place sample files here. Access them with Bundle.module.\n".write(to: sources.appending(path: "Resources/README.txt"), atomically: true, encoding: .utf8)
            try ".build/\n.swiftpm/\n.DS_Store\nRecordings/\n".write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        } catch {
            let original = error
            do { try manager.removeItem(at: root) }
            catch { throw EvaluationError.invalidResult("Project creation failed: \(original); cleanup failed: \(error)") }
            throw original
        }
    }

    func selectProjectTarget(_ target: SwiftPackageProject.Target) {
        guard let project else { return }
        projectTarget = target
        do {
            try openDocument(at: project.entryURL(for: target))
            scheduleEvaluation(immediate: true)
        } catch { diagnostic = error.localizedDescription }
    }

    func newProjectFile() {
        guard let project, let target = projectTarget else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.swiftSource]
        panel.nameFieldStringValue = "Sound.swift"
        panel.directoryURL = project.root.appending(path: target.path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard url.standardizedFileURL.path.hasPrefix(project.root.path + "/") else {
                throw EvaluationError.invalidSource("Create the file inside the project.")
            }
            try fileBrowser.create(at: url, source: "import SwiftMusic\n")
            try fileBrowser.refresh()
            try openDocument(at: url)
        } catch { fileBrowser.errorMessage = error.localizedDescription }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.swiftSource, .plainText]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try openDocument(at: url) }
        catch { diagnostic = error.localizedDescription }
    }

    enum DocumentFailure: LocalizedError {
        case tabLimit, duplicateDestination
        var errorDescription: String? {
            switch self {
            case .tabLimit: "Close a tab before opening another. The limit is 32 documents."
            case .duplicateDestination: "This file is already open in another tab."
            }
        }
    }

    func openDocument(at url: URL, readOnly: Bool = false) throws {
        let identity = url.standardizedFileURL.resolvingSymlinksInPath()
        if let document = documents.first(where: { $0.fileURL == identity }) {
            selectDocument(document.id)
            return
        }
        guard documents.count < Self.maximumOpenDocuments else { throw DocumentFailure.tabLimit }
        let text = try String(contentsOf: identity, encoding: .utf8)
        guard text.utf8.count <= 65_536 else { throw EvaluationError.invalidSource("Source exceeds 64 KiB.") }
        let document = try documentStore?.open(identity, readOnly: readOnly) ?? SessionDocument(source: text, fileURL: identity, isReadOnly: readOnly)
        documents.append(document)
        selectDocument(document.id)
    }

    func selectDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }), index != activeDocumentIndex else { return }
        let sameProject = isProjectManifest(documents[index]) || (isProjectDocument && (documents[index].isReadOnly || documents[index].fileURL.map { $0.path.hasPrefix(project!.root.path + "/") } == true))
        if !sameProject && documentStore == nil { abortPerformanceForDocumentChange() }
        activeDocumentIndex = index
        if !sameProject { lineMaps = [:] }
        rowLines = [:]
        resultLines = [:]
        completionSites = []
        completionSource = ""
        completionStatus = ""
        if documentStore == nil { diagnostic = "" }
        selectionRange = nil
        selectionLine = nil
        controlVisualization = nil
        visualizationTask?.cancel()
        if !sameProject && documentStore == nil {
            loadHostSettings(for: fileURL)
            scheduleEvaluation(immediate: true)
        }
        updateRowLines()
        rememberProjectNavigation()
    }

    enum CloseDecision { case save, cancel, discard }

    func closeDecision(for document: SessionDocument) -> CloseDecision {
        let alert = NSAlert()
        alert.messageText = "Save changes to \(document.name)?"
        alert.informativeText = "Your unsaved Swift code will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }

    @discardableResult
    func closeDocument(_ id: UUID, decision: CloseDecision? = nil) -> Bool {
        guard let document = documents.first(where: { $0.id == id }) else { return true }
        let affectsProject = document.isDirty && document.fileURL.map { url in
            project.map { url.path.hasPrefix($0.root.path + "/") } ?? false
        } == true
        if document.isDirty {
            switch decision ?? closeDecision(for: document) {
            case .save: guard saveDocument(document) else { return false }
            case .cancel: return false
            case .discard:
                if documentStore != nil, let url = document.fileURL {
                    do {
                        document.source = try String(contentsOf: url, encoding: .utf8)
                        document.isDirty = false
                        documentStore?.sourceDidChange?(document)
                    } catch { diagnostic = error.localizedDescription; return false }
                }
            }
        }
        let wasActive = id == activeDocumentID
        let retainedID = activeDocumentID
        if documents.count == 1 { documents.append(SessionDocument(source: Self.initialSource)) }
        if wasActive, let replacement = documents.first(where: { $0.id != id && ($0.fileURL != nil || $0.isDirty) })
            ?? documents.first(where: { $0.id != id }) { selectDocument(replacement.id) }
        let selectedID = wasActive ? activeDocumentID : retainedID
        documents.removeAll { $0.id == id }
        documentStore?.membershipDidChange?()
        activeDocumentIndex = documents.firstIndex { $0.id == selectedID } ?? 0
        rememberProjectNavigation()
        if affectsProject { scheduleEvaluation(immediate: true) }
        return true
    }

    func confirmAllDocuments(decision: ((SessionDocument) -> CloseDecision)? = nil) -> Bool {
        let retained = documents + [loadedDocument].compactMap { value in
            value.flatMap { document in documents.contains(where: { $0.id == document.id }) ? nil : document }
        }
        for document in retained where document.isDirty {
            switch decision?(document) ?? closeDecision(for: document) {
            case .save: guard saveDocument(document) else { return false }
            case .cancel: return false
            case .discard: break
            }
        }
        return true
    }

    private func abortPerformanceForDocumentChange() {
        requiresEvaluatorReset = true
        evaluationTask?.cancel()
        controlTask?.cancel()
        adoptionTask?.cancel()
        if let reservedPerformanceToken {
            _ = engine?.discardPerformanceReplacement(reservedPerformanceToken)
            self.reservedPerformanceToken = nil
        }
        performanceTask?.cancel()
        performanceConfirmationTask?.cancel()
        performanceConfirmationTask = nil
        pendingPerformanceIntent = nil
        performanceTransaction = nil
        controlsAvailable = false
    }

    @discardableResult func saveDocument() -> Bool { saveDocument(activeDocument) }

    @discardableResult
    func saveDocument(_ document: SessionDocument, to url: URL? = nil) -> Bool {
        guard !document.isReadOnly else { return false }
        var destination = url ?? document.fileURL
        if destination == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Session.swift"
            panel.allowedContentTypes = [.swiftSource]
            guard panel.runModal() == .OK else { return false }
            destination = panel.url
        }
        guard let destination = destination?.standardizedFileURL.resolvingSymlinksInPath() else { return false }
        do {
            guard !documents.contains(where: { $0.id != document.id && $0.fileURL == destination }) else { throw DocumentFailure.duplicateDestination }
            try documentStore?.validateSave(document, to: destination)
            let isManifest = project?.root.appending(path: "Package.swift") == destination
            let unchanged: Bool
            if isManifest, FileManager.default.fileExists(atPath: destination.path) {
                unchanged = try String(contentsOf: destination, encoding: .utf8) == document.source
            } else {
                unchanged = false
            }
            if !unchanged { try document.source.write(to: destination, atomically: true, encoding: .utf8) }
            document.fileURL = destination
            documentStore?.didSave(document)
            if documentStore == nil ? document.id == activeDocumentID : document.id == audibleDocumentID { try saveHostSettings(for: destination) }
            document.isDirty = false
            if let root = project?.root, isManifest, document.source != loadedManifest {
                rememberProjectNavigation()
                openProject(at: root, resolveDependencies: true)
                documentStore?.manifestDidSave?(self, root)
            }
            return true
        } catch { diagnostic = error.localizedDescription; return false }
    }

    func confirmDiscard() -> Bool {
        guard activeDocument.isDirty else { return true }
        switch closeDecision(for: activeDocument) {
        case .save: return saveDocument()
        case .cancel: return false
        case .discard: return true
        }
    }

    func configureMIDI(_ route: MIDISessionRoute) async throws {
        guard !midiClosed else { throw MIDIError.serviceShutDown }
        guard !midiConfigurationInProgress else {
            throw MIDIError.invalidLoop("MIDI route configuration is already in progress")
        }
        try route.validate()
        if route == .disabled, midiService == nil { return }
        midiConfigurationInProgress = true
        defer { midiConfigurationInProgress = false }
        if midiService == nil { midiService = try CoreMIDIService() }
        guard let service = midiService else { throw MIDIError.serviceShutDown }
        let endpoints = try await service.enumerateEndpoints()
        for input in route.inputIDs {
            guard endpoints.contains(where: { $0.id == input && $0.direction == .input }) else {
                throw MIDIError.endpointNotFound(input)
            }
        }
        if let output = route.output {
            guard endpoints.contains(where: { $0.id == output && $0.direction == .output }) else {
                throw MIDIError.endpointNotFound(output)
            }
        }
        let previous = midiRoute
        midiSchedulingTask?.cancel()
        await midiSchedulingTask?.value
        midiSchedulingTask = nil
        do {
            try await applyMIDIRoute(route, replacing: previous, service: service)
            try Task.checkCancellation()
            guard !midiClosed else { throw MIDIError.serviceShutDown }
            if route.input != nil { try await startMIDIEvents() }
            midiRoute = route
            if previous.clockMode != route.clockMode { lastMIDICommandGeneration = 0 }
            startMIDIScheduling()
        } catch {
            let original = error
            if !midiClosed {
                do { try await applyMIDIRoute(previous, replacing: route, service: service) }
                catch {
                    diagnostic = "MIDI route failed: \(original). Restoring the previous route also failed: \(error)"
                }
                startMIDIScheduling()
            }
            throw original
        }
    }

    private func applyMIDIRoute(_ route: MIDISessionRoute, replacing previous: MIDISessionRoute,
                               service: any MIDIServiceProtocol) async throws {
        for id in previous.inputIDs.subtracting(route.inputIDs) { try await service.disconnectInput(id) }
        for id in route.inputIDs.subtracting(previous.inputIDs) { try await service.connectInput(id) }
        try await service.setOutput(route.output)
        try await service.setClockMode(route.clockMode)
    }

    private func startMIDIScheduling() {
        guard midiRoute != .disabled, !midiClosed, midiSchedulingTask == nil else { return }
        midiSchedulingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.updateMIDI()
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch is CancellationError { return }
                catch { self.diagnostic = error.localizedDescription; return }
            }
        }
    }

    /// Runs the same bounded step for the owned task and focused session tests.
    func updateMIDI(clockAnchor: PlaybackClockAnchor? = nil, hostTime: UInt64? = nil) async {
        guard let service = midiService, !midiClosed else { return }
        do {
            let anchor: PlaybackClockAnchor?
            do { anchor = try clockAnchor ?? engine?.playbackClockAnchor() }
            catch PlaybackClockError.unavailable { anchor = nil }
            await service.updateClockAnchor(anchor)
            if let anchor, anchor.isPlaying, let loop = engine?.snapshot().loop {
                let now = hostTime ?? mach_absolute_time()
                // A future presentation anchor is itself a valid scheduling origin.
                // Do not query a negative audible beat or clamp a failed conversion.
                let start = now < anchor.presentationHostTime
                    ? anchor.accumulatedBeatPosition : try anchor.beat(atHostTime: now)
                let end = start + anchor.beatsPerMinute / 60 * 0.1
                if midiRoute.sendsLoopNotes {
                    try await service.schedule(loop: loop, from: start, through: end, channel: midiRoute.channel)
                }
                if case .send = midiRoute.clockMode {
                    try await service.scheduleClock(from: start, through: end)
                }
            }
            let snapshot = await service.snapshot()
            midiSnapshot = snapshot
            applyReceivedMIDIClock(snapshot)
            if lastMIDIHealth != snapshot.clockHealth {
                lastMIDIHealth = snapshot.clockHealth
                switch snapshot.clockHealth {
                case .disconnected: diagnostic = "The selected MIDI endpoint disconnected. Audio continues."
                case .failed(let message): diagnostic = "MIDI: \(message)"
                default: break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            let health = MIDIClockHealth.failed(error.localizedDescription)
            if lastMIDIHealth != health {
                lastMIDIHealth = health
                diagnostic = "MIDI: \(error.localizedDescription)"
            }
        }
    }

    private func applyReceivedMIDIClock(_ snapshot: MIDIServiceSnapshot) {
        guard case .receive = midiRoute.clockMode, let clock = snapshot.receivedClock else { return }
        if let tempo = clock.estimatedBPM, tempo.isFinite, (40...240).contains(tempo), tempo != bpm {
            bpm = tempo
        }
        guard clock.commandGeneration > lastMIDICommandGeneration else { return }
        lastMIDICommandGeneration = clock.commandGeneration
        do {
            switch clock.lastCommand {
            case .start:
                wantsPlayback = true
                if loop == nil { scheduleEvaluation(immediate: true) }
                else { try engine?.restartFromBeginning() }
            case .continue:
                wantsPlayback = true
                if loop == nil { scheduleEvaluation(immediate: true) }
                else { try engine?.play() }
            case .stop:
                wantsPlayback = false
                engine?.stop()
            default: break
            }
            refresh()
        } catch { diagnostic = error.localizedDescription }
    }

    func startRecording(to destination: URL, maximumDuration: Duration) throws {
        guard !isShuttingDown else { throw CancellationError() }
        guard let engine else { throw MasterRecordingError.notRecording }
        try engine.startRecording(MasterRecordingRequest(destination: destination, maximumDuration: maximumDuration))
        isRecording = true
    }

    func stopRecording() async throws -> MasterRecordingResult {
        guard let engine else { throw MasterRecordingError.notRecording }
        defer { isRecording = engine.isRecording }
        return try await engine.stopRecording()
    }

    func cancelRecording() async throws {
        defer { isRecording = engine?.isRecording ?? false }
        try await engine?.cancelRecording()
    }

    func exportStems(to destination: URL) async throws -> StemExportSnapshot {
        guard !isShuttingDown else { throw CancellationError() }
        guard stemExportTask == nil else { throw EvaluationError.invalidResult("A stem export is already in progress.") }
        refresh()
        guard let currentRevision, controlsAvailable,
              lastRenderedGeneration == overrideGeneration else {
            throw EvaluationError.invalidResult("Wait for the current live controls to be adopted before exporting stems.")
        }
        let generation = overrideGeneration
        let values = lastRenderedOverrides.map { LiveControlOverride(address: $0.key, value: $0.value) }
        let task = Task { [evaluator] in
            try await evaluator.exportStems(revision: currentRevision, generation: generation,
                overrides: values, destination: destination)
        }
        let id = UUID()
        stemExportID = id
        stemExportTask = task
        isExportingStems = true
        defer {
            if stemExportID == id { stemExportTask = nil; isExportingStems = false }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func cancelStemExport() async throws {
        guard let task = stemExportTask else { return }
        let id = stemExportID
        task.cancel()
        defer {
            if stemExportID == id { stemExportTask = nil; isExportingStems = false }
        }
        do { _ = try await task.value }
        catch is CancellationError { return }
    }

    func shutdown() async throws {
        isShuttingDown = true
        projectRequestID = UUID()
        projectTask?.cancel()
        await projectTask?.value
        rememberProjectNavigation()
        switchTask?.cancel()
        await switchTask?.value
        if let reservedPerformanceToken {
            _ = engine?.discardPerformanceReplacement(reservedPerformanceToken)
            self.reservedPerformanceToken = nil
        }
        await evaluatorResetTask?.value
        visualizationTask?.cancel()
        await visualizationTask?.value
        hostRestoreTask?.cancel()
        effectTask?.cancel()
        midiEventTask?.cancel()
        await hostRestoreTask?.value
        if let effectTask {
            do { try await effectTask.value }
            catch is CancellationError { }
            catch { hostDiagnostic = error.localizedDescription }
        }
        var recordingFailure: Error?
        do { try await cancelRecording() }
        catch { recordingFailure = error; diagnostic = error.localizedDescription }
        do { try await cancelStemExport() }
        catch {
            diagnostic = recordingFailure.map { "\($0.localizedDescription)\n\(error.localizedDescription)" } ?? error.localizedDescription
            if recordingFailure == nil { recordingFailure = error }
        }
        performanceTask?.cancel()
        if let reservedPerformanceToken {
            _ = engine?.discardPerformanceReplacement(reservedPerformanceToken)
            self.reservedPerformanceToken = nil
        }
        await performanceTask?.value
        performanceConfirmationTask?.cancel()
        await performanceConfirmationTask?.value
        performanceTask = nil
        performanceConfirmationTask = nil
        pendingPerformanceIntent = nil
        performanceTransaction = nil
        deferredEvaluation = false
        midiClosed = true
        midiSchedulingTask?.cancel()
        await midiSchedulingTask?.value
        midiSchedulingTask = nil
        engine?.stop()
        if let midiService {
            do { await midiService.updateClockAnchor(try engine?.playbackClockAnchor()) }
            catch { diagnostic = error.localizedDescription }
            await midiService.shutdown()
        }
        await midiEventTask?.value
        evaluationTask?.cancel()
        controlTask?.cancel()
        adoptionTask?.cancel()
        controlHealthTask?.cancel()
        controlsAvailable = false
        engine?.stop()
        await evaluationTask?.value
        await controlTask?.value
        await adoptionTask?.value
        await controlHealthTask?.value
        projectTask?.cancel()
        if let projectCompletion { try await projectCompletion.shutdown() }
        async let completionShutdown: Void = completionService.shutdown()
        async let evaluationShutdown: Void = evaluator.shutdown()
        _ = try await (completionShutdown, evaluationShutdown)
        if let recordingFailure { throw recordingFailure }
    }

    private func requestControlVisualization() {
        visualizationTask?.cancel()
        controlVisualization = nil
        guard selectionGeneration < UInt64.max else {
            visualizationStatus = "Selection generation limit reached. Reopen the app."
            return
        }
        selectionGeneration += 1
        let selection = selectionGeneration
        guard let address = selectedControl, let currentRevision, address.revision == currentRevision,
              controlsAvailable, overrideGeneration == lastRenderedGeneration else {
            visualizationStatus = "Waiting for an adopted score control."
            return
        }
        guard address.target != .master else {
            visualizationStatus = "Master controls use the live output monitor."
            return
        }
        let generation = overrideGeneration
        let values = lastRenderedOverrides.map { LiveControlOverride(address: $0.key, value: $0.value) }
        visualizationStatus = "Loading control trajectories…"
        visualizationTask = Task { [weak self, evaluator] in
            do {
                let result = try await evaluator.visualization(address: address, overrides: values,
                    revision: currentRevision, selectionGeneration: selection)
                try Task.checkCancellation()
                guard let self, self.selectionGeneration == selection, self.currentRevision == currentRevision,
                      self.overrideGeneration == generation, self.selectedControl == address else { return }
                self.controlVisualization = result
                self.visualizationStatus = "Mint: selected · Cyan: amplitude · Orange: pitch · Purple: filter · Individual scales"
            } catch is CancellationError { }
            catch {
                let available = await evaluator.controlsAvailable(revision: currentRevision)
                guard let self, self.selectionGeneration == selection, self.currentRevision == currentRevision else { return }
                self.controlsAvailable = available
                self.visualizationStatus = "Trajectories unavailable: \(error)"
                self.hostDiagnostic = self.visualizationStatus
            }
        }
    }

    private var performanceBPMControlID: String? {
        performanceControlMetadata.first { metadata in
            if case .double(_, let role) = metadata.domain { return role == .beatsPerMinute }
            return false
        }?.controlID
    }

    func resetPerformanceDiagnostics() { engine?.resetDiagnostics() }

    var displayedBPM: Double {
        if let performanceBPMControlID, let value = performanceNumber(performanceBPMControlID) {
            return value
        }
        if case .number(let rate) = masterControlValues[.playbackRate] { return rate * 120 }
        return bpm
    }

    var xyControls: [LiveControlDescriptor] {
        (controlCatalog?.descriptors ?? []).filter { $0.address.target != .master && $0.presentation != nil }
    }

    func controlValue(_ descriptor: LiveControlDescriptor) -> Double? {
        let value = descriptor.address.target == .master
            ? masterControlValues[descriptor.address.parameter] : overrides[descriptor.address]
        if case .number(let number) = value { return number }
        if value == .bypassed { return nil }
        if descriptor.address.target == .master {
            switch descriptor.address.parameter {
            case .playbackRate: return masterBPM / (loop?.bpm ?? 120)
            case .lowPassCutoff: return lowPass >= 19_999 ? nil : lowPass
            case .delayMix: return delayMix
            case .reverbMix: return reverbMix
            default: return nil
            }
        }
        if case .scalar(let number) = descriptor.baseline { return number }
        return nil
    }

    func setXY(x: Double, y: Double) throws {
        guard let xyX, let xyY, xyX != xyY,
              let a = controlCatalog?.descriptor(for: xyX), let b = controlCatalog?.descriptor(for: xyY),
              xyX.target != .master, xyY.target != .master,
              let first = a.presentation, let second = b.presentation else {
            throw LiveControlError.invalidCatalog("Choose two score controls for the XY pad.")
        }
        try setControls([xyX: .number(first.value(at: x)), xyY: .number(second.value(at: y))])
    }

    func refreshHostDevices() async throws {
        guard !isShuttingDown else { throw MIDIError.serviceShutDown }
        if let engine { audioEffects = try engine.discoverAudioEffects() }
        if midiService == nil { midiService = try CoreMIDIService() }
        guard let midiService else { throw MIDIError.serviceShutDown }
        let endpoints = try await midiService.enumerateEndpoints()
        guard !isShuttingDown else { throw MIDIError.serviceShutDown }
        midiEndpoints = endpoints
    }

    func selectHostedEffect(_ id: HostedAudioUnitID?, restoring state: HostedAudioUnitState? = nil) async throws {
        guard !isShuttingDown, !isRecording, let engine else {
            throw EvaluationError.invalidResult("Stop recording before changing the hosted effect.")
        }
        effectTask?.cancel()
        let task = Task { if let id { try await engine.selectAudioEffect(id, restoring: state) }
            else { try engine.clearAudioEffect() } }
        effectTask = task
        let requestID = UUID()
        effectRequestID = requestID
        isLoadingEffect = true
        defer {
            if effectRequestID == requestID { isLoadingEffect = false; hostedEffect = engine.audioEffectSnapshot() }
        }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func bypassHostedEffect(_ bypassed: Bool) throws {
        guard let engine else { throw EvaluationError.invalidResult(audioError) }
        try engine.setAudioEffectBypassed(bypassed)
        hostedEffect = engine.audioEffectSnapshot()
    }

    func beginMIDILearn(_ address: LiveControlAddress) throws {
        guard midiRoute.input != nil, midiEventTask != nil else { throw MIDIError.invalidLoop("Select an active MIDI input before learning a control.") }
        guard address.revision == currentRevision, controlCatalog?.descriptor(for: address)?.presentation != nil else {
            throw LiveControlError.unknownAddress(address)
        }
        learnAddress = address
    }

    func clearMIDILearn(_ address: LiveControlAddress) {
        learnedBindings.removeAll { $0.address == address }
        if learnAddress == address { learnAddress = nil }
    }

    private func startMIDIEvents() async throws {
        guard midiEventTask == nil, let midiService else { return }
        let events = try await midiService.eventStream()
        midiEventTask = Task { [weak self] in
            defer {
                self?.midiEventTask = nil
                if !Task.isCancelled, self?.midiClosed == false {
                    self?.learnAddress = nil
                    self?.hostDiagnostic = "MIDI input stream ended. Reconnect the input to resume Learn."
                }
            }
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.receiveControlChange(event)
            }
        }
    }

    private func receiveControlChange(_ event: TimestampedMIDIEvent) {
        guard event.sourceID == midiRoute.input,
              case .controlChange(let channel, let controller, let value) = event.message else { return }
        do {
            _ = try event.message.validated()
            if let address = learnAddress {
                guard address.revision == currentRevision, adoptedSourceDigest != nil else {
                    learnAddress = nil
                    throw LiveControlError.unknownAddress(address)
                }
                learnedBindings.removeAll { $0.address == address || ($0.endpoint == event.sourceID && $0.channel == channel && $0.controller == controller) }
                guard learnedBindings.count < DocumentHostStateStore.maximumBindingCount else {
                    throw DocumentHostStateStore.Failure.tooLarge
                }
                learnedBindings.append(.init(endpoint: event.sourceID, channel: channel, controller: controller, address: address))
                learnAddress = nil
            }
            guard let binding = learnedBindings.first(where: { $0.endpoint == event.sourceID && $0.channel == channel && $0.controller == controller }),
                  binding.address.revision == currentRevision,
                  let descriptor = controlCatalog?.descriptor(for: binding.address),
                  let presentation = descriptor.presentation else { return }
            let range = binding.range
            let mapping = try LiveControlPresentation(unit: presentation.unit,
                minimum: range?.lowerBound ?? presentation.minimum, maximum: range?.upperBound ?? presentation.maximum,
                scale: presentation.scale)
            try setControl(binding.address, value: .number(mapping.value(at: Double(value) / 127)))
        } catch { hostDiagnostic = error.localizedDescription }
    }

    func saveHostSettings(for document: URL) throws {
        let effect: HostedAudioUnitState?
        let bypassed: Bool
        switch engine?.audioEffectSnapshot() ?? .none {
        case .none: effect = nil; bypassed = false
        case .loaded(_, let value): effect = try engine?.captureAudioEffectState(); bypassed = value
        }
        try hostStateStore.save(.init(adoptedSourceDigest: adoptedSourceDigest, route: midiRoute,
            effect: effect, effectBypassed: bypassed, bindings: learnedBindings), for: document)
    }

    private func loadHostSettings(for document: URL?) {
        hostRestoreTask?.cancel()
        effectTask?.cancel()
        pendingHostState = nil
        do {
            let saved = try document.flatMap { try hostStateStore.load(for: $0) }
            pendingHostState = saved ?? .init(adoptedSourceDigest: nil, route: .disabled,
                effect: nil, effectBypassed: false, bindings: [])
        }
        catch { hostDiagnostic = error.localizedDescription }
    }

    private func adoptedControlsDidChange(revision: UInt64) {
        adoptedSourceDigest = candidateSourceDigests[revision]
        completionSource = source
        completionSites = adoptedSourceDigest == DocumentHostStateStore.sourceDigest(source)
            ? (candidateMetadata[revision]?.completionSites ?? []) : []
        candidateMetadata = candidateMetadata.filter { $0.key == revision }
        candidateSourceDigests = candidateSourceDigests.filter { $0.key == revision }
        if !learnedBindings.isEmpty { hostDiagnostic = "MIDI Learn bindings were detached after the score changed." }
        learnedBindings.removeAll()
        learnAddress = nil
        selectedControl = controlCatalog?.descriptors.first?.address
        xyX = xyControls.first(where: { $0.address.parameter == .pan })?.address ?? xyControls.first?.address
        xyY = xyControls.first(where: { $0.address != xyX })?.address
        let state = pendingHostState
        pendingHostState = nil
        let previousRestore = hostRestoreTask
        previousRestore?.cancel()
        hostRestoreTask = Task { [weak self] in
            await previousRestore?.value
            guard let self, !Task.isCancelled, self.currentRevision == revision, let state else { return }
            do { try await self.restoreHostSettings(state, revision: revision) }
            catch is CancellationError { }
            catch { self.hostDiagnostic = error.localizedDescription }
        }
    }

    func restoreHostSettings(_ state: DocumentHostStateStore.State, revision: UInt64) async throws {
        try state.validate()
        guard !isRestoringHostState else { throw EvaluationError.invalidResult("Host restore is already in progress.") }
        isRestoringHostState = true
        defer { isRestoringHostState = false }
        guard currentRevision == revision, let catalog = controlCatalog else {
            throw LiveControlError.staleRevision(expected: currentRevision ?? 0, actual: revision)
        }
        try await refreshHostDevices()
        try Task.checkCancellation()
        guard currentRevision == revision else { throw CancellationError() }
        if let effect = state.effect, !audioEffects.contains(where: { $0.id == effect.id }) {
            throw HostedAudioUnitError.missingComponent
        }
        for input in state.route.inputIDs {
            guard midiEndpoints.contains(where: { $0.id == input && $0.direction == .input }) else { throw MIDIError.endpointNotFound(input) }
        }
        if let output = state.route.output,
           !midiEndpoints.contains(where: { $0.id == output && $0.direction == .output }) { throw MIDIError.endpointNotFound(output) }
        var bindings: [DocumentHostStateStore.LearnBinding] = []
        for binding in state.bindings where state.adoptedSourceDigest == adoptedSourceDigest {
            let address = LiveControlAddress(revision: revision, target: binding.address.target, parameter: binding.address.parameter)
            guard binding.endpoint == state.route.input, let descriptor = catalog.descriptor(for: address),
                  descriptor.presentation != nil else { continue }
            if let range = binding.range {
                do {
                    for endpoint in [range.lowerBound, range.upperBound] {
                        if address.target == .master { try AudioLoopEngine.validateMasterControl(address.parameter, value: Float(endpoint)) }
                        else { try catalog.validate(value: .number(endpoint), for: address) }
                    }
                } catch { continue }
            }
            bindings.append(.init(endpoint: binding.endpoint, channel: binding.channel, controller: binding.controller,
                                  address: address, range: binding.range))
        }
        guard let engine else { throw EvaluationError.invalidResult(audioError) }
        let previous = midiRoute
        let previousEffect = engine.audioEffectSnapshot()
        let previousEffectState: HostedAudioUnitState?
        if case .loaded = previousEffect { previousEffectState = try engine.captureAudioEffectState() }
        else { previousEffectState = nil }
        try await configureMIDI(state.route)
        do {
            try Task.checkCancellation()
            guard currentRevision == revision else { throw CancellationError() }
            try await selectHostedEffect(state.effect?.id, restoring: state.effect)
            try Task.checkCancellation()
            guard currentRevision == revision else { throw CancellationError() }
            if state.effect != nil { try bypassHostedEffect(state.effectBypassed) }
        } catch {
            let original = error
            // Rollback must finish even when the owning restore was cancelled; its caller awaits it.
            let rollback = Task { @MainActor in
                var failures: [String] = []
                do {
                    if let previousEffectState {
                        try await engine.selectAudioEffect(previousEffectState.id, restoring: previousEffectState)
                        if case .loaded(_, let bypassed) = previousEffect { try engine.setAudioEffectBypassed(bypassed) }
                    } else { try engine.clearAudioEffect() }
                } catch { failures.append("Audio Unit rollback: \(error)") }
                do { try await self.configureMIDI(previous) } catch { failures.append("MIDI rollback: \(error)") }
                return failures
            }
            let failures = await rollback.value
            if !failures.isEmpty { throw EvaluationError.invalidResult("Host restore failed: \(original); " + failures.joined(separator: "; ")) }
            throw original
        }
        learnedBindings = bindings
        if bindings.count != state.bindings.count { hostDiagnostic = "Stale MIDI Learn bindings were left unattached." }
    }

    static let tranceSource = """
    import SwiftMusic
    import MusicPlayground

    // G minor, 140 BPM. Open the acid slider to build energy.
    // Adapted for SwiftMusic from Switch Angel's "Coding Trance Music from Scratch (Again)".
    // With respect and thanks: https://www.youtube.com/watch?v=iu5rnQkfO6M
    // Instrumental adaptation: synthesized here, without the original recording or voiceover.
    struct Trance: Music {
        @State private var leadLevel = 0.8

        var body: some Sound {
            TranceDrums()
            TranceBass()
            TranceLead(acid: slider(0.58, in: 0...1))
            BusReturn("trance.lead").gain(slider($leadLevel, in: 0...1))
            BusReturn("trance.bass")
        }
    }

    struct TranceDrums: Sound {
        var body: some Sound {
            Track("Trance Kick") {
                Sample("kick").rhythm("x*4").gain(1.1)
                    .effect(.saturation(drive: 0.18))
                    .duck(targetBus: "trance.lead", depth: -12,
                          attack: .milliseconds(160), recovery: .milliseconds(220))
                    .duck(targetBus: "trance.bass", depth: -9,
                          attack: .milliseconds(100), recovery: .milliseconds(190))
            }
            Track("Trance Backbeat") {
                Sample("snare").rhythm("~ x ~ x").highPass("900").gain(0.24)
                    .effect(.reverb(roomSize: 0.3, wet: 0.12))
            }
            Track("Trance Hats") {
                Sample("closedHat").rhythm("[~ x] [~ x] [~ x] [~ [x x]]")
                    .gain("0.35 0.25 0.3 0.24")
                    .pan("-0.45 0.45 -0.3 0.55")
            }
        }
    }

    struct TranceBass: Sound {
        var body: some Sound {
            Track("Trance Bass") {
                Synthesizer(.bandLimitedSaw)
                    .notes("G1*16")
                    .transpose("<0 0 -2 -2>")
                    .unison(voices: 5, detuneCents: 18)
                    .gate(0.65)
                    .envelope(attack: .milliseconds(2), decay: .milliseconds(90),
                              sustainLevel: 0.15, release: .milliseconds(35))
                    .lowPass("720", resonanceQ: 1.4)
                    .acidEnvelope(0.25, decay: .milliseconds(100))
                    .gain(0.38)
            }
            .send(to: "trance.bass", level: 1, placement: .preFader)
            .trackLevel(0)
        }
    }

    struct TranceLead: Sound {
        var acid: Double

        var body: some Sound {
            Track("Trance Lead") {
                Synthesizer(.bandLimitedSaw)
                    // The reference's five-note G-minor figure, phrased across sixteenths.
                    .notes("G3 D4 G3 Bb4 G4 G3 D4 G3 Bb4 G4 G3 D4 G3 Bb4 G4 D4")
                    .transpose("<0 0 -2 -2>")
                    .unison(voices: 5, detuneCents: 24)
                    .gate(0.7)
                    .envelope(attack: .milliseconds(3), decay: .milliseconds(140),
                              sustainLevel: 0.2, release: .milliseconds(100))
                    .lowPass("450", resonanceQ: 3.5)
                    .acidEnvelope(acid, decay: .milliseconds(170))
                    .effect(.filter(kind: .highPass, cutoffHz: 190, resonance: 0.707))
                    // Pan creates real L/R differences before the stereo effects.
                    .pan("-0.65 0.35 -0.2 0.65")
                    .effect(.delay(time: .eighth, feedback: 0.35, wet: 0.3))
                    .effect(.reverb(roomSize: 0.45, wet: 0.16))
                    .gain(1.6)
            }
            .send(to: "trance.lead", level: 1, placement: .preFader)
            .trackLevel(0)
        }
    }
    """

    static let initialSource = """
    import SwiftMusic
    import MusicPlayground

    // Deep Current — C minor, 140 BPM.
    // Inspired by Switch Angel, with respect: https://www.youtube.com/watch?v=HkgV_-nJOuE
    struct Session: Music {
        @State private var synthLevel = 0.8

        var body: some Sound {
            // Sibling sounds play together. Each Sound can contain other Sounds.
            RhythmSection()

            // Playground owns this slider's state. Drag it to change the filter sweep.
            SynthSection(acidAmount: slider(0.5, in: 0...1))

            // Control the shared synth return through the State declared above.
            BusReturn("synths")
                .gain(slider($synthLevel, in: 0...1))
        }
    }

    struct RhythmSection: Sound {
        var body: some Sound {
            Track("Kick") {
                Sample("kick")
                    .rhythm("x*4")
                    .gain(1.5)
                    .effect(.saturation(drive: 0.25))
                    .duck(targetBus: "synths", depth: -14,
                          attack: .milliseconds(200), recovery: .milliseconds(230))
            }

            Track("Hats") {
                Sample("closedHat")
                    // Brackets subdivide a step; ~ is a rest.
                    .rhythm("[~ x] [~ x] [~ x] [~ [x x]]")
                    .gain("0.32 0.25 0.29 0.18")
                    .pan(0.22)
            }
        }
    }

    struct SynthSection: Sound {
        var acidAmount: Double

        var body: some Sound {
            AcidBass(amount: acidAmount)
            Foghorn()
        }
    }

    struct AcidBass: Sound {
        var amount: Double

        var body: some Sound {
            Track("Acid") {
                Synthesizer(.bandLimitedSaw)
                    .notes("C2 Eb2 G1 Bb1 C2 G2 Eb2 F2 C2 Bb1 G1 Eb2 F2 G2 Bb1 D2")
                    .gate(0.78)
                    .envelope(
                        attack: .milliseconds(2), decay: .milliseconds(95),
                        sustainLevel: 0.35, release: .milliseconds(30)
                    )
                    .lowPass(CutoffPattern("200 260 380 650").slow(4), resonanceQ: 8)
                    .acidEnvelope(amount, decay: .milliseconds(140))
                    .gain("0.85 0.62 0.72 0.65")
                    .effect(.distortion(drive: 0.32))
                    .effect(.stereoWidth(1.5))
            }
            .send(to: "synths", level: 1, placement: .preFader)
            .trackLevel(0)
        }
    }

    struct Foghorn: Sound {
        var body: some Sound {
            Track("Foghorn") {
                Synthesizer(.bandLimitedSaw)
                    .notes("~ C2 ~ ~")
                    .slow(4)
                    .unison(voices: 5, detuneCents: 32)
                    .envelope(
                        attack: .milliseconds(30), decay: .milliseconds(300),
                        sustainLevel: 0.7, release: .milliseconds(1800)
                    )
                    .highPass("140")
                    .lowPass("1200")
                    .gain(0.32)
                    .effect(.reverb(roomSize: 0.7, wet: 0.32))
            }
            .send(to: "synths", level: 1, placement: .preFader)
            .trackLevel(0)
        }
    }
    """
}
