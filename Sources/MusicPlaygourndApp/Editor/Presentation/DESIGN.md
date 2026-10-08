# Native DSP Presentation Adapters

## Purpose and Scope
Child of [Editor](../DESIGN.md); no children. Platform adapters compiled into both executables.

## Responsibilities and Boundaries
Conform existing runtime value types to UI presentation protocols without changing their storage, validation, ranges or algorithms. Mac imports Core; the native Xcode app compiles the exact Core source into its own module. No alternate settings or DSP implementation is introduced.

## Related Designs
[UI Deck](../../../MusicPlaygroundUI/Deck/DESIGN.md), [Wave](../../../MusicPlaygroundUI/Wave/DESIGN.md), [Control](../../../MusicPlaygroundUI/Control/DESIGN.md) consume these conformances. [Playback](../../../MusicPlaygourndCore/Playback/DESIGN.md) and [Rendering](../../../MusicPlaygourndCore/Rendering/DESIGN.md) remain value/algorithm authority.

## Architecture
```text
Core accepted values -> protocol witnesses -> shared SwiftUI controls
```

## Contracts and Invariants
Witnesses call the existing native response/mapping algorithm and preserve raw enums, bounds and failure contracts. No independent mutable state.

## Verification and Change Impact
Both target compile paths and actual FX/EQ/compressor/knob operations verify witnesses. Shared UI changes require both apps; runtime behavior remains covered by its existing native tests.
