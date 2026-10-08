# Deck

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
A/master/B geometry, deck slots and circular transport presentation. Caller supplies controls, values, availability and actions.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> DeckRack, DeckPanel, TransportButton -> user action -> app owner
```

## Contracts and Invariants
No audio or transport state is duplicated. Disabled actions cannot execute; the app owns play/stop semantics and native gesture adapters.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.

DeckRack assigns explicit equal A/B widths around its bounded center from the actual proposed container width. Deck slot builders execute on MainActor during body evaluation so observable app snapshots are read by the rendering owner, rather than retaining constructor-time audio data. Native editor embedding must preserve full detail width; integrated playback tests reject a stale or zero-width waveform.
