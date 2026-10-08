# Editor

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none. Owns source presentation, canonical palettes and native syntax analysis under [E01–E09](../../../docs/UI-PARITY.md).

## Responsibilities and Boundaries
EditorPane composes tabs/content. UIKit SourceEditor owns native text storage, selection, scrolling, marked text and undo. AppKit retains its existing SourceKit semantic adapter. Callers own documents, saving, accepted music and compilation. Syntax-derived completion names are actual declarations and explicitly supplied imported types; they do not claim scope resolution or compiler semantics.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [UI module](../DESIGN.md) | parent | values/actions composition | shared presentation | preserve native editor identity |
| [Mac Editor](../../MusicPlaygourndApp/Editor/DESIGN.md) | used by | canonical EditorTheme palettes | SourceKit remains the semantic owner | palette changes affect both platforms |
| [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) | used by | SourceEditor edits/analysis/errors | caller retains text and accepted audio | editing does not evaluate source |

## Architecture
```text
Native text storage -> committed source snapshot -> SwiftSourceAnalyzing
       ↑                                                |
selection/undo/IME owner <- identity-checked tokens/diagnostics/format
       ↑
canonical EditorTheme palettes <- AppKit SourceKit semantic adapter
```

## Contracts and Invariants
SwiftSourceAnalyzing provides async throwing analyze/format operations. Official swift-syntax 604.0.0 (050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf) parses actual source. Analysis maps UTF-8 grammar offsets to checked UTF-16 native ranges. Formatting rejects parser diagnostics. The five palette values match the existing Mac values exactly. Color access and UIKit state are MainActor-owned.

## Runtime Flows
Committed edits publish document identity and actual text, then schedule coalesced analysis. Only matching document, source and generation adopt results. Marked text defers coloring, replacement and formatting until commit. Attribute changes preserve selection, scroll and undo. Syntax symbol insertion uses native character editing and undo.

## State, Ownership, and Lifecycle
The coordinator retains one native text view per caller-retained document ID; switching tabs reuses storage/undo. Closing releases its undo state and view. Plain-text documents use the same native storage with an empty syntax analysis; publication follows the same deferred identity/source/generation guards. Explicit diagnostic reveal requests validate UTF-16 bounds before selecting and scrolling. One cancellable analysis/format task belongs to the coordinator; shutdown invalidates generations, cancels the task and releases views. Shared module has no mutable cross-thread state.

## Failure, Concurrency, and Constraints
Parsing runs outside MainActor. Admission permits at most 2 MiB UTF-8, with a bounded byte-to-UTF16 map. Cancellation is checked before/after parser work; its synchronous parser cannot be interrupted mid-parse. Typed oversize, invalid range and invalid syntax failures preserve characters and are published to the owner. Grammar analysis never compiles, evaluates or replaces accepted music.

## Verification and Change Impact
[SharedSourceAnalysisTests](../../../Tests/MusicPlaygourndCoreTests/SharedSourceAnalysisTests.swift) verifies grammar categories, Unicode, raw strings/interpolation/nested comments, actual edits, formatting and failures/cancellation. [SourceEditingTests](../../../MusicPlayground/Tests/SourceEditingTests.swift) hosts the real UIKit view and verifies attributes, edits, selection, undo and IME. [CompletionEditorTests](../../../Tests/MusicPlaygourndCoreTests/CompletionEditorTests.swift) owns Mac semantic-color regressions. Document retention integration belongs to native document tests. Palette/parser/native storage changes require these focused tests and actual editor inspection on both apps.

FileTabStrip is the canonical A/B tab presentation. FileTabItem supplies immutable identity/name/URL/dirty/read-only values. The caller supplies selected/audible identities and real select/close/create/load actions; the shared view owns no file or transport state. Both native adapters must consume this presentation.
