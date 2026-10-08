# Audio Prototype

## Purpose and Scope
Component. Parent: [app module](../DESIGN.md). Children: none. Bundled Music, temporary UI, off-UI PCM preparation and foreground looping playback.

## Responsibilities and Boundaries
DemoMusic owns the bundled musical declaration and its display source. PlaybackModel owns visible state and one cancellable preparation task. AudioPlaying is the internal injected playback contract; NativeAudioPlayer owns serialized asynchronous activation/deactivation and AVAudioSession, AVAudioEngine, AVAudioPlayerNode and scheduled PCM lifetime. OutputMeter owns bounded callback evidence.

## Related Designs
[Rendering](../../../Sources/MusicPlaygourndCore/Rendering/DESIGN.md) supplies bounded finite interleaved stereo PCM through LoopRenderer. [SwiftMusic](../../../Package.swift) supplies Music/SoundCompiler and event semantics. Body evaluation follows upstream MainActor isolation; native source compilation is performed by Xcode before installation.

## Architecture
```text
MainActor: DemoMusic -> SoundCompiler -> immutable CompiledSound
    -> detached cancellable task: LoopRenderer -> validated PreparedLoop
    -> MainActor: native planar buffer -> AVAudioPlayerNode
    -> system audio render threads: output -> bounded OutputMeter atomics
MainActor UI <- snapshot of observed callback count and peak
```

## Contracts and Invariants
Rendering preserves existing 16-second, 32-beat, 32-source, 1024-event and 256-node bounds. The score needs no downloaded assets. PCM is copied once into the system-owned planar buffer because AVAudioPlayerNode requires that layout; scoped channel pointers never escape. UI and audio graph control are MainActor isolated. Meter state uses atomic counters/peak updates, with no callback allocation, suspension, logging or UI access; the tap closure is explicitly @Sendable and uses the SDK read-only buffer borrow. The system owns realtime thread scheduling; detached preparation does not promise a fixed CompileThread.

## Runtime Flows
Play evaluates the score, renders off-UI, validates PCM and starts the native player. Stop enters a stopping state, invalidates any in-flight activation, cancels preparation, stops graph output immediately, waits for owned activation to finish and asynchronously deactivates the session. Play remains disabled until cleanup completes. A cancelled or stale result cannot start playback. Render/session/engine failures become visible errors and do not report playing. Restart reschedules the same valid cached PCM from its beginning. Tests exercise invalid patterns, cancellation, stop/restart and real output.

## State, Ownership, and Lifecycle
One model owns one audio player and one preparation task. Stop invalidates pending results before releasing playback. The player retains the scheduled buffer while active and clears it after stopping. The model forbids new Play while preparing, playing or stopping. Activation completion checks a generation token before scheduling audio; concurrent Stop owns cleanup for the invalidated token. Duplicate Stop requests share the stopping state and do not start another deactivation. Interruption and route disconnection stop playback; route changes are observed on MainActor. No background audio mode is declared. Meter snapshots never borrow audio buffers.

## Failure, Concurrency, and Constraints
Preparation checks cancellation through the existing renderer. UIKit audio session errors propagate explicitly. A busy model ignores duplicate Play actions; controls identify preparing, playing, idle and failed states. Audio node callbacks retain only the independent atomic meter. No unsafe Sendable escape or process-based Mac evaluator is used.

## Verification and Change Impact
App-hosted tests assert expected score events/pitches, finite nonzero rendered PCM, invalid-pattern failure and preserved planar samples. Real AVAudioEngine playback must produce nonzero mixer callback samples, stop and restart successfully; route and volume are recorded on the physical iPad. Hardware volume zero is reported, not treated as acoustic evidence. Model cancellation must reject late preparation. Tests own only this native prototype; Mac renderer tests remain the shared DSP regression authority.

### Ownership and behavioral evidence

| State / invariant | Owner and isolation | Lifetime / release | Test owner |
|---|---|---|---|
| UI phase, generation and pending render | PlaybackModel / MainActor | model lifetime; Stop invalidates before awaiting cleanup | [NativePlaybackTests](../../Tests/NativePlaybackTests.swift), [PlaybackUITests](../../UITests/PlaybackUITests.swift) |
| CompiledSound and PreparedLoop | immutable Sendable values; detached render has local DSP state | prepared PCM cached by model, released with model | NativePlaybackTests score, finite PCM and codec tests |
| Activation, graph and scheduled native buffer | NativeAudioPlayer / MainActor, SDK-owned async activation | Stop invalidates activation, awaits it, stops graph and deactivates session | NativePlaybackTests activation-cancellation and hardware play/stop/restart |
| Callback count and peak | OutputMeter / Atomic, read-only Span borrow | meter retained by tap; buffer borrow ends inside callback | NativePlaybackTests hardware output, UI displayed evidence |
| Shared mute-cache snapshots | existing MuteRenderCache / Mutex on Mac and iPad | immutable render-cache snapshots owned by renderer | existing renderer tests; synchronization unchanged |

The iPad prototype is a native target only. It introduces no WASM/Embedded backend, conditional Sendable contract or conditional raw mutable storage.

## Shared UI adapter

[MusicPlaygroundUI](../../../Sources/MusicPlaygroundUI/DESIGN.md) owns the same sidebar, deck rack, source shell and wave presentation as Mac. This adapter exposes the actual bundled source and its prepared-loop peaks through existing PlaybackModel. Sidebar selection is read-only bundled content; toggling columns does not affect playback. Deck B, arbitrary source editing/compilation and live FX are explicitly unavailable in this milestone. The shared Effect component provides the unavailability presentation; it does not imply DSP support. Physical UI tests own sidebar selection/toggle and retained audio lifecycle.
