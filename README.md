# MusicPlaygournd

**A native macOS live music editor powered by [SwiftMusic](https://github.com/1amageek/SwiftMusic).** Write Swift, press Play, and change your music while the last valid loop continues playing.

```text
Swift code → prepare → musical boundary → audio
               error → Logs; previous audio continues
State pad → preprepared variant → audio
```

## Build and run

This **0.1.0 Preview is a source release**. Requires macOS 15+, Xcode command-line tools and a Swift 6.4 toolchain. Verified on macOS 27 Apple silicon with Swift 6.4.2-dev snapshot `2026-09-04-a`; older macOS versions are not runtime-verified.

```sh
git clone https://github.com/1amageek/MusicPlaygournd.git
cd MusicPlaygournd
./Scripts/build-app.sh
open .build/MusicPlaygournd.app
```

SwiftPM fetches the exact public SwiftMusic 0.4.0 dependency. No sibling checkout is needed. The script produces a locally ad-hoc-signed app and bundles matching runtime modules. It records the installed compiler, SDK and plugin paths: build the app on the machine where you will use it and keep that toolchain installed. No notarized binary is distributed in this preview.

**Sessions execute trusted local Swift with your account's permissions. This is not a code sandbox.**

## Swift package projects

Use **File → New Project** or **Open Project** (Shift–Command–O) to open a folder containing `Package.swift`. New Project creates the named directory with a matching package and target, a playable Session.swift template, resources and recordings folders. It opens the generated session automatically. Existing directories are never overwritten. The sidebar keeps the package folder as its root and expands folders in place.

```text
MyLiveSet/
├── Package.swift
├── Sources/
│   └── MyLiveSet/
│       ├── Session.swift
│       └── Resources/
└── Recordings/
```

A playable Swift library target contains one `Session.swift` defining `Session: Music`. Other Swift files in that target are compiled as separate files; declare their imports normally. When a package has multiple playable targets, select one in the sidebar. Editing another file keeps the target's Session as the playback entry. Unsaved source buffers participate in evaluation without rewriting the files on disk.

SwiftPM resolves dependencies and resources from the package manifest. Access declared resources with `Bundle.module`; relative runtime file paths resolve from the project root. The host prepares its worker in a private copy, preserving the original manifest. Project evaluation uses SwiftPM, so an initial dependency build is slower than standalone single-file evaluation. Failed compilation preserves the last valid audio.

Completion uses SourceKit-LSP against the project itself, including open buffers. Saved-file tabs and selection are remembered per project; unsaved contents remain in the open editor and use the normal save/discard flow. Non-code assets open in their associated macOS app. Inline results are currently anchored to the Session entry; helper files can be edited without assigning entry-file result positions to them.

## Start playing

Open [Examples/LiveSwitch.swift](Examples/LiveSwitch.swift) with Command–O. The entry type is `Session: Music`.

```swift
import SwiftMusic

enum Beat { case steady, fill }

struct Session: Music {
    @State private var beat: Beat = .steady

    var body: some Sound {
        Track("Drums") {
            switch beat {
            case .steady:
                Sample("kick").rhythm("x ~ x ~").gain(0.7)
            case .fill:
                Sample("kick").rhythm("x x [x x] x").gain(0.7)
            }
        }
    }
}
```

Once preparation succeeds, pads beneath each supported `switch` select its cases. The sample also switches whole Tracks. All variants are prepared ahead of time; clicking does not compile or render a new loop. Selection uses the existing beat clock and a short crossfade.

## Editor and performance

- File sidebar and document tabs; Command–O opens a session and Command–S saves it.
- Code-only line numbers, automatic indentation, four-column Tab stops and Control–I formatting.
- Command–Z / Shift–Command–Z undo and redo source edits using per-document histories.
- Semantic Swift completion while typing; Control–Space requests it manually, Return/Tab accepts it.
- Inline rhythm/pitch results after complete sound expressions, with alternate side and bottom layouts.
- Individual rhythm/note tokens light at their event times. Track mute sits beside the corresponding result.
- Global transport, BPM, meter, master volume and filter/space XY pad.
- Stereo waveform and spectrum from actual engine output; collapsible Logs below the editor.
- Optional control/MIDI Learn and recording interfaces. Device/plugin availability depends on the host.

Code changes prepare a replacement and adopt it at a musical boundary. Invalid edits leave the previous audio playing and report diagnostics. Live master controls operate separately from code preparation.

## Patterns and rendering

Brackets subdivide time: `x [x x] ~ x`. Gain can be patterned: `.gain("1 [0.3 0.6] 0.8")`. Notes support rests, subdivisions and chords. SwiftMusic compiles event timing and modifier order; this app renders bounded PCM loops and hosts native audio output.

The renderer includes built-in percussion, oscillator voices, local sample files/banks, envelopes, filters, effects, buses and sends. Unsupported combinations fail explicitly. It does not promise hard real-time scheduling or compatibility with every Audio Unit.

Switch controls initially support compiler-resolved `@State` properties on `Session`, local enums without associated values, and exhaustive simple enum cases. Multiple sites reading the same property share a selection. The bank is limited to 16 combinations and 128 MiB of PCM. Unsupported switch forms remain ordinary Swift but do not receive interactive pads. State switches and `PerformanceEntry` are not combined in this preview.

## Verification

Build the app first so its RuntimeSDK exists, then run the relevant Swift Testing suites:

```sh
swift test -c release --filter SwitchBankTests \
  -Xswiftc -Xfrontend -Xswiftc -disable-round-trip-debug-types
```

The build script disables a development-compiler debug-type round-trip assertion; optimization remains enabled. See [DESIGN.md](DESIGN.md) for renderer, evaluation, ownership and failure contracts.

## License

[MIT](LICENSE) · Copyright 2026 1amageek.
