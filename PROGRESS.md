# Progress

- [ ] TEMPLATE-1 Correct creation to the actual SwiftPM initial template; current custom Session/Resources/Recordings generator does not meet the request; retain existing-path protection; current manifest and generator formatting corrected with four-space indentation and multiline declarations, and SwiftPM metadata is unchanged `depends:none` `parallel:none`
- [x] NAV-1 Native NavigationSplitView/List/DisclosureGroup, unified toolbar, detail-only logs/status and redundant folder strip removal verified by app build and native selection/expansion/visibility checks `depends:none` `parallel:none`
- [x] NAV-2 Bottom status bar removed; native Liquid Glass overlay and all three layout selections verified in the signed app; overlay is owned outside the source scroll view `depends:NAV-1` `parallel:none`
- [ ] TEMPLATE-INT Verify standard SwiftPM package creation/opening without requiring a custom Session.swift entry, existing-path preservation, and the native navigator flow `depends:TEMPLATE-1,NAV-1,NAV-2` `parallel:none`
