# Document Storage

## Purpose and Scope
Child of [Documents](../DESIGN.md). No children. Owns filesystem admission, exact UTF-8 bytes, static SwiftPM targets and bounded snapshots.

## Responsibilities and Boundaries
ProjectFileAccess is the injected Sendable async protocol. ProjectFiles actor serializes filesystem operations. It returns immutable canonical snapshots; it does not own UI selection, dirty decisions, compilation or audio. SwiftParser/SwiftSyntax 604.0.0 parse actual manifest literals; computed metadata is rejected as requiring the separate compiler capability.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Documents](../DESIGN.md) | parent/used by | snapshots and typed errors | UI adoption owns dirty state | save snapshot may differ from current edits |
| [Native project](../../../DESIGN.md) | depends on | pinned package/resources | bundles actual SwiftMusic source | source resources must come from resolved 0.5.1 |

## Architecture
```text
ProjectFileAccess -> ProjectFiles actor -> scoped root access -> real filesystem
                          |                         |
                  checked SwiftParser        immutable snapshots / exact bytes
```

## Contracts and Invariants
Project roots must be real directories; source/target URLs stay within their root after canonicalization. Enumeration skips hidden/build and symbolic-link entries, is bounded to 4096 entries and surfaces errors. Reads require regular UTF-8 text of at most 64 KiB. Creation uses no-overwrite writes; numbered collisions preserve original bytes. Saves compare the current disk content to the caller's baseline before atomic replacement and reject external modification. Dependency roots admit reads and reject writes.

## Runtime Flows
Each operation acquires root security scope when required and defers release. New project content is assembled in an owned staging directory, then moved to a free numbered destination. Static literal package targets map to actual source directories; unsupported/computed metadata fails visibly. File/resource errors propagate as typed failures with path/reason.

## State, Ownership, and Lifecycle
Actor retains canonical root/dependency URLs and immutable snapshots only; it has no persistent security-scope lease or stream. Synchronous I/O within the actor has no suspension inside an ownership transaction. A cancelled request is checked before mutation; completed writes remain completed writes.

## Failure, Concurrency, and Constraints
No fake directory, target, dependency or source is returned. A failed refresh leaves adoption to the parent. A failed write does not mark a buffer saved. External document-provider access and unsupported manifest expressions are reported explicitly. The app owns acquisition of selected project URLs/bookmarks; actor scope lasts only one operation.

## Verification and Change Impact
Native DocumentTests exercise the real filesystem and malformed/dynamic manifest paths. The parent owns buffer/close/persistence integration. Changing bounds, path resolution, target semantics or save conflict handling requires those behavior tests and parent compatibility checks.
