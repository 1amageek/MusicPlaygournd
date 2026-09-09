import SwiftMusic
import CryptoKit
import Foundation

/// Owns automatic control state and explicit State connections for a retained Music value.
@MainActor
public final class PlaygroundControlSession {
    private struct Entry {
        let definition: SliderDefinition
        let write: (@MainActor (Double) -> Void)?
    }

    private static var current: PlaygroundControlSession?
    private var entries: [String: Entry] = [:]
    private var values: [String: Double] = [:]
    private var pending: [String: Entry] = [:]
    private var sourceLines: [Substring] = []
    private var declarationError: SliderDeclarationError?

    public init() {}

    public var definitions: [SliderDefinition] {
        entries.values.map(\.definition).sorted {
            ($0.fileID, $0.line, $0.column) < ($1.fileID, $1.line, $1.column)
        }
    }

    /// Evaluates synchronous declarations without resetting previously accepted values.
    public func evaluate<Result>(source: String = "", _ body: () throws -> Result) throws -> Result {
        let previous = Self.current
        precondition(previous !== self, "A control session cannot evaluate itself recursively")
        Self.current = self
        sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
        pending = [:]
        declarationError = nil
        defer { Self.current = previous; pending = [:] }
        let result = try body()
        if let declarationError { throw declarationError }
        entries = pending
        values = values.filter { entries[$0.key] != nil }
        for (id, entry) in entries where values[id] == nil { values[id] = entry.definition.value }
        return result
    }

    public func validate(_ updates: [String: Double]) throws {
        for (id, value) in updates {
            guard let entry = entries[id] else { throw SliderDeclarationError.unknownID(id) }
            guard value.isFinite, entry.definition.range.contains(value) else {
                throw SliderDeclarationError.invalidValue(id)
            }
        }
    }

    public func apply(_ updates: [String: Double]) throws {
        try validate(updates)
        for (id, value) in updates {
            values[id] = value
            if let entry = entries[id] {
                entry.write?(value)
                let old = entry.definition
                entries[id] = Entry(definition: SliderDefinition(id: old.id, fileID: old.fileID,
                    line: old.line, column: old.column, range: old.range,
                    initialValue: old.initialValue, value: value), write: entry.write)
            }
        }
    }

    fileprivate static func resolve(_ initialValue: Double, state: SwiftMusic.State<Double>?,
                                    range: ClosedRange<Double>, id: String?, fileID: String,
                                    line: Int, column: Int) -> Double {
        guard let owner = current else {
            preconditionFailure("slider must be evaluated by MusicPlayground's control session")
        }
        let identity: String
        if let id { identity = id }
        else if (fileID == "Session.swift" || fileID.hasSuffix("/Session.swift")),
                line > 0, line <= owner.sourceLines.count {
            let text = owner.sourceLines[line - 1]
            let leading = text.prefix { $0 == " " || $0 == "\t" }.utf8.count
            let key = "\(text.trimmingCharacters(in: .whitespaces)):\(column - leading)"
            let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            identity = "slider:\(fileID):\(digest)"
        } else { identity = "slider:\(fileID):\(line):\(column)" }
        if owner.pending[identity] != nil { owner.declarationError = .duplicateID(identity) }
        if owner.pending.count >= 32 { owner.declarationError = .tooManyControls }
        if !range.lowerBound.isFinite || !range.upperBound.isFinite || range.lowerBound >= range.upperBound {
            owner.declarationError = .invalidRange(identity)
        }
        let value = state?.wrappedValue ?? owner.values[identity] ?? initialValue
        if !value.isFinite || !range.contains(value) || !initialValue.isFinite || !range.contains(initialValue) {
            owner.declarationError = .invalidValue(identity)
        }
        let definition = SliderDefinition(id: identity, fileID: fileID, line: line, column: column,
                                          range: range, initialValue: initialValue, value: value)
        let write: (@MainActor (Double) -> Void)?
        if let state { write = { value in state.wrappedValue = value } } else { write = nil }
        owner.pending[identity] = Entry(definition: definition, write: write)
        return value
    }
}

/// Declares a slider whose value is owned by the Playground session.
@MainActor
public func slider(_ initialValue: Double, in range: ClosedRange<Double> = 0...1,
                   id: String? = nil, fileID: String = #fileID, line: Int = #line,
                   column: Int = #column) -> Double {
    PlaygroundControlSession.resolve(initialValue, state: nil, range: range,
                                     id: id, fileID: fileID, line: line, column: column)
}

/// Declares a slider connected to explicitly owned SwiftMusic state.
@MainActor
public func slider(_ state: SwiftMusic.State<Double>, in range: ClosedRange<Double> = 0...1,
                   id: String? = nil, fileID: String = #fileID, line: Int = #line,
                   column: Int = #column) -> Double {
    PlaygroundControlSession.resolve(state.wrappedValue, state: state, range: range,
                                     id: id, fileID: fileID, line: line, column: column)
}
