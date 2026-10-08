import Foundation

nonisolated protocol ProjectFileAccess: Sendable {
    func openProject(_ root: URL) async throws -> ProjectSnapshot
    func createProject(template: String) async throws -> ProjectSnapshot
    func read(_ url: URL) async throws -> DocumentSnapshot
    func save(_ url: URL, source: String, baseline: String) async throws
    func createNumberedSource(in directory: URL) async throws -> URL
    func bookmark(_ root: URL) async throws -> Data
    func resolveBookmark(_ data: Data) async throws -> URL
}
