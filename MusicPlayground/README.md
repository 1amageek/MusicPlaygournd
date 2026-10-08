# Native iPad audio prototype

This Xcode project plays a bundled four-track SwiftMusic composition on iPad without a Mac connection. The UI uses the shared MusicPlaygroundUI module: a native sidebar, A/master/B deck rack, native editable Swift source with grammar highlighting, undo and syntax formatting, real prepared-PCM waveform, Play/Stop controls and output evidence. Deck B and live FX explicitly remain unavailable. Arbitrary Swift compilation on-device is a separate task. Editing does not replace the accepted bundled music.

Requirements: Xcode 27 / Swift 6.4, iPadOS 27+, and a development signing identity for the project's existing Stamp Inc. team. The app's bundle ID is `team.stamp.MusicPlayground`. No background audio entitlement or microphone access is needed.

From the repository root:

```sh
Scripts/build-ipad.sh
IPAD_DESTINATION='id=<connected-iPad-UDID>' Scripts/build-ipad.sh test \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120
```

The script applies `IPHONEOS_DEPLOYMENT_TARGET=27.0` to the complete dependency graph because the unchanged public SwiftMusic 0.5.1 manifest declares only a macOS floor. Plain Xcode Run without this package-wide override fails availability checks in the dependency; the command above is the supported build path for this prototype. The app and tests use the pinned public package, not a modified checkout.

Builds go to `.build/iPad`. Install `.build/iPad/Build/Products/Debug-iphoneos/MusicPlayground.app` using Xcode Devices or `xcrun devicectl device install app --device <UDID> <app-path>`. Open MusicPlayground on the iPad and tap Play. Stop, backgrounding, interruption or disconnected output stops playback; return to the foreground and press Play to restart.

Shared rendering files are referenced directly by the project. DSP implementation is not copied into the iPad app. The [design](DESIGN.md) defines ownership and verification boundaries. Native tests cover score events, real PCM, planar conversion, codec failures, model cancellation and AVAudioEngine output/stop/restart. UI tests press the real Play/Stop buttons, restart playback and verify backgrounding stops audio. Output tap evidence measures the hardware graph before speaker volume; it is not an acoustic recording.
