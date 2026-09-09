# MusicPlayground Declarations

## Purpose and Scope
Host-specific control declarations for SwiftMusic. Parent: [package](../../DESIGN.md). No SwiftUI or AppKit dependency.

## Responsibilities and Boundaries
The explicit overload borrows SwiftMusic.State owned by the retained Music value. The automatic overload stores values in the host-owned evaluation session. Neither mechanism adds Playground declarations to SwiftMusic. Editor widgets never own persistent values.

## Related Designs
Depends on SwiftMusic public State and Sound composition. Used by [Evaluation](../MusicPlaygourndCore/Evaluation/DESIGN.md) and [Editor](../MusicPlaygourndApp/Editor/DESIGN.md).

## Architecture
```text
slider(State) / slider(initial value)
    -> retained control session
    -> validated control metadata and updates
    -> host renderer / source-positioned editor UI
```

## Contracts and Invariants
Both overloads expose finite Double values in a finite ordered range. Invalid declarations are reported by the evaluation scope, never adopted. Registration and state mutation are MainActor-owned. Source positions identify UI placement, not View lifetime. Explicit IDs preserve identity across arbitrary edits; automatic IDs use the declaration identity defined below. Removed declarations release their bindings. A failed evaluation retains the adopted session and audio.

## State, Ownership, and Lifecycle
The worker owns a control session for the lifetime of its retained Music value. Evaluation uses a scoped MainActor registration context and restores the previous context on exit. Values outlive individual evaluation passes and UI reconstruction. The scope cannot escape into asynchronous evaluation.

## Verification and Change Impact
[Control-session verification](../../Tests/MusicPlaygourndCoreTests/PlaygroundControlSessionTests.swift) checks State writes, automatic retention, invalid bounds and actual filter/gain PCM. [Native editor verification](../../Tests/MusicPlaygourndCoreTests/CodeEditorDocumentTests.swift) checks glyph placement, actions and unchanged text/selection/undo. [Continuous adoption verification](../../Tests/MusicPlaygourndCoreTests/SessionModelLiveControlTests.swift) exercises in-flight and latest values through the real worker and AVAudioEngine. A bundled-SDK worker probe also verified source-line insertion transfer and rejected-range PCM retention. Changes to registration, identity or state ownership require Evaluation and Editor integration checks.

## Identity and Host Constraints
Automatic IDs hash the source line and the call column relative to its indentation, scoped by file ID. Inserting preceding lines and changing indentation preserve values. Editing the declaration itself changes its identity; duplicate identical declarations require explicit IDs and fail registration rather than exchanging state. Explicit IDs support arbitrary source refactoring. The host retains values through the existing performance schema transfer contract.

Calls execute in MainActor Music.body. The acidEnvelope convenience extension composes SwiftMusic's existing filterEnvelope; it is exported by MusicPlayground, not by the SwiftMusic package. State-free declarations require a host evaluation scope. Pre-rendered switch banks reject inline controls because their fixed variants cannot represent mutable slider state; existing switch-only sessions are unchanged.
