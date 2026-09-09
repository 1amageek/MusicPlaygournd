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
