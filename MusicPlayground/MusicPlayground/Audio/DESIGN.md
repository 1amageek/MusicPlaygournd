# Native Audio Workspace

## Purpose and Scope
Child of [app module](../DESIGN.md); child: [Deck Host](Host/DESIGN.md). Owns two independent accepted scores and native audio-session lifecycle for the UI/audio parity contract. Arbitrary edited-source compilation is a separate capability.

## Responsibilities and Boundaries
AudioWorkspace owns shared AudioOutput, two AudioLoopEngine instances, session activation/deactivation and lifecycle cancellation on MainActor. AudioDeck owns one accepted compiled score, prepared-loop/control metadata, transport presentation and cancellable render work. The existing shared Playback/Rendering/MIDI/AudioUnits sources remain the sole DSP/host implementations. Documents own editable text independently. A load request must match an actual build-time entry or report compilerRequired; it never substitutes a bundled score for edited text.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [App](../DESIGN.md) | parent | scene lifetime | UI composition owns workspace | stop on inactive/interruption/route loss |
| [Playback](../../../Sources/MusicPlaygourndCore/Playback/DESIGN.md) | depends on | AudioOutput/AudioLoopEngine | same two-deck graph, FX, transport, recording and AU | iOS route adapter replaces only HAL device selection |
| [Rendering](../../../Sources/MusicPlaygourndCore/Rendering/DESIGN.md) | depends on | compiled-score render, controls/mutes/stems | bounded off-UI preparation | generation/current accepted identity checks |
| [MIDI](../../../Sources/MusicPlaygourndCore/MIDI/DESIGN.md) | depends on | MIDIServiceProtocol | real endpoints/events/clock | shutdown finishes owned streams |
| [Documents](../Documents/DESIGN.md) | coordinates with | immutable source identity | accepted ID/source snapshot independent of editing | failure retains accepted audio |

## Architecture
```text
Documents -> explicit load -> actual compiled entry -> immutable CompiledSound
                                    |                     |
 MainActor AudioDeck <- guarded prepared result <- detached Rendering
       |     controls/transport         |
       +-> shared AudioLoopEngine A/B -> AudioOutput -> AVAudioSession route
                  |                         |             |
             post-FX meters          master tap/WAV     explicit cue channel map
```

## Contracts and Invariants
Both engines attach before output starts. Each accepted score owns its revision and metadata; edits never change it. Play/pause, CUE, tempo, SYNC, scratch and FX use the shared engine's actual state. UI controls publish values only after native admission succeeds. Render/mute/control changes retain the previous loop until successful guarded adoption. No callback state is replaced by unsynchronized iOS state.

## Runtime Flows
Session category configuration runs in the activation task through an @concurrent function to avoid the SDK's active-session MainActor hang warning; graph control and accepted state remain MainActor. Session activation is awaited before engine start and checked against lifecycle generation. Stop invalidates generations, cancels render/activation work, releases CUE/scratch and stops both decks before awaited deactivation. Concurrent stop shares cleanup; failed cleanup remains visible. Recording/export use actual accepted samples; cancellation and write failures retain audio and report errors.

## State, Ownership, and Lifecycle
MainActor owns graph, controls, pending tasks and UI snapshots. PreparedLoop/CompiledSound values retain immutable PCM across detached preparation. Existing playback/kernel/meter Mutex and atomics own callback state. Session activation has one owned task; stop waits for its completion before deactivation. A/B data is independent; master capture is sampled once per display refresh. At most two decks, 512 peak bins, existing 8192-frame meter rings and bounded render/recording limits apply.

## Failure, Concurrency, and Constraints
iOS uses the actual AVAudioSession output channels and AUAudioUnit channel-map capability; Mac retains HAL devices. Cue requires a distinct stereo channel pair and supported output mapping. Mono/no extra pair is a hardware admission failure, never cue on the main speaker. Route changes invalidate mapping and stop playback. Native catalog/endpoint errors are explicit. Backgrounding does not automatically resume audio.

## Verification and Change Impact
Physical native tests must execute shared source callbacks, actual DSP response and nonzero output, independent A/B play/pause/CUE/SYNC/scratch, invalid control retention, capture/WAV and lifecycle cancellation. Native MIDI loopback/catalog/render tests own host behavior. Shared-engine changes require existing focused Mac DSP/clock/scratch/recording regression. Shared UI integration owns gestures and accepted-document markers.

### Accepted metadata and cleanup boundary
Prepared session/document/catalog metadata remains pending until PlaybackSnapshot reports its submitted revision. Control values remain pending until its override generation is adopted. MainActor refresh publishes metadata together with that snapshot; cancellation cannot falsely publish an unadopted candidate. A bounded two-second adoption wait reports failure without substituting another score. Cleanup attempts recording cancellation, cue release and session deactivation even after an earlier step fails, then reports all failures. Native manual-render tests explicitly stop the initialized engine before switching modes and respect the existing 4096-frame test boundary. SYNC requires both real source transports running and compares their anchors at a common host time.

Stop awaits canceled preparation, control and stem-export tasks, including staging cleanup; shutdown failures remain explicit. Host settings restoration and AU selection also have owned cancellation lifetimes. Each awaited resume/adoption checks workspace or host generation before graph mutation, preventing a suspended caller from restarting work after stop.

Live controls have separate requested and adopted override dictionaries. A newer render includes all validated requested changes and supersedes only the older render task, not independent parameter intent. The latest failed request restores intent to an already queued valid candidate or the adopted snapshot. A revision/lifecycle change invalidates both render completion and its adoption wait. Physical overlapping Track-level requests must retain both values and leave the peer and source unchanged.

Deck FX/EQ/AU and workspace compressor/recording values are observable accepted projections read from the native engine after successful admission or refresh. Computed access to non-observable engine storage is insufficient for SwiftUI publication. Projection storage has no independent mutation authority. UI integration verifies immediate control redraw as well as actual DSP output.
