# Native Deck Host

## Purpose and Scope
Child of [Audio](../DESIGN.md); no children. Owns per-deck MIDI routing, Learn, hosted AU and document settings; preparation remains with the parent deck.

## Responsibilities and Boundaries
DeckHost consumes HostControls and MIDIServiceProtocol, plus AudioUnitHosting. The parent workspace supplies an awaited session-activation closure before received MIDI transport starts. The host never edits source or manufactures descriptors, plugins or endpoints. Existing DocumentHostStateStore and MIDISessionRoute implementations are compiled into both apps through explicit file references; their Mac ownership and binary settings contract remain unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Audio](../DESIGN.md) | parent | HostControls, activation | accepted score and graph lifetime | MainActor control adapter; source revision invalidates Learn |
| [MIDI](../../../../Sources/MusicPlaygourndCore/MIDI/DESIGN.md) | depends on | MIDIServiceProtocol | actual endpoints, bounded scheduling, shutdown | routing rollback; paused clock flushes notes |
| [AudioUnits](../../../../Sources/MusicPlaygourndCore/AudioUnits/DESIGN.md) | depends on | AudioUnitHosting | native catalog, load/state/bypass | cancellation and graph admission preserve prior unit |
| [Mac Editor](../../../../Sources/MusicPlaygourndApp/Editor/DESIGN.md) | coordinates with | DocumentHostStateStore/MIDISessionRoute | same persisted host schema | canonical document and adopted source digest |

## Architecture
```text
HostControls <- MainActor DeckHost -> MIDIServiceProtocol -> CoreMIDI
      |                 |                  |
accepted catalog    AU hosting       stream + 50ms clock scheduling
                        |
              document host state store
```

## Contracts and Invariants
MainActor owns route, Learn and task state. Weak controls are accessed only on MainActor; graph is retained for host lifetime. Routes validate actual endpoint direction before mutation and roll back on failure. Learn maps validated CC through the accepted descriptor presentation; stale revisions detach bindings. Settings preserve source digest and remap matching semantic addresses to current accepted revision only. No active input means no Learn. Native empty catalog is an explicit result.

## Runtime Flows
Configure stops the previous scheduler, applies route transactionally and starts stream/scheduling. Poll publishes real service health, schedules accepted loop notes/clock from an actual playback anchor and applies received transport through awaited activation. Missing initial clock is reported by the service as unavailable and schedules no notes. Stop updates nil anchor and suspends scheduling. The single claimed event stream remains consumed for service lifetime, discarding events while suspended; resume restarts scheduling without reclaiming a terminated stream. Shutdown cancels consumption, finishes the service stream and awaits both tasks. The native host bundle declares the audio background capability required to create real virtual MIDI endpoints; scene lifecycle still stops audio on inactivity.

## State, Ownership, and Lifecycle
Workspace owns hosts; each host owns one service, one event task and one scheduling task. Configuration and shutdown serialize on MainActor; generation rejects suspended configuration after stop. Learn bindings use the shared store's bounded admission; immutable settings writes remain at a user action boundary. Audio graph lifetime remains parent-owned.

## Failure, Concurrency, and Constraints
All endpoint, AU, file and control errors remain visible. Restore validates endpoints and source/control compatibility before mutation; failed route restores prior route and reports rollback failure. Settings cannot claim an effect or Learn binding absent from current capabilities. Background cleanup flushes owned MIDI notes without resuming audio.

## Verification and Change Impact
Physical native endpoint loopback must exercise CC Learn, note/clock sending, received transport, stream shutdown and settings round trip. Native AU catalog/load/render/bypass/invalid-ID checks establish actual graph use. Parent integration verifies session activation and lifecycle; existing Mac host tests verify shared schema remains compatible.

AU selections are owned cancellable tasks, checked against host lifecycle generation. Suspend cancels and awaits the selection before releasing the session; a delayed native instantiation cannot attach or restart playback after stop. The existing engine's cancellable native request owns timeout/callback completion. Selection is rejected while recording; unchanged accepted unit is retained on failure. UI calls this host entry point, not the raw engine selection method.

Cancel Learn clears only the pending learning address and preserves existing assignments. Remove Binding explicitly deletes the selected assignment. Shared presentation displays the selected accepted control and its current assignment.
