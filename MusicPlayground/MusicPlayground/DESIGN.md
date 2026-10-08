# iPad App Module

## Purpose and Scope
Native SwiftUI executable module. Parent: [project](../DESIGN.md). Children: [Interface](Interface/DESIGN.md), [Documents](Documents/DESIGN.md), [Audio](Audio/DESIGN.md). Entry point is the SwiftUI App/WindowGroup in MyApp.swift.

## Responsibilities and Boundaries
Composes the full shared interface, real documents and independent deck audio models. Consumes shared renderer source under its existing contract; owns no alternate DSP.

## Related Designs
[Audio](Audio/DESIGN.md) owns score/playback state and failures. [Rendering](../../Sources/MusicPlaygourndCore/Rendering/DESIGN.md) owns synthesis and prepared PCM. [MusicPlaygroundUI](../../Sources/MusicPlaygroundUI/DESIGN.md) supplies the same workspace, sidebar, deck, effect and waveform presentation as Mac. Parent owns dependency and target membership.

## Architecture
```text
SwiftUI app -> Interface -> Documents + Audio -> shared Rendering/Playback -> AVFoundation
```

## Contracts and Invariants
UI state is MainActor isolated. App backgrounding stops playback and cancels pending work; foregrounding does not start audio automatically.

## Verification and Change Impact
App-hosted behavioral tests use the same model and playback implementation as the UI. Normal launches present an idle Play button; no editable-source execution is advertised.

[Documents](Documents/DESIGN.md) owns real project files, shared A/B buffers, saving and dirty-close decisions. Source selection and edits preserve the accepted audio owned by Audio. Interface is the production composition. The superseded prototype was removed after its score/codec/hardware/cancellation tests migrated to AudioWorkspace. No alternate single-player production path remains.

The native iPad deployment supports LandscapeLeft and LandscapeRight only. Debug and Release own the matching Info.plist orientation declaration. UIRequiresFullScreen enables Apple's documented landscape compatibility policy while retaining SwiftUI window/scene restoration. On windowed iPadOS this maintains a consistent logical scene size and scales its presentation instead of dynamically resizing it. The installed SwiftUI SDK has no public orientation-lock scene modifier; UIViewController orientation lock is conditional on a fullscreen, centered, unoccluded scene. Physical attempted portrait rotation and background/resume verify the actual policy and unchanged lifecycle. Reference: [Apple compatibility policy](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen.md).
