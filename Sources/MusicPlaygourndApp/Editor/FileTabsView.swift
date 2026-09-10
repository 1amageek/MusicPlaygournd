import SwiftUI

struct FileTabsView: View {
    @Bindable var model: SessionModel
    var accent: Color = .accentColor
    var deckName: String? = nil
    var editing = true
    var activate: () -> Void = {}
    var load: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                if let deckName { Text(deckName).font(.system(size: 12, weight: .bold)).foregroundStyle(accent).padding(.horizontal, 10) }
                ForEach(model.documents.filter { $0.fileURL != nil || $0.isDirty }) { document in
                    HStack(spacing: 8) {
                        Button { activate(); model.selectDocument(document.id) } label: {
                            HStack(spacing: 7) {
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
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(document.id == model.activeDocumentID ? .white.opacity(0.07) : .clear)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
                    .overlay(alignment: .bottom) {
                        if editing && document.id == model.activeDocumentID { Rectangle().fill(accent).frame(height: 2) }
                    }
                    .contextMenu {
                        if let load { Button("Load into Deck " + (deckName ?? "")) { activate(); model.selectDocument(document.id); load() } }
                    }
                    .help(document.fileURL?.path ?? "Unsaved session")
                }
                if deckName != nil {
                    Button { activate(); model.openDocument() } label: { Image(systemName: "plus").padding(.horizontal, 10) }
                        .buttonStyle(.plain).accessibilityLabel("Open file in Deck " + (deckName ?? ""))
                }
            }
        }.scrollIndicators(.hidden).frame(height: 30).clipped()
            .background(.black.opacity(0.12)).accessibilityIdentifier("document-tabs")
    }
}
