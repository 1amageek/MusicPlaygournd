import AppKit
import SwiftUI
import Testing
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct EditorTabsIntegrationTests {
        @Test(.timeLimit(.minutes(1)))
        func longDocumentDrawingStaysInsideViewport() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let file = root.appending(path: "Long.swift")
            try (0..<200).map { "// Line \($0)" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            let model = SessionModel(audioEnabled: false)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
                styleMask: [.titled], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: ContentView(model: model))
            window.contentView = hosting
            do {
                try model.openDocument(at: file)
                try await settle(hosting)
                let editor = try #require(findEditor(hosting))
                let scroll = try #require(editor.enclosingScrollView)
                let clip = scroll.contentView
                clip.scroll(to: NSPoint(x: 0, y: 500))
                scroll.reflectScrolledClipView(clip)
                try await settle(hosting)
                let visible = editor.convert(editor.visibleRect, to: clip)
                #expect(clip.bounds.insetBy(dx: -1, dy: -1).contains(visible), "Visible document \(visible) escaped viewport \(clip.bounds)")
                #expect(editor.frame.height > clip.bounds.height)
                #expect(clip.bounds.minY >= 499)
                #expect(scroll.convert(scroll.bounds, to: hosting).height < hosting.bounds.height)
                window.contentView = nil
                try await model.shutdown()
            } catch {
                window.contentView = nil
                try await model.shutdown()
                throw error
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func productionEditorKeepsTwoDirtyTabsAndTheirUndo() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let a = root.appending(path: "A.swift"), b = root.appending(path: "B.swift")
            try "// A\n".write(to: a, atomically: true, encoding: .utf8)
            try "// B\n".write(to: b, atomically: true, encoding: .utf8)
            let model = SessionModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 540),
                styleMask: [.titled], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: ContentView(model: model))
            window.contentView = hosting
            do {
                try model.openDocument(at: a)
                try await settle(hosting)
                let first = model.activeDocument
                let editor = try #require(findEditor(hosting))
                window.makeFirstResponder(editor)
                editor.insertText("// Edited A\n", replacementRange: NSRange(location: 0, length: 0))
                editor.breakUndoCoalescing()
                #expect(first.source == "// Edited A\n// A\n" && first.isDirty)
                try model.openDocument(at: b)
                try await settle(hosting)
                #expect(findEditor(hosting) === editor)
                #expect(editor.string == "// B\n")
                try expectVisibleText(editor)
                let second = model.activeDocument
                editor.insertText("// Edited B\n", replacementRange: NSRange(location: 0, length: 0))
                editor.breakUndoCoalescing()
                model.selectDocument(first.id)
                try await settle(hosting)
                #expect(editor.string == "// Edited A\n// A\n")
                try expectVisibleText(editor)
                try #require(editor.undoManager).undo()
                #expect(editor.string == "// A\n")
                #expect(first.source == "// A\n" && second.source == "// Edited B\n// B\n")
                model.selectDocument(second.id)
                try await settle(hosting)
                #expect(editor.string == "// Edited B\n// B\n")
                try #require(editor.undoManager).undo()
                #expect(editor.string == "// B\n" && second.source == "// B\n")
                #expect(!model.closeDocument(first.id, decision: .cancel))
                #expect(model.documents.count == 3)
                #expect(model.saveDocument())
                #expect(try String(contentsOf: b, encoding: .utf8) == "// B\n")
                let longSource = (0..<150).map { "// Line \($0)" }.joined(separator: "\n")
                editor.insertText(longSource, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
                try await settle(hosting)
                let scroll = try #require(editor.enclosingScrollView)
                let clip = scroll.contentView
                #expect(editor.frame.width >= scroll.contentSize.width)
                clip.scroll(to: CGPoint(x: -clip.contentInsets.left, y: 600))
                scroll.reflectScrolledClipView(clip)
                try await settle(hosting)

                #expect(abs(clip.bounds.minY - 600) < 1)
                #expect(editor.visibleRect.minY >= 599)
                clip.scroll(to: CGPoint(x: -clip.contentInsets.left, y: -clip.contentInsets.top))
                scroll.reflectScrolledClipView(clip)
                try await settle(hosting)
                try expectVisibleText(editor)
                editor.setSelectedRange(NSRange(location: 3, length: 0))
                editor.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: editor.selectedRange())
                try await settle(hosting)
                #expect(editor.hasMarkedText())
                #expect(editor.string.hasPrefix("// にほんLine"))
                editor.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                try await settle(hosting)
                #expect(editor.hasMarkedText())
                editor.insertText("日本語", replacementRange: editor.markedRange())
                try await settle(hosting)
                #expect(!editor.hasMarkedText())
                #expect(editor.string.hasPrefix("// 日本語Line"))
                #expect(model.source == editor.string)
                #expect(editor.selectedRange() == NSRange(location: 6, length: 0))
                window.contentView = nil
                try await model.shutdown()
            } catch {
                window.contentView = nil
                try await model.shutdown()
                throw error
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func savingManifestReloadsPackageWithoutReplacingDirtyDocuments() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try SessionModel.createProject(at: root)
            let model = SessionModel()
            do {
                model.openProject(at: root)
                let deadline = ContinuousClock.now.advanced(by: .seconds(40))
                while model.project == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
                _ = try #require(model.project)
                let session = model.activeDocument
                session.source += "\n// Keep this unsaved edit\n"
                session.isDirty = true
                try model.openDocument(at: root.appending(path: "Package.swift"))
                let manifest = model.activeDocument
                manifest.source = manifest.source.replacingOccurrences(of: "name: \"\(root.lastPathComponent)\"", with: "name: \"Renamed\"", range: manifest.source.range(of: "name: \"\(root.lastPathComponent)\""))
                #expect(model.saveDocument())
                let reloadDeadline = ContinuousClock.now.advanced(by: .seconds(40))
                while model.project?.name != "Renamed", ContinuousClock.now < reloadDeadline { try await Task.sleep(for: .milliseconds(50)) }
                #expect(model.project?.name == "Renamed")
                #expect(model.activeDocumentID == manifest.id)
                #expect(session.isDirty && session.source.hasSuffix("// Keep this unsaved edit\n"))
                try await model.shutdown()
                try FileManager.default.removeItem(at: root)
            } catch {
                try await model.shutdown()
                try FileManager.default.removeItem(at: root)
                throw error
            }
        }

        private func expectVisibleText(_ editor: CompletionTextView) throws {
            let manager = try #require(editor.layoutManager)
            let container = try #require(editor.textContainer)
            manager.ensureLayout(for: container)
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
                .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            if let ruler = editor.enclosingScrollView?.verticalRulerView {
                let glyphInRuler = editor.convert(rect, to: ruler)
                #expect(glyphInRuler.minX >= ruler.bounds.maxX, "Glyph overlaps the line-number gutter: \(glyphInRuler), ruler: \(ruler.bounds)")
            }
            #expect(editor.visibleRect.contains(rect), "Glyph: \(rect), visible: \(editor.visibleRect), frame: \(editor.frame)")
        }

        private func settle(_ view: NSView) async throws {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
        }

        private func findEditor(_ view: NSView) -> CompletionTextView? {
            if let editor = view as? CompletionTextView { return editor }
            for child in view.subviews {
                if let editor = findEditor(child) { return editor }
            }
            return nil
        }
    }
}
