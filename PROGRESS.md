# Progress

- [ ] TEMPLATE-1 Correct creation to the actual SwiftPM initial template; current custom Session/Resources/Recordings generator does not meet the request; retain existing-path protection; current manifest and generator formatting corrected with four-space indentation and multiline declarations, and SwiftPM metadata is unchanged `depends:none` `parallel:none`
- [x] NAV-1 Native NavigationSplitView/List/DisclosureGroup, unified toolbar, detail-only logs/status and redundant folder strip removal verified by app build and native selection/expansion/visibility checks `depends:none` `parallel:none`
- [x] NAV-2 Bottom status bar removed; native Liquid Glass overlay and all three layout selections verified in the signed app; overlay is owned outside the source scroll view `depends:NAV-1` `parallel:none`
- [x] EDITOR-1 Document visibility and gutter origin corrected with SCROLL-1; native source visibility and existing tab/undo test verified `depends:NAV-2` `parallel:none`
- [x] FOOTER-1 Sidebar footer and collapsed Logs aligned to 36 points; Release build and native divider alignment verified `depends:NAV-2` `parallel:none`
- [x] MUSIC-1 Night Drive six-track starter composed; actual source compiled with live-loop policy, 16 beats/137 events rendered to finite stereo PCM, 32-second preview and app build verified `depends:none` `parallel:none`
- [x] GROOVE-1 Afterhours replaces Night Drive: seven tracks, live compilation/render verified at 16 beats and 99 events, finite PCM peak 0.514, 32-second stereo preview; final template confirmed in built app `depends:MUSIC-1` `parallel:none`
- [x] ACID-1 Deep Current starter follows supplied reference mechanisms: C-minor sixteenths, filter envelope, resonance and event ducking; live renderer validated 16 beats/101 events, finite stereo peak 0.713, 32-second preview; app build passed `depends:GROOVE-1` `parallel:none`
- [x] DECL-1 Inline nonthrowing starter parameters and located diagnostics; app build, byte-identical PCM and actual worker invalid-edit retention verified against local SwiftMusic 41f291a; public 0.3.0 does not contain these APIs `depends:none` `parallel:none`
- [x] SCOPE-1 Independent waveform/spectrum/vectorscope views and header popovers; Release build and real projection check passed; existing PCM ownership and diagnostics preserved `depends:none` `parallel:none`
- [x] SCOPE-INT Native independent opening/closing passed; actual stereo PCM rendered through VectorscopeView; live playback UI check interrupted by user interaction, original playing app preserved `depends:SCOPE-1` `parallel:none`
- [x] SCROLL-1 Normalize saved offsets against native ruler insets; preserve NSClipView constraints and one document sizing owner; gutter overlap regression and existing native editor test passed `depends:none` `parallel:none`
- [x] SCROLL-INT Release build passed; native Deep Current Tribute scrolling to end and back preserves complete line starts; fixed app opened `depends:SCROLL-1` `parallel:none`
- [x] CHROME-1 MusicHeaderView owns native toolbar controls; fixed-height sibling tabs reserve space above the editor; native screenshot confirms nonoverlap `depends:none` `parallel:none`
- [x] CHROME-INT Release build, native source scroll and Package/Session tab switching verified; toolbar and tabs remain fixed `depends:CHROME-1` `parallel:none`
- [x] START-1 Persist SwiftPM project build products and stable augmented manifests while keeping worker/PCM process-local; focused project integration passed with public SwiftMusic 0.4.0 `depends:none` `parallel:none`
- [x] START-INT Actual cold/warm evaluation measured 106.163/5.117 seconds; changed buffers, retained failure behavior and new-project preservation passed; packaged Release build already verified `depends:START-1` `parallel:none`
- [ ] TEMPLATE-INT Verify standard SwiftPM package creation/opening without requiring a custom Session.swift entry, existing-path preservation, and the native navigator flow `depends:TEMPLATE-1,NAV-1,NAV-2,EDITOR-1` `parallel:none`

- [x] COMPACT-1 Gutter gap reduced to 8 points; navigator glyphs use 12-point font in 14-point slots; Release build and native source/sidebar appearance verified `depends:none` `parallel:none`

- [x] CARET-1 Preserve selection and Japanese marked text; pre-fix reproduction fails, focused AppKit composition/commit and document/undo checks pass; packaged Release build passed `depends:none` `parallel:none`

- [x] EDIT-2 Fix URL/comment coloring, resolve saved manifests with stale evaluation cancellation, preserve dirty documents and selection, and move layout menu to tab row; focused behavioral checks passed `depends:none` `parallel:none`
- [x] EDIT-INT Syntax/IME checks passed; real manifest save reload passed in 2.639 seconds; Release build and native tab-row layout verified `depends:EDIT-2` `parallel:none`

- [x] WELCOME-1 Launch welcome and Deep Current/Basic Beat selection use existing project creation/opening; cancellation preserves documents `depends:none` `parallel:none`
- [x] WELCOME-INT Both template creation cases and editor integration passed; native welcome, chooser, save panel, cancellation and generated session observed; Release build passed `depends:WELCOME-1` `parallel:none`

