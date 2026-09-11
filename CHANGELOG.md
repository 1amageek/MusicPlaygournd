# Changelog

## Unreleased

- Update the host, evaluator, completion service and new-project templates to SwiftMusic 0.5.1 Preview.
- Reduce synthesis scheduling overhead while preserving exact PCM output.

## 0.3.0 — Preview — 2026-09-11

Source release using SwiftMusic 0.5.0.

- Independent A/B decks, shared source documents, separate tabs and evaluation workers, TAP/Sync, and a central equal-power crossfader.
- Two generated musical starters, per-deck EQ/Gain and Filter/Space controls, selectable deck palettes, and shared 3D vectorscope trails.
- Bidirectional Wave scratching while playing or paused, inertial release, and a centered scrolling waveform.
- Selectable main/headphone outputs and independent deck CUE.
- Play Mode with independent left/right 18% scratch regions and a bottom 20% crossfader region at 3x sensitivity. Resting touch starts remain tracked so subsequent motion can operate alongside another edge.
- Space toggles both decks; standalone left/right Command and Option taps control deck transport and headphone CUE. Escape restores the cursor.
- Compact tabs with cross-deck loading and file dragging, editor viewport clipping, queued-play cancellation, semantic-service recovery, and more readable controls and monitor colors.

Validation: 26 focused tests passed, covering generated SwiftPM projects, independent evaluation workers, shared document editing, native deck mixing/Sync/CUE, scratch inertia, transport keys and edge contact routing.

This remains a source preview requiring Swift 6.4 and Xcode command-line tools. No notarized binary is provided. Physical multi-contact trackpad behavior is not fully verified: the resting-contact fix passes a native-event regression, but still needs hardware confirmation. Earlier broad editor tests reported string/comment highlighting and restored horizontal-scroll failures; these remain known issues outside this release's focused validation.

## 0.2.0 — Preview — 2026-09-10

Source release using SwiftMusic 0.5.0.

- Folder-based SwiftPM projects with a compact welcome screen, a generated playable starter, persistent dependency navigation, and cached package preparation.
- A 140 BPM starter with nested sounds, four tracks, and both Playground-owned and explicit `@State` sliders, with credit to Switch Angel.
- SourceKit semantic highlighting, five configurable editor themes and font sizing, Japanese input and selection fixes, comment toggling, and improved tabs, scrolling and line numbers.
- Faster live track mute, Space-key transport outside the editor, and three-finger tempo gestures scoped to the BPM control.
- Independent Wave, Spectrum and Vectorscope popovers; spectrum EQ response curves and reset; vectorscope balance/reverb control and reset.
- A live stereo-linked master compressor in Wave with threshold, ratio, attack/release, aligned pre/post traces, gain reduction, bypass and reset. Compression also reaches recordings.
- Refresh cached project build plans when bundled host source files change.

Validation: the current generated-project compilation/rendering and both slider paths passed against public SwiftMusic 0.5.0. The compressor passed eight focused dynamics/PCM checks and a native hardware recording check. The packaged app played the matching starter with zero reported errors/dropouts; compressor settings and reset were exercised through native accessibility actions.

Verification limits: physical mouse dragging in the compressor popover and physical three-finger trackpad input still need manual confirmation. These limits are not claims of verified gesture behavior. This remains a source preview; build locally with Swift 6.4 and Xcode command-line tools. No notarized binary is provided.


## 0.1.0 — Preview

Initial standalone source release, using SwiftMusic 0.3.0.

- Native Swift editor with file tabs/sidebar, semantic completion, indentation, formatting and per-document Undo/Redo.
- Inline, side and bottom rhythm results with source token highlighting and per-track mute.
- Preprepared `@State` switch pads inside and around Tracks.
- Native playback, global tempo/volume/effects, XY control, stereo waveform and spectrum monitoring.
- Optional performance/MIDI Learn and recording controls.
- Explicit compiler/runtime diagnostics and retention of the previous valid audio after failed edits.

Requires a local Swift 6.4 toolchain and Xcode command-line tools. This preview is released as source; no notarized binary is provided.
