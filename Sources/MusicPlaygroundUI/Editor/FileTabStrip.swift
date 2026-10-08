import SwiftUI

public struct FileTabStrip: View {
    private let tabs: [FileTabItem]
    private let selected: UUID?
    private let audible: UUID?
    private let accent: Color
    private let deckName: String?
    private let editing: Bool
    private let canCreate: Bool
    private let select: (UUID) -> Void
    private let close: (UUID) -> Void
    private let create: () -> Void
    private let load: ((UUID, Int) -> Void)?

    public init(tabs: [FileTabItem], selected: UUID?, audible: UUID?, accent: Color, deckName: String?,
                editing: Bool, canCreate: Bool, select: @escaping (UUID) -> Void,
                close: @escaping (UUID) -> Void, create: @escaping () -> Void,
                load: ((UUID, Int) -> Void)? = nil) {
        self.tabs = tabs; self.selected = selected; self.audible = audible; self.accent = accent
        self.deckName = deckName; self.editing = editing; self.canCreate = canCreate
        self.select = select; self.close = close; self.create = create; self.load = load
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                if let deckName {
                    Text(deckName).font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 17, height: 17).background(accent.gradient, in: RoundedRectangle(cornerRadius: 3))
                        .padding(.horizontal, 7)
                }
                ForEach(tabs) { document in
                    tab(document)
                }
                if let deckName {
                    Button(action: create) {
                        Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Create file in Deck " + deckName)
                        .accessibilityIdentifier("create-file-" + deckName).disabled(!canCreate)
                        .help("Create a numbered Swift file in the project")
                }
            }
        }.scrollIndicators(.hidden).frame(height: 28).clipped()
            .background(.black.opacity(0.12)).accessibilityIdentifier("document-tabs-" + (deckName ?? ""))
    }

    private func tab(_ document: FileTabItem) -> some View {
        HStack(spacing: 6) {
            Button { select(document.id) } label: {
                HStack(spacing: 5) {
                    if audible == document.id { Image(systemName: "waveform").foregroundStyle(accent) }
                    Image(systemName: document.name == "Package.swift" ? "shippingbox" :
                        (document.fileURL?.pathExtension.lowercased() == "swift" || document.fileURL == nil ? "swift" : "doc"))
                        .foregroundStyle(.orange)
                    Text(document.name).lineLimit(1)
                    if document.isDirty { Circle().fill(.secondary).frame(width: 5, height: 5).accessibilityLabel("Unsaved changes") }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Select \(document.name)")
            Button { close(document.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 12, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Close \(document.name)")
        }
        .font(.system(size: 11)).padding(.horizontal, 8).frame(height: 28)
        .background(document.id == selected ? .white.opacity(0.07) : .clear)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
        .overlay(alignment: .bottom) {
            if editing && document.id == selected { Rectangle().fill(accent).frame(height: 2) }
        }
        .contextMenu {
            if let load, document.fileURL?.pathExtension.lowercased() == "swift", document.name != "Package.swift", !document.isReadOnly {
                Button("Load into Deck A") { load(document.id, 0) }
                Button("Load into Deck B") { load(document.id, 1) }
            }
        }
        .draggableFile(document.fileURL)
        .help(document.fileURL?.path ?? "Unsaved session")
    }
}

extension View {
    @ViewBuilder
    fileprivate func draggableFile(_ url: URL?) -> some View {
        if let url { self.draggable(url) } else { self }
    }
}
