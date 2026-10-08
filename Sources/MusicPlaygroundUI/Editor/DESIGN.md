# Editor

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
Tab/content layout, explicit sidebar toggle and read-only source presentation. Native text storage, undo, IME, completion and source compilation belong to platform editors.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> EditorPane, SidebarToggle, SourceCodeView -> user action -> app owner
```

## Contracts and Invariants
Embedding the Mac editor preserves its identity and bindings; read-only iPad code is never advertised as editable or evaluated dynamically.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.
