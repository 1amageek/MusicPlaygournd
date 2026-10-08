import Foundation

public struct FileTabItem: Identifiable {
    public let id: UUID
    public let name: String
    public let fileURL: URL?
    public let isDirty: Bool
    public let isReadOnly: Bool

    public init(id: UUID, name: String, fileURL: URL?, isDirty: Bool, isReadOnly: Bool) {
        self.id = id; self.name = name; self.fileURL = fileURL
        self.isDirty = isDirty; self.isReadOnly = isReadOnly
    }
}
