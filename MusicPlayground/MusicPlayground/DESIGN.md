# iPad App Module

## Purpose and Scope
Native SwiftUI executable module. Parent: [project](../DESIGN.md). Children: [Prototype](Prototype/DESIGN.md), [Documents](Documents/DESIGN.md). Entry point is MyApp.swift.

## Responsibilities and Boundaries
Composes the temporary view and its playback model. Consumes shared renderer source under its existing contract; owns no alternate DSP.

## Related Designs
[Prototype](Prototype/DESIGN.md) owns score/playback state and failures. [Rendering](../../Sources/MusicPlaygourndCore/Rendering/DESIGN.md) owns synthesis and prepared PCM. [MusicPlaygroundUI](../../Sources/MusicPlaygroundUI/DESIGN.md) supplies the same workspace, sidebar, deck, effect and waveform presentation as Mac. Parent owns dependency and target membership.

## Architecture
```text
SwiftUI app -> Prototype -> shared Rendering -> AVFoundation
```

## Contracts and Invariants
UI state is MainActor isolated. App backgrounding stops playback and cancels pending work; foregrounding does not start audio automatically.

## Verification and Change Impact
App-hosted behavioral tests use the same model and playback implementation as the UI. Normal launches present an idle Play button; no editable-source execution is advertised.

[Documents](Documents/DESIGN.md) owns real project files, shared A/B buffers, saving and dirty-close decisions. Source selection and edits preserve the accepted audio owned by Prototype. The parity task replaces the prototype presentation incrementally; incomplete audio/host branches remain explicit until verified.
