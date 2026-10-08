# Wave

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
Draw actual supplied loop peaks/stereo samples using bounded Canvas columns. The renderer/application owns PCM, peak derivation, timestamps and transport.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> LoopWaveView, WaveformView -> user action -> app owner
```

## Contracts and Invariants
No decorative waveform or audio inference. Empty input is empty; cyclic interpolation and finite-value handling preserve the existing Mac behavior.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.

## Complete Native Interface Parity
This component's visual implementation is shared by Mac and iPad. App adapters supply accepted values and actions; presentation protocols preserve concrete runtime validation and callback ownership. Native gesture/chooser adapters remain explicit at the platform boundary. Buttons and menus have explicit content shapes. Platform API adapters cannot change control meaning or synthesize samples/metadata. Narrow width uses an adaptive complete rack; all actions remain reachable. [Parity requirements](../../../docs/UI-PARITY.md) and actual platform UI tests own visual/workflow completion.

Wave also owns the original stereo Mid/Side/time projection, dual-deck overlay, master balance/space surface and compressor panel. CompressorSettings and CompressorEnvelope supply accepted settings and aligned pre/post samples; the caller owns admission and snapshots. The actual Mac Canvas/control implementation moves here with unchanged axes, font, geometry, threshold gestures and accessibility. UIKit and AppKit scratch adapters dispatch actual signed transport motion; release/cancellation retain distinct semantics.
