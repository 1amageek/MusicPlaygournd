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

## Complete Native Interface Parity
This component's visual implementation is shared by Mac and iPad. App adapters supply accepted values and actions; presentation protocols preserve concrete runtime validation and callback ownership. Native gesture/chooser adapters remain explicit at the platform boundary. Buttons and menus have explicit content shapes. Platform API adapters cannot change control meaning or synthesize samples/metadata. Narrow width uses an adaptive complete rack; all actions remain reachable. [Parity requirements](../../../docs/UI-PARITY.md) and actual platform UI tests own visual/workflow completion.

Deck owns the full transport-row composition, gain, EQ and filter/space XY presentation. EqualizerBandSettings and EqualizerResponse provide accepted three-band values and exact native transfer response; they do not validate or mutate DSP. App callbacks perform admission. Shared gain drawing preserves the original Mac dial and accessibility; Mac injects its existing multi-finger adapter. Rack uses the original horizontal A/master/B layout where full headers fit, and bounded scrollable vertical composition at narrow width so the editor retains space. No deck state lives in the rack.
