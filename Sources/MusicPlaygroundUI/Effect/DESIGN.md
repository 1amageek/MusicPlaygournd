# Effect

## Purpose and Scope
Shared SwiftUI component. Parent: [UI module](../DESIGN.md). Children: none.

## Responsibilities and Boundaries
Display-only settings protocol and FX selection/mix/depth/rate/feedback interaction. Caller owns validation, adoption, BPM mapping, rollback and actual DSP.

## Related Designs
[Mac adapter](../../MusicPlaygourndApp/Editor/DESIGN.md) and [iPad adapter](../../../MusicPlayground/MusicPlayground/Prototype/DESIGN.md) consume this component. Both retain their runtime ownership.

## Architecture
```text
App-owned values/bindings -> EffectSettings, EffectView, UnavailableEffectView -> user action -> app owner
```

## Contracts and Invariants
Mutations pass through caller actions with the same clamped pad mapping as macOS. Unsupported iPad FX presents a reason, with no enabled DSP controls or synthetic applied values.
Public views implement SwiftUI.View; EffectSettings supplies the settings contract. UI is MainActor isolated by SwiftUI; this component owns only presentation state.

## Verification and Change Impact
[Mac tests](../../../Tests/MusicPlaygourndCoreTests) exercise real model/editor/FX behavior and waveform interpolation. [iPad tests](../../../MusicPlayground/UITests/PlaybackUITests.swift) exercise actual selection, sidebar toggle and playback through the integrated shared UI. Changing slots/layout requires inspecting both native apps; changing waveform or pad mapping requires focused behavioral regression.

## Complete Native Interface Parity
This component's visual implementation is shared by Mac and iPad. App adapters supply accepted values and actions; presentation protocols preserve concrete runtime validation and callback ownership. Native gesture/chooser adapters remain explicit at the platform boundary. Buttons and menus have explicit content shapes. Platform API adapters cannot change control meaning or synthesize samples/metadata. Narrow width uses an adaptive complete rack; all actions remain reachable. [Parity requirements](../../../docs/UI-PARITY.md) and actual platform UI tests own visual/workflow completion.
