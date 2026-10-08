# Control Presentation

## Purpose and Scope
Child of [UI module](../DESIGN.md); no children. Shared accepted live-control knobs, host selection and result trajectories.

## Responsibilities and Boundaries
Owns presentation and local selection/gesture state; consumes the app-owned disclosure binding. Applications own catalog identity, control value admission, MIDI scheduling, hosted unit lifecycle, recording/export and settings I/O. Protocols expose immutable accepted values; callbacks report validation errors rather than inventing values.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [UI](../DESIGN.md) | parent | SwiftUI composition | common presentation | no runtime dependency |
| [Mac Editor](../../MusicPlaygourndApp/Editor/DESIGN.md) | used by | accepted controls/actions | native model adapter | semantic highlighting remains Mac-owned |
| [Native Host](../../../MusicPlayground/MusicPlayground/Audio/Host/DESIGN.md) | used by | accepted endpoint/unit/control state | iPad adapter | lifecycle cancellation before graph mutation |

## Architecture
```text
accepted descriptor/presentation -> shared knob/trace/host controls -> callback -> app admission
```

## Contracts and Invariants
The original Mac control drawing and gestures are shared. MIDI options initially collapse. The app owns the disclosure binding so its bounded popover grows when MIDI is expanded and shrinks when collapsed; overflowing content remains scrollable. Each action retains its own accessibility label. The disclosure header shows accepted route selection; expanded content uses distinct Input, Output, Notes and Clock sections with readable device names, selection status and explicit unmet prerequisites. Off/Send/Receive clock actions preserve the existing route bindings and disable unavailable directions. A selected control and its learning state appear inside the MIDI section, with explicit Learn/Cancel/Remove actions. The apps own actual endpoint discovery and learn admission; the shared view displays only accepted state. Real empty catalogs/endpoints remain empty. Bypassed/automation controls display their score state rather than invented scalar defaults. Accepted trajectory data is drawn with source timing and independently scaled channels, never an oscillator animation.

## State, Ownership, and Lifecycle
MainActor owns transient SwiftUI state; app retains accepted data and tasks. Closures do not retain platform graph objects inside render callbacks. Presentation caches change only when accepted identity/data changes.

## Failure, Concurrency, and Constraints
App errors are shown explicitly; views perform no file I/O or audio rendering. Source revision invalidates stale selection/Learn. Catalog and trajectory bounds remain runtime-owned.

## Verification and Change Impact
Physical iPad control dismissal/reopen/real audio changes and MIDI/host workflows must pass. Mac regression verifies unchanged action bindings and exact presentation. Parent integration owns full geometry and lifecycle.
