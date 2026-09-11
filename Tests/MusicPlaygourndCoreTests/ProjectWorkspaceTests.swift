import Foundation
import Testing
@testable import MusicPlaygourndCore

struct ProjectWorkspaceTests {
    @Test(.timeLimit(.minutes(1)))
    func unchangedBytesPreserveTimestampAndUnicodeChangesReachTheCompiler() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".swift")
        let composed = "// é\nstruct Session {}"
        let decomposed = "// e\u{301}\nstruct Session {}"
        #expect(composed == decomposed)
        try ProjectWorkspace.writeIfChanged(composed, to: file)
        let date = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        try ProjectWorkspace.writeIfChanged(composed, to: file)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == date)
        try ProjectWorkspace.writeIfChanged(decomposed, to: file)
        #expect(try Data(contentsOf: file) == Data(decomposed.utf8))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date != date)
        try FileManager.default.removeItem(at: file)
    }
}
