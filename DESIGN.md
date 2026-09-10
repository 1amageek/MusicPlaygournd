# MusicPlaygournd

## Purpose and Scope
Standalone macOS 15+ live Swift editor; the native package owns the app and host runtime. Parent: none. Children: [Declarations](Sources/MusicPlayground/DESIGN.md), [Core](Sources/MusicPlaygourndCore/DESIGN.md), [App](Sources/MusicPlaygourndApp/DESIGN.md).

## Responsibilities and Boundaries
Uses the exact public SwiftMusic 0.5.0 package from GitHub. The build bundles the host source and matching runtime objects. Evaluation and completion workspaces resolve the same public SwiftMusic version rather than assuming an adjacent checkout. Editor code is trusted local Swift, evaluated in a separate process, not a security sandbox. Playback, transport, rendering, file editing, diagnostics, and visualization belong to this package.

## Related Designs
Use the parent/child links above. Dependencies: SwiftMusic owns event semantics; Core owns rendering/playback/evaluation contracts; App consumes Core.

## Architecture
```text
Swift source -> compiler AST + bounded evaluation -> PCM + pattern/result anchors -> bar-boundary adoption -> audio + aligned rows + analyzers
```

## Contracts and Invariants
The source timeline uses the adopted immutable loop and latency-adjusted transport cursor. The master waveform and spectrum use the bounded post-effect capture owned by [Playback](Sources/MusicPlaygourndCore/Playback/DESIGN.md). Player rows use compiler provenance and native editor geometry: pattern anchors own side alignment and active-token highlighting, while compiler-AST expression-end lines place inline results after all modifiers. Semantic completion uses a dedicated SourceKit-LSP workspace and never owns evaluation or playback state. New edits invalidate pending updates immediately. Failure/stale results never replace current audio or visualization. BPM and master effects are live playback controls separate from code evaluation; the editor prepares at a fixed 120 BPM base. Unsupported backend features fail explicitly.

## Failure, Concurrency, and Constraints
Failure is reported as a diagnostic or typed error; the last adopted loop survives edit failures. Mutable host state is MainActor- or Mutex-isolated.

## Verification and Change Impact
Run core behavioral tests, real compiler good/bad/recovery checks, AVAudioEngine output checks and live UI. Scripts/build-app.sh bundles source for evaluation and records the installed Swift executable. App runtime needs Swift 6.4 and Xcode command-line tools including Python3. Version 0.2.0 is a source preview release; no prebuilt notarized binary or App Store distribution is provided.

SwiftPM project management is owned by the App editor and project evaluation/completion by Core Evaluation. Package.swift remains the source of target/dependency/resource membership. See the corresponding child designs for the project snapshot and last-good-audio contracts.

The [MusicPlayground declaration library](Sources/MusicPlayground/DESIGN.md) owns host-only slider declarations and state connections. It depends on SwiftMusic and is consumed by the Core evaluation adapter and Editor.

## Two-deck performance

The editor workspace owns two deck sessions and one shared source-document store. Deck A and B own separate selected-tab lists, loaded entry identities, evaluator workspaces, revision counters, retained Music/State instances, transport, tempo, track overrides and deck EQ/gain. File URLs identify shared text, dirty state, saving and undo; a deck assignment identifies a Music type in a package target/file. Selecting an editing tab never replaces the loaded entry. Loading a new entry prepares a candidate and retains the previous audible entry on failure. A successful shared-source edit updates each affected deck through its existing last-good adoption protocol, preserving independent performance values where compatible.

```text
Shared source documents -> Deck A evaluator/State -> A transport, EQ, gain --+
                        -> Deck B evaluator/State -> B transport, EQ, gain --+-> crossfade -> master balance/reverb/compressor/volume -> output tap/recording
```

One native audio graph owns output, the compressor, recording and master analyzers. A deck pause stops only its source transport; the other deck and output graph continue. The mixer uses equal-power crossfade endpoints with explicit exact zero at the opposite endpoint; deck gain is independent. Gain transitions reuse bounded smoothing. Mono inputs are not widened by visualization. The master vectorscope consumes the post-mix stereo output. There is no extra long PCM history or realtime UI computation.

TAP measures monotonic inter-tap intervals per deck, admits 40–240 BPM, uses a bounded recent interval window, and restarts after inactivity. It adjusts BPM without rebuilding source. Sync is an explicit one-shot BPM and beat-phase alignment to the other deck, with source-output latency accounted for; it fails visibly if the reference is not playing or the receiving deck has no valid loop. It does not silently restart either deck or reinitialize State.

The header contains two independent decks and a central scope above the crossfader. Each deck has BPM, TAP, Sync, transport, EQ and gain. Left/right tab groups can contain the same file. Only the active editing group renders the wide editor. A/B color pickers persist validated colors and drive deck waveforms, tab playing indicators and fade endpoints; syntax themes remain independent and text labels identify A/B without color.

Verification owners: Playback verifies native mixed PCM, exact endpoints, independent pause/rate/state, smoothing, phase sync and master recording; Evaluation verifies separate workers with same-source State isolation and distinct entry selection; Editor verifies shared edits/undo/save, loaded-versus-selected distinction, failed-load retention, independent tabs, tap timing, color restoration and shutdown. Existing single-deck clients retain their behavior. Physical gestures are not marked verified from type checks or accessibility actions alone.
