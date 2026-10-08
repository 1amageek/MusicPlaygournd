# Documents

## Purpose and Scope
Native project/document component. Parent: [app module](../DESIGN.md). Child: [Storage](Storage/DESIGN.md). Owns S01–S04/E04/E06 in the [parity contract](../../../docs/UI-PARITY.md); accepted music belongs to the audio owner.

## Responsibilities and Boundaries
DocumentWorkspace owns shared file identity, A/B tab membership, selected document, dirty source, close/replacement decisions and visible failures on MainActor. SourceDocument owns one source/baseline pair. Platform views adapt these values to shared Sidebar/Editor views. Storage owns actual file operations and static package metadata. Selecting or editing never evaluates music.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [App](../DESIGN.md) | parent | scene composition | owns view/model lifetime | audio remains independent |
| [Storage](Storage/DESIGN.md) | child | ProjectFileAccess | async project/file operations | adoption checks current identity/revision |
| [Shared Editor](../../../Sources/MusicPlaygroundUI/Editor/DESIGN.md) | depends on | SourceEditor retained document IDs | native selection/undo/IME | close releases only unreferenced buffers |
| [Shared Sidebar](../../../Sources/MusicPlaygroundUI/Sidebar/DESIGN.md) | depends on | rows/footer/error slots | real source/dependency tree | stale listing is explicit |
| [Prototype](../Prototype/DESIGN.md) | coordinates with | accepted audio identity | editing does not replace audio | native compilation is separate |

## Architecture
```text
Sidebar/tabs/editor -> DocumentWorkspace (MainActor) -> ProjectFileAccess (actor)
                           |                               |
                     SourceDocument                  real files / bookmarks
                           |
                     committed source -> SourceEditor -> parsing diagnostics
Audio owner -> accepted identity/playing markers; source selection does not change audio
```

## Contracts and Invariants
One canonical URL owns one buffer shared by both deck tab lists. Closing one membership preserves the other. Last dirty membership offers Save/Discard/Cancel; failed or raced save retains source and membership. Save updates the baseline to the exact written snapshot. Numbered files are born in the selected real target directory. Project replacement resolves dirty buffers before adopting a new snapshot. Settings/bookmarked project are persisted only after successful adoption.

## Runtime Flows
Bootstrap restores the bookmarked project or creates the first real project from the bundled source. Open/new obtains a candidate snapshot, then adopts it without changing audio. Selection reuses or reads one canonical buffer. Editing changes only the source. Save/close/replacement serialize admission on MainActor while storage serializes I/O. Alert actions capture document/deck or candidate URL synchronously before SwiftUI dismisses the alert; asynchronous work uses that owned intent rather than the cleared presentation state. Filter includes matching descendants/ancestors; refresh preserves previous listing on failure.

## State, Ownership, and Lifecycle
At most 32 distinct documents and two membership lists are retained. Project entries are bounded to 4096 and files to 64 KiB, matching Mac admission. UIKit storage lifetime follows the retained IDs. Storage accesses security-scoped folders only for each operation and balances acquisition/release. Workspace owns no audio engine or compiler task.

## Failure, Concurrency, and Constraints
Typed storage failures remain visible; successful UI construction is not file-operation evidence. Dynamic package target metadata requests compiler capability explicitly. An imported dependency tree is read-only and contains actual bundled package source. Cancellation cannot discard dirty text or imply a write was rolled back.

## Verification and Change Impact
Native DocumentTests must exercise real temporary files: no-overwrite numbering, filter ancestry, dirty A/B switching, shared identity, failed save/conflict, Save/Discard/Cancel, read-only dependencies, stale refresh, static targets and project bookmark restoration. Integrated physical UI tests create/edit/save/switch/close files while real audio remains accepted. Storage changes require lower-level behavioral tests before document composition; shared tab changes require Mac regression and final visual integration.