- [x] PREP-1 Publish real dependency/compiler progress with operation-scoped callbacks and navigator activity; readiness and playback contracts preserved `depends:none` `parallel:none`
- [x] PREP-INT Partial-line progress delivered before exit; success/failure and cancellation/timeout cases passed; Release build and native MyLiveSet sidebar compiler progress verified `depends:PREP-1` `parallel:none`

- [x] DEPS-1 Keep declared package dependencies and requirements visible; both template metadata cases and Release build passed, native sidebar retained SwiftMusic 0.4.0 after preparation `depends:none` `parallel:none`

- [x] TREE-1 Resolve dependency checkout locations through SwiftPM and expose expandable package files in existing read-only editor tabs; preserve playback and project buffers `depends:none` `parallel:none`
- [x] TREE-INT Real checkout metadata for both templates and read-only save rejection passed; Release build and native folder expansion/source tabs verified `depends:TREE-1` `parallel:none`

- [x] COMMENT-1 Command-/ toggles focused source lines; AppKit Unicode, CRLF, selection, undo/redo, read-only and IME checks passed; Release app built `depends:none` `parallel:none`

- [x] EQ-1 Three native master EQ bands: filtered PCM, invalid-value retention and independent low-pass verified `depends:none` `parallel:none`
- [x] EQ-2 Spectrum overlay presents three selectable accessible controls and routes accepted targets through SessionModel `depends:EQ-1` `parallel:none`
- [x] EQ-INT Release build and native Spectrum overlay/selection verified; native audio test passed; automated dragging interrupted by concurrent user interaction `depends:EQ-2` `parallel:none`

- [x] PREFS-1 Native Settings provides persisted 12pt default, 10–24pt sizing and five editor palettes; source and IME ownership preserved `depends:none` `parallel:none`
- [x] PREFS-INT Release build and two focused palette/undo checks passed; native Settings changed Midnight 12pt to Dracula 13pt with immediate preview; reviewed for main commit `depends:PREFS-1` `parallel:none`

- [x] LIVE-1 EQ handle gestures, adjustable Q/native response curves and reset; vectorscope XY balance/reverb and isolated center reset implemented and reviewed `depends:none` `parallel:none`
- [x] LIVE-INT Native PCM/response/Q/invalid-value checks passed; Release built; native changed EQ/Q and curves observed, EQ reset and scope 0/50% center reset verified; main commit `depends:LIVE-1` `parallel:none`

- [x] SPACE-1 Route unmodified Space outside text editing to transport; preserve text input, dialogs and modified keys, suppress key repeat `depends:none` `parallel:none`
- [x] SPACE-INT Verify native focus routing and playback toggle, build and push main `depends:SPACE-1` `parallel:none`

- [x] TABS-1 Keep the loaded project visible after closing its last tab; verify native close and reopen `depends:none` `parallel:none`
- [x] TABS-INT Build and verify the workspace remains navigable, then commit to main `depends:TABS-1` `parallel:none`

- [x] RESET-1 Reset vectorscope balance to zero and shared reverb to 0%; verify native values `depends:none` `parallel:none`
- [x] RESET-INT Build and confirm reset through the native popover before main commit `depends:RESET-1` `parallel:none`

- [x] STEREO-1 Add stereo chorus to Deep Current and save the same source in active LivePlayback; retain mono kick, notes, tempo and attribution `depends:none` `parallel:none`
- [x] STEREO-INT Generated source matches active project; PCM Side/Mid 29.2%, native output 26.4%, peak 0.632; Release build passed `depends:STEREO-1` `parallel:none`

- [x] MUTE-1 Pack PCM as Float32 bytes; serialization reduced from 600–750ms to 8ms, exact and legacy decoding verified; bus processing and generation ordering unchanged `depends:none` `parallel:none`
- [x] MUTE-INT Release built; real worker and native audio adoption measured at 312–318ms across four track mutes; unmute restores exact baseline PCM; remaining latency is full rendering `depends:MUTE-1` `parallel:none`

- [x] MUTE2-1 Retain mute-independent boundaries per non-mute control state; bounded 32-buffer cache with Mutex snapshot ownership, exact routing and control invalidation `depends:none` `parallel:none`
- [x] MUTE2-INT Full-render differential and concurrent checks passed; release built; real worker/audio adoption reduced from 312–318ms to 29–41ms, unmute exact; native project mute/unmute verified with zero errors `depends:MUTE2-1` `parallel:none`

