# Shared MusicPlayground Interface Requirements

## Authority and Scope

The production two-deck macOS workspace is the reference. This contract supersedes the previous shared-UI milestone, which extracted shells but did not reproduce its controls or editing. The user requires full shared UI, editing and audio operations. Arbitrary Swift compilation and execution on iPad is a separate task, explicitly confirmed on 2026-10-08.

Every requirement below is mandatory. Native hardware capabilities have explicit admission conditions, not implementation shortcuts. A missing implementation cannot satisfy a requirement by hiding a control, showing an unavailable placeholder, returning synthetic data or testing only construction. A hardware condition is checked against the actual route/catalog and reported to the user. A compiler-dependent action must explicitly request the separate compiler capability and preserve the last accepted score.

## Reference and Verification Model

```text
Requirement ID -> shared component -> native adapter -> real document/audio operation
                       |                                    |
                       +------------ actual UI ------------+-> behavioral evidence
```

macOS reference: `Sources/MusicPlaygourndApp/Editor/ContentView.swift`, `DeckHeaderView.swift`, `FileSidebarView.swift`, `FileTabsView.swift`, `CodeEditor.swift`, `EditorTheme.swift`, `HeaderXYPad.swift`, `SpectrumEqualizerView.swift`, `WaveCompressorView.swift`, `VectorscopeControlView.swift`, `LiveControlsView.swift` and `DeckWorkspace.swift`. These paths define existing behavior; their corresponding DESIGN.md files own implementation contracts. [Shared UI design](../Sources/MusicPlaygroundUI/DESIGN.md) owns the component hierarchy.

## Workspace and Sidebar

| ID | Required behavior | Acceptance evidence |
|---|---|---|
| W01 | Native two-column sidebar/detail workspace; the deck rack is above tabs/editor and diagnostics. No replacement monitor sidebar or permanent debug footer. | Side-by-side actual Mac/iPad images with every major region identified. |
| W02 | Sidebar visibility toggle remains reachable in normal, fullscreen and iPad window layouts; changing visibility preserves editor identity, source, selection, undo and audio. | Hide/show while editing and playing; identical retained state. |
| W03 | Geometry, spacing, typography, dark backgrounds, separators and A/B accents come from shared views/styles. Narrow layouts retain all controls through explicit adaptive layout, without clipping or dropping operations. | Landscape, portrait and reduced-width window checks; all controls reachable. |
| S01 | Sidebar displays the selected project's expandable folder/source tree and dependency tree, including package manifest and supported text documents. | Expand/collapse directories; select actual files; dependency documents are read-only. |
| S02 | Filter preserves matching descendants and ancestors; clear restores the list. Refresh reports failures and retains the previous listing as stale. | Nested-file filter, clear, refresh and real filesystem failure. |
| S03 | New/open project, target selection, refresh and numbered new Swift file are reachable from the plus menu. New files are created immediately in the project's source directory with no overwrite. | Create two files, verify names/bytes/listing; open/import project; collision preserves original bytes. |
| S04 | File selection opens/selects a shared document buffer, preserves dirty edits and does not evaluate or replace audio. | Switch dirty tabs during playback; selected source changes and accepted audio does not. |

## Editor

