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