- [x] SLIDER-1 MusicPlayground declarations support explicit State and retained automatic values; finite bounds and actual gain/filter PCM verified; SwiftMusic remains unchanged `depends:none` `parallel:none`
- [x] SLIDER-2 Retained worker updates both forms without Swift recompilation; source-line insertion preserves values and rejected updates retain PCM; SDK probe measured 43ms for the short fixture; fixed switch-bank combinations fail explicitly `depends:SLIDER-1` `parallel:none`
- [x] SLIDER-3 Native sliders follow code glyphs without text/selection/undo changes; continuous changes adopt an in-flight value and then the latest value through AVAudioEngine `depends:SLIDER-2` `parallel:none`
- [x] SLIDER-INT Focused Swift Testing, bundled worker probe, native AppKit actions and AVAudioEngine adoption passed; release app built; manual screen inspection unavailable while Mac is locked `depends:SLIDER-1,SLIDER-2,SLIDER-3` `parallel:none`

- [x] CREATE-1 Removed template selection and presentation state; New Project uses native naming and the existing transactional default generator; creation errors use a native alert `depends:none` `parallel:none`
- [x] CREATE-INT Existing package generation/protection test and release build passed; native QuickStart creation directly opened Sources/QuickStart/Session.swift without a template chooser `depends:CREATE-1` `parallel:none`

- [x] STARTER-1 Default session teaches nested Sounds and both slider forms; synth return owns its gain, nonperiodic chorus removed; generated project rendering and slider PCM changes verified `depends:none` `parallel:none`
- [x] STARTER-INT Generated SwiftPM project and live slider PCM checks passed (76.8s); release build passed; final source displayed with two sliders, four inline tracks and active playback in the native editor `depends:STARTER-1` `parallel:none`

- [x] README-1 Rewrote the user guide for Swift 6.4, composition, performance controls and projects; embedded the supplied screenshot unchanged `depends:none` `parallel:none`
- [x] README-INT Checked current editor/control entry points, all relative links and exact screenshot bytes; documentation-only diff reviewed `depends:README-1` `parallel:none`

- [x] MANIFEST-1 Retain the loaded manifest and graph across navigation and unchanged saves; manifest buffers apply on save; failed reloads retain the prior snapshot `depends:none` `parallel:none`
- [x] MANIFEST-INT Native SessionModel with real SwiftPM verified navigation, unchanged file timestamps, reverted edits and changed-package reload (2.4s); release app build passed `depends:MANIFEST-1` `parallel:none`

- [x] REL050-1 Published SwiftMusic 0.5.0 Preview at cc5d9d2; URL-only manifest and tag/main identity verified; 205 library and 7 host tests from the unchanged implementation remain valid `depends:none` `parallel:none`
- [x] REL050-2 Updated app, evaluation/completion manifests, new-project template, tracked example, README and design versions to 0.5.0 `depends:REL050-1` `parallel:none`
- [x] REL050-INT Public tag resolved; fresh project compilation/rendering and slider PCM changes plus real SourceKit completion passed (2 tests, 79.7s); release app build and bundled runtime digests verified `depends:REL050-1,REL050-2` `parallel:none`

- [x] COLOR-1 Replace fixed-name coloring with SourceKit semantic tokens for project and standalone documents; preserve exact source/UTF-16 mapping, document isolation, completion serialization, cancellation and bounded lifecycle `depends:none` `parallel:none`
- [x] COLOR-2 Apply token categories through all five themes without modifying characters, selection, undo or marked text; verify actual SourceKit output and native editor behavior `depends:COLOR-1` `parallel:none`
- [x] COLOR-INT Release app and starter/Settings visually verified; real SourceKit, UTF-16, native editing and stale-response checks passed `depends:COLOR-1,COLOR-2` `parallel:none`

- [x] TEMPO-1 Move gesture ownership to the BPM view; accept three-finger horizontal motion only inside its visible bounds, preserve native editing/scrolling and existing tempo deltas `depends:none` `parallel:none`
- [x] TEMPO-INT Native region/lifecycle check passed; Release app built and FirstLight reopened; physical three-finger input requires manual confirmation `depends:TEMPO-1` `parallel:none`

- [x] WELCOME-1 Match the observed Xcode welcome hierarchy with a compact 480×360pt startup view; preserve existing new/open/cancel/error routes and independently resizable editor content `depends:none` `parallel:none`
- [x] WELCOME-INT Release build passed; native startup is 480×360pt content (480×388pt including title bar), New Project cancellation retains welcome, FirstLight opens at editor minimum with toolbar restored `depends:WELCOME-1` `parallel:none`

- [x] WELCOME-FIX-1 Restore 1160×760pt editor size on welcome-to-workspace transition and give welcome action labels readable fixed sizing; retain user resizing after entry `depends:none` `parallel:none`
- [x] WELCOME-FIX-INT Release build passed; native screenshots verify full welcome labels and FirstLight workspace at 1160×760pt `depends:WELCOME-FIX-1` `parallel:none`

