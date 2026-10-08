# Native Interface

## Purpose and Scope
The production iPad composition. Parent: [App](../DESIGN.md). Composes Deck, Master and host adapters with shared [UI](../../../Sources/MusicPlaygroundUI/DESIGN.md). No additional child component.

## Responsibilities and Boundaries
Owns MainActor view state, persistent deck colors, cancellable user commands, file export presentation and native touch adapters. Documents own buffers and disk authority; Audio owns accepted audio, routes, DSP, recording and host lifecycle. Arbitrary Swift compilation remains a separate task and surfaces compilerRequired without changing the accepted loop.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Documents](../Documents/DESIGN.md) | depends on | select/edit/save/shared identities | Real package workspace | Selecting a tab never loads audio |
| [Audio](../Audio/DESIGN.md) | depends on | accepted loop/control setters, stop | Independent decks and master | Publish only admitted state |
| [Host](../Audio/Host/DESIGN.md) | depends on | discovery/configure/Learn/AU/settings | Actual hardware hosting | Cancellable selection and restoration |
| [UI](../../../Sources/MusicPlaygroundUI/DESIGN.md) | depends on | presentation protocols and slots | Exact shared Mac drawing | Slots evaluate current observed state |

## Architecture
```text
MusicWorkspaceView -> DocumentSidebar + DocumentEditor
                  -> DeckRack -> NativeDeckView -> shared Deck/Effect/Wave
                              -> NativeMasterView -> shared MasterStrip
NativeControlsView -> AudioDeck + DeckHost -> shared ControlKnob/MIDIOptions
NativeCueButton/NativeScratchView -> actual touch phases -> AudioDeck
```

## Contracts and Invariants
Both decks expose color, load, play/pause, momentary CUE, BPM/TAP/SYNC, headphone cue, FX, EQ, gain, filter/space and full host controls. Shared rack stacks at narrow widths and scrolls without removing operations. Editor identity, undo and audio survive sidebar/layout changes. Source compilation failure preserves the previous accepted audio. Results describe accepted PCM metadata, never edited-source guesses.

## Runtime Flows
Startup opens the real project then prepares its supported selected score without starting playback. Play activates the session before transport. CUE touch-down activates with a held-token guard; touch-up/cancel releases it. Scratch activates with the same gesture-lifetime guard, transfers signed movement to the engine and releases inertia on lift. UI snapshots are sampled at 30 Hz; no analysis, file I/O or UIKit mutation executes on the audio callback.

## State, Ownership, and Lifecycle
AudioWorkspace and DocumentWorkspace live above responsive layouts. Native momentary controls own held state, invalidate on dismantle and never restart after lift. Lifecycle stop cancels owned work, releases scratch/CUE and deactivates the session. Export uses an exclusive app Documents destination; the system export picker owns the user's external destination. Recording failure remains visible; discard removes only its owned take. Master recording presents an Identifiable saved result through sheet(item:); the sheet consumes that admitted URL directly, so separate visibility and optional-content state cannot produce an empty save screen.

## Failure, Concurrency, and Constraints
User command failures are surfaced in alerts or host diagnostics, cancellation is not success. Actual disconnected routes stop playback; unavailable independent cue ports are not synthesized. Supported audio/control bounds are owned by Audio/Rendering. Accepted pattern and result anchors are validated on adoption, then transformed through the shared SourceLineMap using committed UTF-16 edits. Insertions move accepted results; deletion of an anchored expression omits that anchor. Editing never substitutes new audio or guessed result metadata.

## Verification and Change Impact
Physical UI workflows must operate both decks, FX/EQ/filter, real waveform scratch, master mix/recording, MIDI/AU choices, accepted results/mutes, text highlighting/undo and sidebar restoration in both landscape orientations. The app declares landscape-only iPad orientation support; attempted portrait rotation must retain a landscape workspace. App-hosted behavioral tests cover command cancellation, failed edited-source load, tab reorder and result source identity. Mac regression tests and normal/fullscreen inspection cover shared rendering changes.

Workspace tint is scoped to the deck/editor detail column. The project sidebar inherits the system default selection appearance rather than the music-control mint tint.