| ID | Required behavior | Acceptance evidence |
|---|---|---|
| E01 | Real editable native text view wrapped by SwiftUI; monospaced font defaults to 12 pt, 4 pt line spacing, four-space indentation, matching gutter/background/insertion/selection colors. | Actual native view properties and editing screenshot. |
| E02 | Swift highlighting covers keywords/modifiers, type names, function calls/declarations, properties/parameters, numbers, strings, raw/multiline strings, interpolation and nested comments. The five Mac palettes (Midnight, Light, Dark, Dracula, Solarized Dark) are shared exactly. No regex-only imitation or precolored bundled-source fixture. | Parser-derived token ranges, Unicode/UTF-16 boundaries, actual text attributes and screenshot; edit changes token coloring. |
| E03 | Highlighting uses the current document/source snapshot, avoids stale results and IME marked text, and preserves selection/scroll/undo. Mac retains SourceKit semantic classification; iPad uses an explicit native syntax parser, without claiming compiler/type-checker semantics. | Rapid edit/document switch; marked-text and Unicode tests; selection/undo preserved. |
| E04 | Independent document tabs for A and B show active accent underline, filename/type icon, dirty dot, close control and audible-document marker. Selecting, reordering/loading and closing preserve other buffers. | Open/edit/switch/save/reopen/close-cancel with two files and two decks. |
| E05 | Native undo/redo, cut/copy/paste, selection, hardware-keyboard editing, indentation, line numbers and vertical/horizontal scrolling work. Theme/font changes do not recreate buffers. | Real keyboard/UI operations and exact saved bytes. |
| E06 | Save/open/import/new project/file actions report typed failures. Dirty close offers Save/Discard/Cancel and respects cancellation. Settings are retained. | Dirty close/cancel/save; failed save retains dirty source; relaunch persistence. |
| E07 | Inline results, side timeline and bottom overview are selectable; rows, mute buttons, musical events and playhead refer to accepted evaluated metadata and actual transport. | Three layout selections during playback; track mute changes actual output. |
| E08 | Diagnostics are collapsible and errors visible; source highlights/reveals use real ranges. Parsing diagnostics are identified as parsing, not compilation. Editor changes do not claim a new accepted score. | Invalid edited syntax; diagnostic reveal; last accepted score continues. |
| E09 | Completion/format commands retain native editor state. iPad offers syntax formatting from the actual parser and only accurate supplied completion metadata; compiler-dependent completion is explicitly distinguished. | Format/undo and completion insertion; error/cancellation retain text. |

## Decks, Effects and Wave

| ID | Required behavior | Acceptance evidence |
|---|---|---|
| D01 | Both Deck A and B use the complete shared header: color, load/name menu, play/pause, momentary transport CUE, BPM, TAP, SYNC, headphone CUE, FX and controls. No substitute Stop button or disabled second deck implementation. | Actual images plus activate every operation on both decks. |
| D02 | Both decks own independent accepted music, play position and transport. Play/pause resumes, momentary CUE obeys the reference press/release behavior, and one deck can stop without stopping the other. | Real independent audio/clock tests; CUE down/up; mixed output. |
| D03 | BPM is editable, TAP derives tempo from tap intervals, SYNC adopts the playing peer's tempo and aligns beat position. Invalid values report errors and retain accepted state. | Tempo/beat measurements; deterministic TAP; invalid BPM; actual SYNC. |
| D04 | Deck colors are selectable and persisted; all header/tab/FX/wave accents follow the selected deck. Loading chooses actual content and preserves the peer. Loading edited/uncompiled source requests the separate compiler capability and cannot silently play a bundled fallback. | Color persistence, load/cancel/error, peer remains audible. |
| D05 | Gain, parametric EQ response/spectrum and the bipolar filter/reverb XY pad share exact visual/gesture implementations and change actual deck DSP. Reset and accessible adjustments obey the Mac mappings. | Real PCM/graph response, drag/reset on both decks and isolation tests. |
| F01 | Phaser, Chorus and Flanger popover, beat rate, depth, feedback, mix, XY mapping and reset use the shared full controls and the same streaming DSP semantics as Mac. | Physical native DSP output, parameter changes while playing, bypass and A/B isolation. |
| F02 | No source rewrite, recompile or playback restart occurs for live FX/EQ/filter/gain changes. Invalid updates are rejected with a visible error and accepted values retained. | Continuous playhead/output while changing parameters; rejected update rollback. |
| V01 | Waveform shows accepted PCM peaks scrolling around the fixed center playhead at the real transport position. Actual realtime wave/spectrum/vectorscope use audio samples, never generated animation. | Output capture and playhead advance/pause/restart tests; inspect live images. |
| V02 | Waveform opens the shared master compressor. Threshold gesture, enabled state, ratio, attack, release, pre/post traces and gain reduction correspond to the real master processor. | Compressor changes actual captured PCM; pre/post frames aligned; reset/bypass. |
| V03 | Scratch gestures preserve the reference direction and inertia; paused scratching is audible without entering ordinary playback. Touch and keyboard/accessible alternatives preserve semantics. | Gesture -> actual reverse/advance PCM and transport; release behavior. |

