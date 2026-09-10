import SwiftUI

struct FileTabsView: View {
    @Bindable var model: SessionModel
    var accent: Color = .accentColor
    var deckName: String? = nil
    var editing = true
    var activate: () -> Void = {}
    var load: ((SessionDocument, Int) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                if let deckName { Text(deckName).font(.system(size: 10, weight: .bold)).foregroundStyle(.black).frame(width: 17, height: 17).background(accent.gradient, in: RoundedRectangle(cornerRadius: 3)).padding(.horizontal, 7) }
                ForEach(model.documents.filter { $0.fileURL != nil || $0.isDirty }) { document in
                    HStack(spacing: 6) {
                        Button { activate(); model.selectDocument(document.id) } label: {
                            HStack(spacing: 5) {
                                if model.isPlaying && model.audibleDocumentID == document.id {
                                    Image(systemName: "waveform").foregroundStyle(accent)
                                }
                                Image(systemName: document.name == "Package.swift" ? "shippingbox" : (document.fileURL?.pathExtension == "swift" || document.fileURL == nil ? "swift" : "doc")).foregroundStyle(.orange)
                                Text(document.name).lineLimit(1)
                                if document.isDirty { Circle().fill(.secondary).frame(width: 5, height: 5) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Select \(document.name)")
                        Button { model.closeDocument(document.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("Close \(document.name)")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(document.id == model.activeDocumentID ? .white.opacity(0.07) : .clear)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
                    .overlay(alignment: .bottom) {
                        if editing && document.id == model.activeDocumentID { Rectangle().fill(accent).frame(height: 2) }
                    }
                    .contextMenu {
                        if let load, document.fileURL?.pathExtension == "swift", document.name != "Package.swift", !document.isReadOnly {
                            Button("Load into Deck A") { load(document, 0) }
                            Button("Load into Deck B") { load(document, 1) }
                        }
                    }
                    .draggableFile(document.fileURL)
                    .help(document.fileURL?.path ?? "Unsaved session")
                }
                if deckName != nil {
                    Button { activate(); model.openDocument() } label: { Image(systemName: "plus").padding(.horizontal, 7) }
                        .buttonStyle(.plain).accessibilityLabel("Open file in Deck " + (deckName ?? ""))
                }
            }
        }.scrollIndicators(.hidden).frame(height: 28).clipped()
            .background(.black.opacity(0.12)).accessibilityIdentifier("document-tabs")
    }
}

extension View {
    @ViewBuilder
    fileprivate func draggableFile(_ url: URL?) -> some View {
        if let url { self.draggable(url) } else { self }
    }
}