- [x] COMP-1 f9c0f83: live stereo-linked compressor; focused PCM and native recording checks passed `depends:none` `parallel:none`
- [x] COMP-2 Wave controls, pre/post traces and bounded telemetry connected; native accessibility changes and reset verified during playback; bundled source inventory and root manifest fingerprint restore existing cached-project builds `depends:COMP-1` `parallel:none`
- [ ] COMP-INT Release build and existing FirstLight playback passed with zero errors/dropouts; native controls produced 18 dB reduction and reset to bypass; PCM/recording/revision checks passed; physical mouse drag remains unverified because automation coordinates do not reach the popover `depends:COMP-1,COMP-2` `parallel:none`

- [x] REL020-1 App 0.2.0 (2), source-preview documentation and public SwiftMusic 0.5.0 verified; Release build, runtime artifact digests and code signature passed; unchanged template/PCM checks retained `depends:none` `parallel:none`
- [x] REL020-2 Published 0.2.0 source-preview tag and GitHub Release at 260a49b with validation limits `depends:REL020-1` `parallel:none`
- [x] REL020-INT Remote main and peeled 0.2.0 tag matched 260a49b at publication; published preview notes, app 0.2.0 (2), runtime digests and signing verified `depends:REL020-1,REL020-2` `parallel:none`

- [x] DJ-1 Defined shared-document, independent-deck and single-output contracts (e05e6d4) `depends:none` `parallel:none`
- [x] DJ-2 Shared output implemented (43e08e4); native PCM verified crossfade endpoints, pause isolation, master balance/reset; hardware clocks verified Sync across different rates and deck taps `depends:DJ-1` `parallel:none`
- [x] DJ-3 Independent editing/evaluation implemented (d60e6e4); separate workers/caches verified same-file State isolation, explicit Alternate entry and failed-load retention; shared-buffer edits/save/discard/tab-close and TAP checks passed `depends:DJ-2` `parallel:none`
- [ ] DJ-4 Complete accepted visuals and automatic file loading; scope output measured at correlation 0.999834 and Side/Mid -35.7 dB; scope now uses the existing 8192-frame history and horizontal A/B gradient, native verification pending; compact tabs updated to 28 pt with 17 pt A/B badges, packaged Release build and native DualDeck visual check passed; uniform vertical three-finger BPM/Gain/master input implemented, native region/lifecycle and upward/downward/horizontal rejection check passed (0.147 s), Release app built (61.56 s) and DualDeck reopened; physical touch and native file drop still require confirmation; prior partial implementation (bef2a62). DJ workspace integrated (bef2a62); Release built, live same-file State isolation, pause, Sync, EQ/reset, scope/reset and color persistence visually verified `depends:DJ-3` `parallel:none`
- [ ] DJ-INT Reopened after comparison with the accepted mockup; verify corrected design and file loading before completion. Previous integrated Release build/signature and live DualDeck playback passed; same-file independent sliders, different-rate Sync, A/B pause, scope/EQ reset and persisted Mint/Violet colors verified; focused PCM/worker/document evidence retained, no source changes after verification `depends:DJ-1,DJ-2,DJ-3,DJ-4` `parallel:none`

- [x] TRANCE-1 Add the credited G-minor B template; preserve A and saved deck choices; verify live-loop PCM (5 tracks, 2 sliders, peak 0.603, Side/Mid -15.96 dB) `depends:none` `parallel:none`
- [x] TRANCE-INT Release app built; native project generation, B entry selection, playback and scope verified with zero errors `depends:TRANCE-1` `parallel:none`

- [ ] PLAY-1 Implemented central MASTER removal and full-circle transport hit targets; queued-play cancellation check passed (0.103 s); awaiting integration into the outstanding DJ UI commit `depends:none` `parallel:none`
- [ ] PLAY-INT Release built (29.59 s); previously missed edge coordinates now stop/start B, prepared playback and MASTER removal visually verified; zero errors; commit pending `depends:PLAY-1` `parallel:none`

- [x] SEEK-CORE Implement retained-PCM seek with wrapping and paused-state preservation; real transport PCM test passed `depends:none` `parallel:none`
- [ ] SEEK-1 Add Wave-only bidirectional three-finger seek; preserve playback state and deck isolation; verify PCM and gesture direction; three focused tests passed; Release build passed (65.90 s), TranceSet reopened; UI commit pending with existing gesture refactor `depends:SEEK-CORE` `parallel:none`
- [ ] SEEK-INT Native app built and seek path reviewed; physical three-finger input remains unverified `depends:SEEK-1` `parallel:none`

- [x] TOUCH-1 Shared gesture adapter committed (89c16d4); two/three contacts, four directions, contact transitions and region lifecycle tests passed `depends:none` `parallel:none`
- [ ] TOUCH-INT Integrated Release build passed (64.22 s), TranceSet reopened; physical trackpad input unverified and older UI integration remains uncommitted `depends:TOUCH-1` `parallel:none`

- [x] SCRATCH-1 Signed PCM output and paused/native behavior verified (81e0b77) `depends:none` `parallel:none`
- [x] SCRATCH-2 Timed Wave motion and lifecycle cleanup connected (fa8651b) `depends:SCRATCH-1` `parallel:none`
- [x] SCRATCH-INT Native paused output, 18 regressions and Release build (67.26 s) passed; reopened paused, zero errors; physical touch delivery not automated `depends:SCRATCH-1,SCRATCH-2` `parallel:none`

