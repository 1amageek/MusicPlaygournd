# Sidebar

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
Native selectable List, caller-supplied rows and footer, explicit error presentation. SidebarDisclosureGroup owns platform-specific tree expansion presentation. FileTreeItemRow owns the canonical expandable folder/file/dirty/context-load presentation; callers supply actual URLs, expansion binding, children and actions. File discovery, persistence, selection handling and filters stay in each app.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Documents/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> ProjectSidebar -> user action -> app owner
```

## Contracts and Invariants
Selection bindings route to the caller once; no hidden file I/O or fake files. macOS retains its native sidebar style and dense rows. iPad uses a plain native selectable List with four-point horizontal content margins, six-point row insets, four-point icon/name spacing and a 44-point minimum touch row. macOS keeps native DisclosureGroup. iPad SidebarDisclosureGroup renders individually selectable list rows and exposes expansion through the caller binding; the adapter supplies eight-point indentation per visible tree level. The caller scopes its music-control tint to the detail column so the sidebar inherits the system default, with no custom selected-row background or text color. File names receive the remaining row width and truncate in the middle only when necessary; dirty indicators retain their own space. Compact insets must leave Session.swift and Package.swift completely readable in the actual landscape split view.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.
