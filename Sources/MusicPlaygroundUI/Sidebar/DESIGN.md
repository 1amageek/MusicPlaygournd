# Sidebar

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
Native selectable List, caller-supplied rows and footer, explicit error presentation. FileTreeItemRow owns the canonical expandable folder/file/dirty/context-load presentation; callers supply actual URLs, expansion binding, children and actions. File discovery, persistence, selection handling and filters stay in each app.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> ProjectSidebar -> user action -> app owner
```

## Contracts and Invariants
Selection bindings route to the caller once; no hidden file I/O or fake files. macOS dense rows and iPad touch rows use platform-appropriate minimum heights.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.