- [x] SCOPE-1 Shared 3D deck trajectories (c79b1d2) and header routing verified in Release/native UI `depends:none` `parallel:none`
- [x] SCOPE-INT Both selected deck colors, shared depth trails and master placement visually verified; focused scope test passed `depends:SCOPE-1` `parallel:none`

- [x] WAVE-1 Centered playhead and interpolated wrapped loop peaks; direction, seam and invalid-input test passed `depends:none` `parallel:none`
- [x] WAVE-INT Release build passed (62.30 s); native A/B playback showed changing waveforms with fixed center lines and zero errors `depends:WAVE-1,SCOPE-1` `parallel:none`

- [x] MIXUI-1 Native bipolar filter and delay timing added; LP/HP attenuation, center reset, retained invalid values and three-band EQ regression passed (2 tests, 0.909 s) `depends:none` `parallel:none`
- [x] MIXUI-2 Compact EQ above Wave and existing Filter-Space XY integrated; native EQ drag, independent deck values and pad reset verified `depends:MIXUI-1` `parallel:none`
- [x] MIXUI-TOP Native top safe area reclaims 52 points; sidebar collapse/expand preserves window controls `depends:MIXUI-1` `parallel:none`
- [ ] MIXUI-INT Final Release build passed (27.86 s); native EQ, XY/reset and header geometry verified; CUE implementation authorized; independent output integration pending `depends:MIXUI-1,MIXUI-2,MIXUI-TOP` `parallel:none`

- [x] DROPSELECT-1 Native NSItemProvider delivery selects the receiving deck and source before discovery; failed opens preserve selection (0.126 s); real compiler discovery passed (1.452 s), Release built (25.19 s); physical drag automation did not complete `depends:none` `parallel:none`

- [x] CUE-1 Independent cue and main/headphone routing (145b097); native PCM, volume, live device switching and private-device filtering verified (3 tests, 1.050 s) `depends:none` `parallel:none`
- [x] CUE-2 Rounded TAP/SYNC/CUE buttons and shared Audio settings verified in the Release app; main device switch/restore and unconfigured cue popover exercised `depends:CUE-1` `parallel:none`
- [x] CUE-INT Release build and native UI passed; main/cue PCM separation and output switching verified; physical headphone listening unavailable because headphones are disconnected `depends:CUE-1,CUE-2` `parallel:none`

- [x] INERTIA-1 Sample-clock decay, paused PCM/output release and return to playback verified by native tests `depends:none` `parallel:none`
- [x] INERTIA-2 Wave release/coast/recontact/cancel callbacks verified; existing two/three-finger and axis checks passed `depends:INERTIA-1` `parallel:none`
- [x] SPECTRUM-READABILITY Removed compounded transparency; selected deck tint and EQ remain readable during native playback `depends:none` `parallel:none`
- [x] INERTIA-INT Six focused tests passed (0.301 s), Release built and updated app launched with zero playback errors; physical trackpad inertia feel remains unverified `depends:INERTIA-1,INERTIA-2,SPECTRUM-READABILITY` `parallel:none`

- [x] HIGHLIGHT-1 Fresh language connection and bounded highlight retry; native NSTextStorage recovery and stale-document regressions passed `depends:none` `parallel:none`
- [x] HIGHLIGHT-INT Release build passed; Trance.swift in Deck B visibly colors keywords, comments, types and strings `depends:HIGHLIGHT-1` `parallel:none`

- [x] PALETTE-1 Restore 12-swatch deck palette and compressor tint; native Cyan selection and Magenta restoration verified `depends:none` `parallel:none`
- [x] PALETTE-INT Release build and native palette/settings verification passed; paused compressor tint verified; live waveform check interrupted by app closure `depends:PALETTE-1` `parallel:none`

- [x] DECK-COLOR-1 Independent nonblocking readers; two real language processes, bounded shutdown, cancellation, final response and native editor regressions passed (10 tests, 2.35 s) `depends:none` `parallel:none`
- [x] DECK-COLOR-INT Release build passed (63.78 s); native TranceSet A/B/A switching retained keyword, comment, type and string colors with zero errors `depends:DECK-COLOR-1` `parallel:none`

- [x] WAVE-DIR-1 Make Wave follow horizontal finger motion; preserve vertical and knob direction, two/three fingers and inertia `depends:none` `parallel:none`
- [x] WAVE-DIR-INT Four gesture/native PCM tests and release build passed `depends:WAVE-DIR-1` `parallel:none`

- [x] EDGE-1 Add explicit edge mode with contact-locked routing, cursor capture and Esc/focus-loss teardown; preserve regular gestures outside mode `depends:none` `parallel:none`
- [x] EDGE-INT Six tests and release build passed; user verified cursor capture/Esc restoration; TranceSet opened for physical edge trial `depends:EDGE-1` `parallel:none`

