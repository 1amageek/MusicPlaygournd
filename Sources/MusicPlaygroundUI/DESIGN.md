# MusicPlaygroundUI

## Purpose and Scope
SwiftPM UI module, public library product. Parent: [system/package](../../DESIGN.md). Children are indexed below. macOS 15+ and iPadOS 27+ use the same SwiftUI source.

## Responsibilities and Boundaries
Owns shared presentation and gestures; has no Core, SwiftMusic, process, audio engine or file-system dependency; shared Editor uses pinned native SwiftSyntax grammar libraries. macOS owns SessionModel/DeckWorkspace and AppKit text editing. iPad owns PlaybackModel/NativeAudioPlayer and bundled-score evaluation. SwiftUI.View is the public view protocol; the EffectSettings protocol adapts existing settings without changing their owner.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Workspace](Workspace/DESIGN.md) | child | WorkspaceSplitView | Two-column NavigationSplitView and column sizing | app owns runtime state |
| [Sidebar](Sidebar/DESIGN.md) | child | ProjectSidebar | Native selectable List, caller-supplied rows and footer, explicit error presentation | app owns runtime state |
| [Deck](Deck/DESIGN.md) | child | DeckRack, DeckPanel, TransportButton | A/master/B geometry, deck slots and circular transport presentation | app owns runtime state |
| [Editor](Editor/DESIGN.md) | child | EditorPane, SidebarToggle, SourceEditor, SwiftSourceAnalyzing, EditorTheme | Tab/content layout, explicit sidebar toggle and native source editing, shared palettes and parser analysis | app owns runtime state |
| [Effect](Effect/DESIGN.md) | child | EffectSettings, EffectView, UnavailableEffectView | Display-only settings protocol and FX selection/mix/depth/rate/feedback interaction | app owns runtime state |
| [Wave](Wave/DESIGN.md) | child | LoopWaveView, WaveformView | Draw actual supplied loop peaks/stereo samples using bounded Canvas columns | app owns runtime state |
| [Mac Editor](../MusicPlaygourndApp/Editor/DESIGN.md) | used by | app-owned bindings and actions | native models/editing retained | preserve fullscreen and native editor identity |
| [iPad Interface](../../MusicPlayground/MusicPlayground/Interface/DESIGN.md) | used by | app-owned playback snapshot | real documents and independent audio | arbitrary native compilation is separate |

## Architecture
```text
Mac SessionModel / DeckWorkspace -> MusicPlaygroundUI <- iPad PlaybackModel
     AppKit editor adapter           |                native audio adapter
                      Workspace + Sidebar
                       Deck + Effect + Wave
                             Editor
```

## Contracts and Invariants
Shared views receive values, bindings and actions; they do not reinterpret music or adopt DSP state. Native adapters supply special gestures and editors via View slots. The public library builds independently of Mac-only Core. Platform conditionals select native view/color adapters and row sizing; state isolation is identical. No module mutable shared state exists.

## Runtime Flows
Selection and control actions call their app owner; snapshots return to SwiftUI. Wave views display actual accepted PCM-derived peaks. Unsupported capabilities are explicit adapter branches and never mutate a pretend backend.

## State, Ownership, and Lifecycle
Binding lifetime is the caller view/model lifetime. Views own local disclosure/popup presentation only; app models own document, transport, effect and audio lifecycle. Moving presentation does not transfer their cleanup responsibilities.

## Verification and Change Impact
Mac focused native tests cover editor selection/undo, shared waveform and FX pad/model behavior. Physical iPad tests cover shared sidebar selection/toggling, actual PCM-derived waveform, play/stop/restart and background stop. Both apps must build and display the shared components before completion. Root owns cumulative integration.

Child: [Control](Control/DESIGN.md) owns accepted knob/host/trajectory presentation.
