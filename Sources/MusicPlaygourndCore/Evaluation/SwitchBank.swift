import Foundation
import SwiftMusic

/// The source ranges and case order for one compiler-admitted switch site.
public struct SwitchSite: Codable, Sendable, Equatable, Hashable {
    public let switchLine: Int
    public let endLine: Int
    public let caseRanges: [NSRange]

    public init(switchLine: Int, endLine: Int, caseRanges: [NSRange]) throws {
        guard (1...65_536).contains(switchLine),
              (1...65_536).contains(endLine),
              endLine >= switchLine,
              caseRanges.count >= 2,
              caseRanges.count <= 64,
              caseRanges.allSatisfy({
                  $0.location >= 0 && $0.length >= 0 &&
                  $0.location <= 65_536 && $0.length <= 65_536 - $0.location
              }) else {
            throw EvaluationError.invalidResult("Invalid Swift switch source site.")
        }
        self.switchLine = switchLine
        self.endLine = endLine
        self.caseRanges = caseRanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            switchLine: container.decode(Int.self, forKey: .switchLine),
            endLine: container.decode(Int.self, forKey: .endLine),
            caseRanges: container.decode([NSRange].self, forKey: .caseRanges)
        )
    }
}

/// One stored enum property that controls one or more compiler-admitted sites.
public struct SwitchControl: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let propertyName: String
    public let cases: [String]
    public let sites: [SwitchSite]

    public init(id: String, propertyName: String, cases: [String], sites: [SwitchSite]) throws {
        guard !id.isEmpty, id.utf8.count <= 512,
              !propertyName.isEmpty, propertyName.utf8.count <= 256,
              cases.count >= 2, cases.count <= 64,
              cases.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              Set(cases).count == cases.count,
              !sites.isEmpty, sites.count <= 256 else {
            throw EvaluationError.invalidResult("Invalid Swift switch control metadata.")
        }
        self.id = id
        self.propertyName = propertyName
        self.cases = cases
        self.sites = sites
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            propertyName: container.decode(String.self, forKey: .propertyName),
            cases: container.decode([String].self, forKey: .cases),
            sites: container.decode([SwitchSite].self, forKey: .sites)
        )
    }
}

/// A fully prepared retained result for one switch selection.
public struct SwitchVariant: Codable, Sendable, Equatable {
    public let selection: [Int]
    public let loop: PreparedLoop
    public let catalog: LiveControlCatalog
    public let metadata: EditorSemanticMetadata

    public init(
        selection: [Int],
        loop: PreparedLoop,
        catalog: LiveControlCatalog,
        metadata: EditorSemanticMetadata
    ) throws {
        guard selection.count <= 64 else {
            throw EvaluationError.invalidResult("Swift switch selection exceeds the bound.")
        }
        try loop.validate()
        guard catalog.descriptors.allSatisfy({ $0.address.revision == metadata.revision }) else {
            throw EvaluationError.invalidResult("Invalid Swift switch metadata revision.")
        }
        self.selection = selection
        self.loop = loop
        self.catalog = catalog
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            selection: container.decode([Int].self, forKey: .selection),
            loop: container.decode(PreparedLoop.self, forKey: .loop),
            catalog: container.decode(LiveControlCatalog.self, forKey: .catalog),
            metadata: container.decode(EditorSemanticMetadata.self, forKey: .metadata)
        )
    }
}

/// All compiler-prepared combinations for one ordinary `Session: Music` source.
public struct PreparedSwitchBank: Codable, Sendable, Equatable {
    public static let maximumVariants = 16
    public static let maximumPCMBytes = 128 * 1024 * 1024

    public let controls: [SwitchControl]
    public let variants: [SwitchVariant]
    public let initialIndex: Int

    public init(controls: [SwitchControl], variants: [SwitchVariant], initialIndex: Int) throws {
        guard !controls.isEmpty, controls.count <= 16,
              !variants.isEmpty, variants.count <= Self.maximumVariants,
              variants.indices.contains(initialIndex) else {
            throw EvaluationError.invalidResult("Invalid prepared Swift switch bank.")
        }
        var expectedCount = 1
        for control in controls {
            guard control.cases.count > 0,
                  expectedCount <= Self.maximumVariants / control.cases.count else {
                throw EvaluationError.invalidResult("Prepared Swift switch bank exceeds the variant bound.")
            }
            expectedCount *= control.cases.count
        }
        guard expectedCount == variants.count else {
            throw EvaluationError.invalidResult("Prepared Swift switch bank combinations are incomplete.")
        }
        guard variants.allSatisfy({ $0.selection.count == controls.count }) else {
            throw EvaluationError.invalidResult("Prepared Swift switch selection shape is invalid.")
        }
        guard Set(variants.map(\.selection)).count == variants.count else {
            throw EvaluationError.invalidResult("Prepared Swift switch selections are duplicated.")
        }
        for variant in variants {
            for (index, selection) in variant.selection.enumerated() {
                guard controls[index].cases.indices.contains(selection) else {
                    throw EvaluationError.invalidResult("Prepared Swift switch selection is invalid.")
                }
            }
            guard variant.loop.bpm == variants[initialIndex].loop.bpm,
                  variant.loop.beatsPerBar == variants[initialIndex].loop.beatsPerBar else {
                throw EvaluationError.invalidResult("Prepared Swift switch variants disagree on tempo or meter.")
            }
        }
        for control in controls {
            guard control.sites.allSatisfy({ $0.caseRanges.count == control.cases.count }) else {
                throw EvaluationError.invalidResult("Prepared Swift switch case metadata is incomplete.")
            }
        }
        let totalPCMBytes = try variants.reduce(into: 0) { partial, variant in
            let (bytes, overflow) = variant.loop.pcm.count.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
            guard !overflow else {
                throw EvaluationError.invalidResult("Prepared Swift switch PCM size overflowed.")
            }
            let (total, totalOverflow) = partial.addingReportingOverflow(bytes)
            guard !totalOverflow else {
                throw EvaluationError.invalidResult("Prepared Swift switch PCM size overflowed.")
            }
            partial = total
        }
        guard totalPCMBytes <= Self.maximumPCMBytes else {
            throw EvaluationError.invalidResult("Prepared Swift switch bank exceeds the 128 MiB PCM bound.")
        }
        self.controls = controls
        self.variants = variants
        self.initialIndex = initialIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            controls: container.decode([SwitchControl].self, forKey: .controls),
            variants: container.decode([SwitchVariant].self, forKey: .variants),
            initialIndex: container.decode(Int.self, forKey: .initialIndex)
        )
    }
}

/// Small worker handshake payload. PCM and semantic metadata stay in bounded sidecars.
struct RenderWorkerSwitchDescriptor: Codable, Sendable, Equatable {
    let controls: [SwitchControl]
    let selections: [[Int]]
    let initialIndex: Int

    init(bank: PreparedSwitchBank) {
        self.controls = bank.controls
        self.selections = bank.variants.map(\.selection)
        self.initialIndex = bank.initialIndex
    }
}