- [x] EDITOR-CLIP-1 Confine native editor drawing to its viewport while retaining document scrolling and header/tab/log layout `depends:none` `parallel:none`
- [x] EDITOR-CLIP-INT Two native tests and release build passed; app scroll down/up preserves header, tabs, EDGE and logs `depends:EDITOR-CLIP-1` `parallel:none`

- [x] PLAY-MODE-1 Rename the control and move it to the log bar; keep capture lifecycle owned by the workspace view `depends:none` `parallel:none`
- [x] PLAY-MODE-INT Release build passed; native screenshots verify log bar placement in collapsed/expanded states and removal of the center button `depends:PLAY-MODE-1` `parallel:none`

- [x] PLAY-KEY-1 Route Space to combined transport and standalone left/right Command/Option taps to deck transport/CUE in Play Mode; preserve typing and shortcuts `depends:none` `parallel:none`
- [x] PLAY-KEY-INT Three focused tests and release build passed; native Space starts and pauses both decks; unrelated color/scroll suite failures remain outside scope `depends:PLAY-KEY-1` `parallel:none`

- [x] FADE-SENS-1 Increase bottom-edge crossfade sensitivity threefold with relative motion and no touch-down jump `depends:none` `parallel:none`
- [x] FADE-SENS-INT Three native edge tests and release build passed; physical sensitivity remains for user trial `depends:FADE-SENS-1` `parallel:none`

- [x] FREE-FADE-1 Route two-finger motion anywhere to crossfade, exclusively until all fingers lift; preserve single-contact edge controls `depends:none` `parallel:none`
- [x] FREE-FADE-INT Four edge tests and release build passed; updated app opened with new help; physical two-finger feel awaits user trial `depends:FREE-FADE-1` `parallel:none`

- [x] WIDE-EDGE-1 Widen side bands to 18 percent while preserving bottom 12 percent crossfade priority and two-finger routing `depends:none` `parallel:none`
- [x] WIDE-EDGE-INT Four edge tests and release build passed; updated app opened for physical trial `depends:WIDE-EDGE-1` `parallel:none`

- [x] EDGE-SIM-1 Remove whole-pad two-finger capture and restore independent concurrent edges, retaining widths and sensitivity `depends:none` `parallel:none`
- [x] EDGE-SIM-INT Three edge tests and release build passed; updated app launched for physical simultaneous-control trial `depends:EDGE-SIM-1` `parallel:none`

- [x] BOTTOM-20-1 Expand bottom crossfade band to 20 percent, preserving side widths and concurrent routing `depends:none` `parallel:none`
- [x] BOTTOM-20-INT Three edge tests and release build passed; updated app launched `depends:BOTTOM-20-1` `parallel:none`

- [x] REST-EDGE-1 Preserve resting touch begins so a bottom contact can move while another edge remains active `depends:none` `parallel:none`
- [x] REST-EDGE-INT Native event regression failed before fix and passed after; four edge tests and release build passed; LiveSet0911 reopened for physical trial `depends:REST-EDGE-1` `parallel:none`

- [x] RELEASE-030-1 Review and commit current production changes and 0.3.0 preview metadata; retain local trial projects outside release `depends:none` `parallel:none`
- [x] RELEASE-030-INT 26 integration tests passed; packaged 0.3.0 built, signature verified and native version display confirmed; public SwiftMusic 0.5.0 dependency checked `depends:RELEASE-030-1` `parallel:none`

- [x] PERF-1 Mapped both package structures and traced compilation, build, PCM publication, rendering, playback and display paths; reviewed copy/cache ownership and cancellation; source unchanged `depends:none` `parallel:none`
- [x] PERF-2 Release focused checks passed 16/16; measured compile/render/PCM codec/validation/spectrum costs and 513 ms cancellation latency with temporary probes `depends:PERF-1` `parallel:none`
- [x] PERF-INT Ranked proposals by interaction latency, build stages, monitor copies, PCM transport and DSP reuse; measurement limits and preserved invariants stated; no source changes or publishing `depends:PERF-1,PERF-2` `parallel:none`

