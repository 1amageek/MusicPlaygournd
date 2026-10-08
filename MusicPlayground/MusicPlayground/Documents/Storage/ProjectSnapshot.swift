import Foundation

struct ProjectSnapshot: Sendable {
    let root: URL
    let scopeURL: URL
    let entries: [ProjectTreeEntry]
    let targets: [ProjectTarget]
    let dependencyRoot: URL?
    let dependencyEntries: [ProjectTreeEntry]
}
