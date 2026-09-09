import Foundation
import SwiftMusic

/// The retained worker setup produced by one source compilation.
public struct RenderWorkerPreparation: Sendable {
    public let session: LoopRenderSession
    public let metadata: EditorSemanticMetadata?
    public let source: String?
    public let performanceControls: [PerformanceControlMetadata]
    public let performanceAdapter: (any RenderWorkerPerformanceAdapter)?
    public let switchBank: PreparedSwitchBank?
    public let switchSessions: [LoopRenderSession]
    public let switchSelection: (@MainActor @Sendable ([Int]) -> Void)?

    public init(
        session: LoopRenderSession,
        metadata: EditorSemanticMetadata? = nil,
        source: String? = nil,
        performanceControls: [PerformanceControlMetadata] = [],
        performanceAdapter: (any RenderWorkerPerformanceAdapter)? = nil,
        switchBank: PreparedSwitchBank? = nil,
        switchSessions: [LoopRenderSession] = [],
        switchSelection: (@MainActor @Sendable ([Int]) -> Void)? = nil
    ) {
        self.session = session
        self.metadata = metadata
        self.source = source
        self.performanceControls = performanceControls
        self.performanceAdapter = performanceAdapter
        self.switchBank = switchBank
        self.switchSessions = switchSessions
        self.switchSelection = switchSelection
    }
}

/// The fixed-file payload published by a worker before a successful response.
public struct WorkerPreparedResult: Codable, Sendable, Equatable {
    public let revision: UInt64
    public let generation: UInt64
    public let loop: PreparedLoop
    public let metadata: EditorSemanticMetadata?

    public init(
        revision: UInt64,
        generation: UInt64,
        loop: PreparedLoop,
        metadata: EditorSemanticMetadata? = nil
    ) {
        self.revision = revision
        self.generation = generation
        self.loop = loop
        self.metadata = metadata
    }
}