- [x] OPT-1 73e1a18: Added block cancellation, immutable detune ratios and bounded FFT scratch/impulse reuse; 36 tests passed including native synthesis, concurrent rerenders and convolution reference/reuse; reviewed ownership and PCM paths `depends:none` `parallel:none`
- [x] OPT-2 f762c9f: Ring history, immutable snapshot reuse and shared master capture; 19 tests passed including wrap/isolation, telemetry and hardware callback; corrected stale 2048-frame test expectation to the existing 8192-frame viewport `depends:OPT-1` `parallel:none`
- [x] OPT-3 af66ba8/da4af1c: Stable worker source, runtime identity and input-keyed AST/executable reuse; 14 native worker/project tests passed; unchanged SDK evaluation 0.56 s, project warm restart 4.15 s; fresh State and revision verified; exact-UTF8 source write and unchanged timestamp regression passed `depends:OPT-2` `parallel:none`
- [x] OPT-4 8f95b81/4aeef8d: Atomic raw-PCM container with immutable mapped ownership and cached finite validation; legacy codec, malformed ranges, mapping after unlink and native playback verified; 17 protocol/PCM tests plus real synthesis evaluation passed; compatibility conversion regression fixed with scoped bulk borrow and five release checks `depends:OPT-3` `parallel:none`
- [x] OPT-5 SwiftMusic fc9e6c3/5b10080 reuses bounded syntax under exclusive compilation ownership; 208 debug/release tests and nine exact-UTF8/typed-cache checks passed; edited dependency and compiled cache type confirmed in app integration (57 checks plus corrected stale meter expectation/five native rechecks); public dependency remains released 0.5.0 until the next SwiftMusic release `depends:OPT-4` `parallel:none`
- [x] OPT-INT SwiftMusic 208 debug/release tests plus nine UTF8/cache checks; app integration and 41 release checks, five PCM ASan/native checks and two final packaged SDK/source checks passed. Signed app built with public 0.5.0 dependency and no edit override. Probe: cancellation 513.45 to 0.063 ms, unison render 9.38 to 8.12 ms, 16-second mapped receive 0.52 ms versus prior decode 4.03 ms; compatible decode 3.34 ms, mapped/Array native block both 0.745 ms. Unchanged packaged evaluation 0.38 s; raw-file write timing remains filesystem-dependent. Only task commits admitted to configured main upstreams `depends:OPT-1,OPT-2,OPT-3,OPT-4,OPT-5` `parallel:none`

- [x] MEASURE-1 Release probes on M4 Max/macOS 27 measured 4s render 1/8/16 tracks at 33.01/257.65/513.36 ms median; 4s interleave 0.135 ms; fresh snapshot p95 0.00792 ms; sustained-contention capture p95 0.02158 ms versus 0.00629 ms without contention; source unchanged, temporary probe /tmp/zero-copy-measure.swift `depends:none` `parallel:none`
- [x] MEASURE-2 Shared-output A/B hardware ran 600 idle plus 600 active updates (actual median intervals 19.54/17.98 ms), zero diagnostic dropouts; active update p95 0.102 ms. Reused-buffer native offline graph: active 512-frame p95 0.183 ms. Allocations attachment failed; direct allocator statistics showed 1000 cached snapshots add zero live bytes/blocks, fresh snapshots add 999 blocks/81,838,080 bytes (80 KiB each); total allocation traffic not measured `depends:MEASURE-1` `parallel:none`
- [x] MEASURE-INT Correlated /tmp/zero-copy-{micro,contention,hardware,native,memory}.txt with source ownership; render-end interleave is about 0.03% of 16-track rendering. Meter allocation/critical-section reduction is a secondary candidate, with no demonstrated hardware playback bottleneck. Contention timings include execution and scheduling rather than isolated lock wait; hardware callback load is sampled source-only telemetry, offline graph timings exclude hardware/UI rendering. Production source and public dependencies unchanged; no optimization implemented `depends:MEASURE-1,MEASURE-2` `parallel:none`

- [x] SYNTH-1 Borrow active voices for frame advancement; sampled per-frame aggregate copies removed without changing DSP arithmetic. 24 release tests passed including exact 1/8/16-track PCM, voice stealing/choke and seamless boundaries. Clean median 4s render: 8 tracks 247.83 to 69.77 ms; 16 tracks 489.66 to 136.83 ms; 7 runs each. Commit: 7c3fc98 `depends:none` `parallel:none`
- [x] SYNTH-INT Eight release integration tests passed for concurrent live rerenders, cancellation, source controls and actual hardware playback; 24 focused checks plus exact PCM hashes cover the scheduler. Reviewed unchanged ordering, local value ownership and error/cancellation paths; no unsafe/shared-state changes. Only task commits admitted to configured main upstream `depends:SYNTH-1` `parallel:none`

- [x] UPDATE-051-1 SwiftMusic bffb25e released as 0.5.1 Preview; 208 Release tests passed, URL-independent library graph checked, tag commit equals origin/main; GitHub release published `depends:none` `parallel:none`
- [x] UPDATE-051-2 Host, evaluator/completion manifests, new-project template, tracked example and docs pin public 0.5.1 (bffb25e); 12 Release tests passed including generated project/native PCM, both slider paths, real SourceKit completions, multi-file dependencies and synthesis PCM regression. Public checkout state verified; commit: b39e86f `depends:UPDATE-051-1` `parallel:none`
- [x] UPDATE-051-INT Packaged app built and signature verified; public 0.5.1 manifest, runtime artifact hashes and compiled PatternParseCache verified. Two bundled-SDK tests passed (entry discovery, retained switch worker); 12 project/completion/synthesis tests passed including generated-template native PCM and Slider changes. SwiftMusic 208 Release tests passed. Only task commits admitted to configured main upstream `depends:UPDATE-051-1,UPDATE-051-2` `parallel:none`