## Master and Host Operations

| ID | Required behavior | Acceptance evidence |
|---|---|---|
| M01 | Center master region contains actual A/B vectorscopes, crossfader, master volume, headphone settings and master recording. Crossfader has centered reset and accessible adjustment, and applies equal-power A/B gains. | Captured output at A/center/B; volume response and retained peer; actual shared view. |
| M02 | Vectorscope popover exposes actual A/B samples, master balance and space; changes affect real output. | Balance/reverb capture and reset. |
| M03 | Headphone CUE settings show real available output routes, cue deck selection, cue/master mix and level. Independent headphone output only activates on hardware/platform that exposes independently routable outputs. Never send pretend cue audio to the main speaker. | Route discovery and unsupported-hardware admission on connected iPad; separate-route proof when hardware is available. |
| M04 | Master recording starts only with actual output, writes a valid WAV, stops/saves/discards correctly, enforces duration and reports write/cancellation failure. | File decode and nonzero PCM; discard removal; duration/failure tests. |
| H01 | Deck controls expose accepted live parameter descriptors and preserve values/targets after dismissal. Sliders, switches and track mute affect actual accepted music without source edits. Compiler-derived controls require accepted metadata. | Change/reopen, audio response, source unchanged. |
| H02 | MIDI input/output, note output, clock and Learn are in the initially collapsed options section; actual native endpoints and bindings persist. | Native endpoint enumeration, loopback input/output/clock and Learn state. |
| H03 | Audio Unit selection uses the real platform catalog, bypass/rollback and lifetime behavior. An empty native catalog is represented explicitly, not filled with fake plugins. | Enumeration; actual native unit load/render/bypass/error where installed. |
| H04 | Stem export and settings save operate on accepted music and preserve running playback; cancellation/failure is explicit. | Decode exported stems, manifest/settings round trip and cancellation. |

## Global Invariants and Completion

| ID | Invariant | Evidence owner |
|---|---|---|
| G01 | UI and graph control remain MainActor-owned; preparation stays off the UI path; audio callbacks own no UI, file I/O or task work. Existing Mutex/atomic ownership is preserved. | Native app/runtime designs and focused race/cancellation tests. |
| G02 | Stop/background/interruption/route loss invalidate pending work and release audio resources; stale completion cannot restart audio. | Physical lifecycle and cancellation tests. |
| G03 | Mac editing, semantic highlighting, fullscreen geometry, documents and audio behavior regressions remain passing. | Focused Mac tests plus actual normal/fullscreen UI comparison. |
| G04 | Requirements map to implementation and successful behavioral evidence. Missing requirements remain incomplete; tests/screenshots proving only a subset cannot close the task. | PROGRESS.md and the evidence mapping below. |

## Implementation and Evidence Mapping

Each sprint records implementation paths and behavioral evidence here after the paths are verified. The requirements above remain fixed; a change in scope requires user resolution. All requirements are currently open for the corrected parity task, including behavior present on Mac but absent on iPad. Native parser/formatter is independent of the excluded native compiler.

| Requirements | Implementation owner | Evidence |
|---|---|---|
| W01-W03, S01-S04 | Shared Workspace/Sidebar, native document adapters | Pending |
| E01-E09 | Shared Editor, AppKit/UIKit adapters and document owner | Pending |
| D01-D05, F01-F02, V01-V03 | Shared Deck/Effect/Wave, native transport and DSP | Pending |
| M01-M04, H01-H04 | Shared master/control presentation, native output and host adapters | Pending |
| G01-G04 | Module owners and task integration | Pending |
