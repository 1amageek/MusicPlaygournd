# Native iPad Application

## Purpose and Scope
Xcode application project. Parent: [system](../DESIGN.md). Child: [app module](MusicPlayground/DESIGN.md). iPadOS 27+, device family iPad only; Swift 6.4. First milestone: an audible bundled SwiftMusic composition, temporary UI and independent device execution.

## Responsibilities and Boundaries
Owns native target membership, signing and integration evidence. Uses public SwiftMusic 0.5.1, identical to the Mac pin. No runtime Swift source compiler is declared or exposed. The existing SwiftPM Mac products remain independent.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [System](../DESIGN.md) | parent | platform boundaries | standalone native prototype | no Mac runtime dependency |
| [App](MusicPlayground/DESIGN.md) | child | UI and audio lifecycle | native application | foreground playback only |
| [UI](../Sources/MusicPlaygroundUI/DESIGN.md) | depends on | public SwiftUI views | shared presentation | local product has no Mac Core dependency |
| [Rendering](../Sources/MusicPlaygourndCore/Rendering/DESIGN.md) | depends on | LoopRenderer and PreparedLoop | shared source, no DSP copy | Xcode source references compile in the app module; Mac-only worker transport and retained control session are excluded |

## Architecture
```text
SwiftMusic 0.5.1 -> shared Rendering source -> native iPad app -> AVAudioEngine -> hardware
```

## Contracts and Invariants
The native app target is named `MusicPlaygroundApp` to keep UI-test app resolution distinct from the root package library target `MusicPlayground`. Its product, executable and Swift module remain `MusicPlayground`; the scheme remains `MusicPlayground`. Signed bundle prefix team.stamp uses the existing Stamp Inc. developer team, independently verified from existing profile/certificate metadata. Xcode target references shared files instead of copying implementations. PreparedLoop standalone serialization remains portable; Mac worker-only range decoding explicitly fails on iPad. No process spawn, interpreter placeholder or synthetic success response is included.

## Verification and Change Impact
Xcode tests execute actual score evaluation, native DSP, planar PCM conversion and AVAudioEngine output. Physical-device evidence identifies the device, route, running engine and nonzero mixer callbacks; those callbacks establish output before hardware volume, not acoustic recording. Focused Mac renderer tests own regression. Opening this project in Xcode supports normal development; existing wildcard development provisioning supports the connected iPad without new credentials.

The Xcode project retains iPadOS 27 as its runtime floor to use asynchronous audio-session activation and deactivation. SwiftMusic 0.5.1 omits an iOS floor in its manifest, so the provided build command applies `IPHONEOS_DEPLOYMENT_TARGET=27.0` to the complete package graph. This preserves the public pin without modifying dependency checkouts. Plain Xcode Run without that package-wide override is not a supported build path for this milestone.