- [x] RELEASE-040-1 Updated README/changelog and packaged version to 0.4.0 (build 4); app build, signature and exact public SwiftMusic 0.5.1 pin verified. Production code unchanged; UPDATE-051 and SYNTH behavioral evidence remains valid. Commit: a7a614d and packaged-version commit `depends:none` `parallel:none`
- [x] RELEASE-040-INT Verified app 0.4.0/build 4, signature and bundled/public SwiftMusic 0.5.1; candidate changes are release metadata/docs only, existing behavioral evidence retained. Correct-case tracked Scripts/build-app.sh included; candidate verification committed before publishing the matching main tag `depends:RELEASE-040-1` `parallel:none`

- [x] LATENCY-1 1799a80: Immediate/beat/bar source adoption, app preference and phase-preserving 30ms crossfade; new native timing/PCM tests passed. 32-test run exposed two old instantaneous-adoption expectations; updated contract checks plus 9 focused regressions passed. Native two-deck/audio-clock checks passed; reviewed Mutex ownership and post-fade controls `depends:none` `parallel:none`
- [x] LATENCY-2 9aba791: Cached last SwiftPM build-root binary path after successful discovery; real multi-file project regression passed (103.68s). Two successful compilations used one directory query; failure retained old worker. Warm edit 2.866s; separate query probe median 0.290s (3 runs). Reviewed actor ownership, root identity, fixed configuration and error propagation `depends:LATENCY-1` `parallel:none`
- [x] LATENCY-INT Final 32 native timing/playback/clock/scratch checks passed; multi-file project check and two packaged SDK/retained-switch checks passed (35 total). App built and signature verified. Native Audio settings showed all three timings; Next Beat survived app restart, then restored Immediate. Reviewed parent flow, worker publication and native Mutex ownership; only task commits admitted to configured main upstream `depends:LATENCY-1,LATENCY-2` `parallel:none`

- [x] VINYL-1 37c84a1 (following c992f9f): cumulative position tracking and native TimePitch bypass; endpoint/return, native varispeed, normal keylocked tempo, release/cancel/failure behavior and independent output retirement verified. Immutable PCM/table borrows and Mutex/MainActor ownership reviewed `depends:none` `parallel:none`
- [x] VINYL-INT 36 focused integration tests passed in 2.865s, including native two-deck output, sync, source adoption and master ramps. Scratch output 219/438/877Hz at 0.5/1/-2 speed independent of deck tempo; transition jump <0.0063; steady-tone alias rejection 80.6...81.2dB; two-deck 32x/512-frame median 2.826ms versus 11.610ms budget on M4 Max. ASan borrow evidence from c992f9f remains applicable. Release app built (72.61s), signature verified, updated app launched. Physical finger feel is not automated. Upstream comparison admits only this task's commits `depends:VINYL-1` `parallel:none`

- [x] COAST-R1 de85b72: Recent hand velocity survives settled position/zero-motion lift samples, expires after 120ms, and launches inertia over 5ms; fast finite input retains displacement with bounded audible speed. Reproduced old near-zero release and native speed-limit error; 25 focused tests pass, including stale silence, 400x input admission/bounds, exact endpoint, output pitch/transitions and native two-deck isolation. Reviewed Mutex-owned scalars, bounded age/velocity and unchanged PCM borrow lifetime `depends:none` `parallel:none`
- [x] COAST-G1 726c279: Valid two/three-contact transitions rebase the centroid without cancelling scratch; native cancellation remains explicit and numeric controls keep their reset policy. Exact production-adapter probe changed from release 0/cancel 1 to release 1/cancel 0 for both transitions; all 26 gesture, inertia, numeric-control and edge tests passed. Reviewed MainActor lifecycle and unchanged SwiftUI attachment path `depends:COAST-R1` `parallel:none`
- [x] COAST-RINT 56 integration tests in 12 suites passed in 4.337s, covering native audio, gesture transitions, inertia, source replacement and deck isolation. Release app built in 72.44s, strict deep signature verification passed, and the updated app opened LiveSet051 with zero errors. Physical finger feel is not automated. Upstream comparison admits only task commits for normal push `depends:COAST-R1,COAST-G1` `parallel:none`

- [x] RELEASE-050-1 cdeb61d: Updated 0.5.0 Preview README/changelog and build 5 metadata; release app built and signature, public SwiftMusic 0.5.1 and runtime hashes verified. Production source unchanged; 56-test integration evidence remains valid `depends:none` `parallel:none`
- [x] RELEASE-050-INT Release candidate verified: 0.5.0/build 5, strict deep signature and every bundled runtime digest passed; public SwiftMusic 0.5.1 checkout, no local dependency overrides, and unchanged production sources confirmed. Prior 56-test native integration and source-update verification remain applicable. Candidate ready for matching main tag and source-preview publication `depends:RELEASE-050-1` `parallel:none`
