# Changelog

## 0.5.1 — Preview — 2026-09-12

- Show compiler issues directly in the editor with red gutter markers, underlines, subtle row backgrounds and trailing inline messages.
- Click an inline message or issue-list entry to open the source file and select the compiler-reported location. Errors precede warnings, and full build output starts collapsed.
- Map UTF-8 compiler columns to Unicode editor positions and retain exact source snapshots; changed text, unknown files and ambiguous locations never receive stale or guessed navigation.
- Include ordinary Swift syntax/type failures and package-manifest reload diagnostics while preserving the previous valid music after failed edits.

Validation: four focused tests passed, covering real compiler errors, cross-file navigation, Unicode/EOF and ambiguous locations, native annotation lifecycle, and retained audio after typed and ordinary compiler failures. The packaged app was visually verified with a real line-7/column-19 error; clicking its inline message selected the failing character and opened details. SwiftMusic remains pinned to public 0.5.1. This is a source preview requiring Swift 6.4 and Xcode command-line tools; no notarized binary is provided. Earlier documented limitations outside editor diagnostics remain unchanged.

## 0.5.0 — Preview — 2026-09-12

- Choose when source edits become audible and apply replacements with seamless crossfades.
- Cache SwiftPM binary-directory discovery between source edits to avoid repeated process startup.
- Track cumulative scratch position and use band-limited variable-speed playback in both directions, including while paused. Scratch bypasses pitch preservation; normal tempo changes retain it.
- Preserve recent hand velocity through finger release and smoothly launch inertia. Fast finite gestures retain their displacement while audible read speed stays bounded.
- Keep scratch gestures active when contact count changes between two and three fingers, rebasing the touch centroid to avoid jumps.

Validation: 56 Release integration tests passed across native audio, gesture transitions, inertia, source replacement and deck isolation. Earlier scratch checks verified pitch following speed, exact position return, bounded resampling and PCM lifetime. Physical finger feel is not automated. SwiftMusic remains pinned to public 0.5.1. This remains a source preview requiring Swift 6.4 and Xcode command-line tools; no notarized binary is provided. Previously documented editor and hardware-verification limitations remain outside this release's scope.

## 0.4.0 — Preview — 2026-09-11

- Update the host, evaluator, completion service and new-project templates to SwiftMusic 0.5.1 Preview.
- Reduce synthesis scheduling overhead while preserving exact PCM output. On the measured M4 Max fixture, four-second synthesis dropped from 248 to 70 ms for eight tracks and 490 to 137 ms for sixteen tracks (seven-run Release medians).
- Reuse stable evaluation binaries and compiler discovery, and preserve exact UTF-8 bytes when checking unchanged source files.
- Retain immutable mapped PCM across worker transport and playback, and reuse meter snapshots with bounded ring capture.
- Improve obsolete-render cancellation and reuse oscillator/FFT preparation.

Validation: SwiftMusic 0.5.1 passed 208 Release tests. The host passed 24 synthesis-focused and eight live/native integration tests, followed by 12 dependency/template/completion checks and two packaged-runtime checks. Generated-template native PCM, both Slider paths and actual hardware playback were verified; mapped PCM also passed five prior Address Sanitizer checks. Release packaging and signature are verified locally. This remains a source preview; no notarized binary is provided. The known limitations recorded under 0.3.0 remain outside this performance-focused release.

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
