import AppKit
import SwiftUI
import MusicPlaygourndCore
import Testing
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct CompletionEditorTests {
        @Test(.timeLimit(.minutes(1)))
        func commentShortcutPreservesLinesAndSupportsUndo() throws {
            let editor = CompletionTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            editor.isRichText = false
            editor.allowsUndo = true
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                characters: "/", charactersIgnoringModifiers: "/", isARepeat: false, keyCode: 44))
            for (source, selection, expected) in [
                ("    音🎵()\nnext()", NSRange(location: 5, length: 0), "    // 音🎵()\nnext()"),
                ("  a()\r\n\tb()\r\nc()", NSRange(location: 0, length: 13), "  // a()\r\n\t// b()\r\nc()"),
                ("// a\n// b", NSRange(location: 0, length: 9), "a\nb"),
                ("a\n\nb", NSRange(location: 0, length: 4), "// a\n\n// b"),
                ("", NSRange(location: 0, length: 0), "// ")
            ] {
                editor.string = source
                editor.setSelectedRange(selection)
                editor.undoManager?.removeAllActions()
                #expect(editor.performKeyEquivalent(with: event))
                #expect(editor.string == expected)
                let selected = editor.selectedRange()
                #expect(NSMaxRange(selected) <= (editor.string as NSString).length)
                editor.undo(nil)
                #expect(editor.string == source)
                editor.redo(nil)
                #expect(editor.string == expected)
            }
            editor.isEditable = false
            let before = editor.string
            editor.toggleComment(nil)
            #expect(editor.string == before)
            editor.isEditable = true
            editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
            let marked = editor.string
            editor.toggleComment(nil)
            #expect(editor.string == marked && editor.hasMarkedText())
        }

        @Test(.timeLimit(.minutes(3)))
        func testCompletionPreviewIsReadOnlyAndAcceptanceIsOneUndoableEdit() throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            let editor = CompletionTextView(frame: window.contentView!.bounds)
            editor.isRichText = false
            editor.allowsUndo = true
            let observer = EditObserver()
            editor.delegate = observer
            window.contentView = editor
            window.makeFirstResponder(editor)
            let original = "// 🎵\nSample(\"kick\").ga"
            editor.string = original
            editor.setSelectedRange(NSRange(location: original.utf16.count, length: 0))
            let range = (original as NSString).range(of: "ga", options: .backwards)
            let item = SwiftCompletion(label: "gain(value: Double)", detail: nil,
                insertion: "gain(0.5)", replacementRange: range,
                selectionRange: NSRange(location: 5, length: 3),
                annotation: CompletionAnnotation(unit: "amplitude", minimum: 0, maximum: 2))
            editor.presentCompletions([item], source: original, selection: editor.selectedRange())
            let cell = try #require(editor.tableView(NSTableView(), viewFor: nil, row: 0) as? NSStackView)
            let labels = cell.arrangedSubviews.compactMap { $0 as? NSTextField }
            #expect(labels.map(\.stringValue) == ["gain(value: Double)", "amplitude 0…2"])
            #expect(labels[1].contentCompressionResistancePriority(for: .horizontal) == .required)
            editor.moveCompletion(by: 1)
            #expect(editor.string == original)
            #expect(observer.changes == 0)
            editor.acceptSelectedCompletion()
            #expect(editor.string == "// 🎵\nSample(\"kick\").gain(0.5)")
            #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "0.5")
            #expect(observer.changes == 1)
            #expect(observer.ranges == [range])
            let undo = try #require(editor.undoManager)
            #expect(undo.canUndo)
            undo.undo()
            #expect(editor.string == original)
            for (before, position, length, expected, caret) in [
                ("    .gain(0.5)", 14, 0, "    .gain(0.5)\n    ", 19),
                ("    Track {", 11, 0, "    Track {\n        ", 20),
                ("\tTrack {}", 8, 0, "\tTrack {\n\t\t\n\t}", 11),
                ("    // 🎵", 9, 0, "    // 🎵\n    ", 14),
                ("    abc", 4, 3, "    \n    ", 9)
            ] {
                editor.string = before
                editor.setSelectedRange(NSRange(location: position, length: length))
                undo.removeAllActions()
                editor.insertNewline(nil)
                #expect(editor.string == expected)
                #expect(editor.selectedRange() == NSRange(location: caret, length: 0))
                undo.undo()
                #expect(editor.string == before)
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func testEditorCommandsUseTheFocusedDocumentHistory() throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            let editor = CompletionTextView(frame: window.contentView!.bounds)
            editor.allowsUndo = true
            editor.isRichText = false
            window.contentView = editor
            window.makeFirstResponder(editor)
            var source = ""
            let view = CodeEditor(text: Binding(get: { source }, set: { source = $0 }),
                inlineLoop: nil, inlineEnabled: false, resultLines: [:], beatPosition: 0,
                isPlaying: false, selectionLine: nil, selectionToken: 0, rhythmLines: [],
                rowLines: [:], patternTexts: [:], activeTokens: [:], scrollDelta: 0,
                onLayout: { _ in }, beforeEdit: { _, _ in }, onEdit: {},
                completions: { _, _ in [] }, onCompletionStatus: { _ in })
            let coordinator = view.makeCoordinator()
            editor.delegate = coordinator
            let first = UndoManager()
            editor.useUndoManager(first)
            editor.insertText("first", replacementRange: NSRange(location: 0, length: 0))
            editor.breakUndoCoalescing()
            #expect(editor.undoManager === first)
            #expect(editor.validateMenuItem(NSMenuItem(title: "Undo", action: #selector(CompletionTextView.undo(_:)), keyEquivalent: "z")))
            editor.undo(nil)
            #expect(editor.string.isEmpty)
            editor.redo(nil)
            #expect(editor.string == "first")
            let second = UndoManager()
            editor.useUndoManager(second)
            editor.string = ""
            editor.insertText("second", replacementRange: NSRange(location: 0, length: 0))
            editor.breakUndoCoalescing()
            #expect(editor.undoManager === second)
            editor.undo(nil)
            #expect(editor.string.isEmpty)
            editor.redo(nil)
            #expect(editor.string == "second")
            #expect(first.canUndo)
        }

        @Test(.timeLimit(.minutes(3)))
        func testStaleCompletionCannotReplaceNewSource() {
            let editor = CompletionTextView()
            editor.string = "value.ga"
            editor.setSelectedRange(NSRange(location: 8, length: 0))
            let item = SwiftCompletion(label: "gain", detail: nil, insertion: "gain(1)",
                replacementRange: NSRange(location: 6, length: 2), selectionRange: nil)
            editor.presentCompletions([item], source: editor.string, selection: editor.selectedRange())
            editor.string = "value.pan"
            editor.acceptSelectedCompletion()
            #expect(editor.string == "value.pan")
        }

        @Test(.timeLimit(.minutes(3)))
        func testControlSpaceRequestsCompletionOnce() throws {
            let editor = CompletionTextView()
            var requests = 0
            editor.onCompletionRequest = { requests += 1 }
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: 49
            ))

            editor.keyDown(with: event)

            #expect(requests == 1)
            var formats = 0
            editor.onFormatRequest = { formats += 1 }
            let formatKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.control], timestamp: 0, windowNumber: 0, context: nil,
                characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
            editor.keyDown(with: formatKey)
            #expect(formats == 1)
            editor.string = "a"
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            let tabKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
            editor.keyDown(with: tabKey)
            #expect(editor.string == "a   ")
        }

        @Test(.timeLimit(.minutes(3)))
        func testTabAcceptsSelectedCompletionAsOneUndoableEdit() throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            let editor = CompletionTextView(frame: window.contentView!.bounds)
            editor.isRichText = false
            editor.allowsUndo = true
            let observer = EditObserver()
            editor.delegate = observer
            window.contentView = editor
            window.makeFirstResponder(editor)
            let original = "Sample(\"kick\").ga"
            editor.string = original
            editor.setSelectedRange(NSRange(location: original.utf16.count, length: 0))
            let range = (original as NSString).range(of: "ga", options: .backwards)
            let item = SwiftCompletion(label: "gain(value: Double)", detail: nil,
                insertion: "gain(0.5)", replacementRange: range,
                selectionRange: NSRange(location: 5, length: 3),
                annotation: CompletionAnnotation(unit: "amplitude", minimum: 0, maximum: 2))
            editor.presentCompletions([item], source: original, selection: editor.selectedRange())
            let cell = try #require(editor.tableView(NSTableView(), viewFor: nil, row: 0) as? NSStackView)
            let labels = cell.arrangedSubviews.compactMap { $0 as? NSTextField }
            #expect(labels.map(\.stringValue) == ["gain(value: Double)", "amplitude 0…2"])
            #expect(labels[1].contentCompressionResistancePriority(for: .horizontal) == .required)
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: 48
            ))

            editor.keyDown(with: event)

            #expect(editor.string == "Sample(\"kick\").gain(0.5)")
            #expect(observer.changes == 1)
            let undo = try #require(editor.undoManager)
            #expect(undo.canUndo)
            undo.undo()
            #expect(editor.string == original)
        }

        @Test(.timeLimit(.minutes(1)))
        func semanticColorsPreserveEditingAndRejectStaleDocuments() async throws {
            var source = "struct Old {}"
            let editor = CompletionTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            editor.isRichText = false
            editor.allowsUndo = true
            editor.string = source
            var delivered = false
            var requestStarted = false
            var view = CodeEditor(text: Binding(get: { source }, set: { source = $0 }),
                inlineLoop: nil, inlineEnabled: false, resultLines: [:], beatPosition: 0,
                isPlaying: false, selectionLine: nil, selectionToken: 0, rhythmLines: [],
                rowLines: [:], patternTexts: [:], activeTokens: [:], scrollDelta: 0,
                onLayout: { _ in }, beforeEdit: { _, _ in }, onEdit: {},
                completions: { _, _ in [] }, onCompletionStatus: { _ in },
                semanticTokens: { snapshot in
                    requestStarted = true
                    if snapshot.contains("Old") {
                        // An uncooperative response must still be rejected by document identity.
                        await Task.detached {
                            do { try await Task.sleep(for: .milliseconds(100)) }
                            catch { Issue.record(error) }
                        }.value
                    }
                    return [SwiftSemanticToken(range: NSRange(location: 0, length: 6), kind: "keyword")]
                }, onHighlightStatus: { status in
                    #expect(status.isEmpty)
                    delivered = true
                })
            let coordinator = view.makeCoordinator()
            editor.delegate = coordinator
            coordinator.installDocument(UUID(), editor: editor, state: EditorDocumentState())
            coordinator.highlight(editor)
            let deadline = ContinuousClock.now + .seconds(3)
            while !requestStarted, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(requestStarted)
            let scroll = NSScrollView()
            scroll.documentView = editor
            source = "let fresh = 1"
            coordinator.switchDocument(to: UUID(), text: source, editor: editor, scroll: scroll, state: EditorDocumentState())
            coordinator.cancelHighlight()
            try await Task.sleep(for: .milliseconds(130))
            #expect(!delivered)
            #expect(editor.string == source)
            editor.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
            editor.insertText("2", replacementRange: editor.selectedRange())
            editor.breakUndoCoalescing()
            coordinator.cancelHighlight()
            let selection = editor.selectedRange()
            let undo = try #require(editor.undoManager)
            #expect(undo.canUndo)
            view.semanticTokens = { _ in [SwiftSemanticToken(range: NSRange(location: 0, length: 3), kind: "keyword")] }
            coordinator.parent = view
            coordinator.highlight(editor)
            while !delivered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(delivered)
            #expect(editor.selectedRange() == selection)
            #expect(editor.string == "let fresh = 12")
            let theme = EditorTheme(rawValue: UserDefaults.standard.string(forKey: "editor.theme") ?? "") ?? .midnight
            #expect(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == theme.palette.keyword)
            undo.undo()
            #expect(editor.string == "let fresh = 1")
            coordinator.cancelHighlight()
            editor.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0), replacementRange: editor.selectedRange())
            let marked = editor.markedRange()
            let markedSource = editor.string
            coordinator.highlight(editor)
            #expect(editor.markedRange() == marked)
            #expect(editor.string == markedSource)
            editor.unmarkText()
            for theme in EditorTheme.allCases {
                #expect(theme.palette.color(for: SwiftSemanticToken(range: NSRange(location: 0, length: 1), kind: "struct")) == theme.palette.type)
                #expect(theme.palette.function != theme.palette.foreground)
            }
            coordinator.cancelHighlight()
            coordinator.cancelCompletion()
        }

        @MainActor private final class EditObserver: NSObject, NSTextViewDelegate {
            var changes = 0
            var ranges: [NSRange] = []
            func textDidChange(_ notification: Notification) { changes += 1 }
            func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
                ranges.append(affectedCharRange)
                return true
            }
        }

    }
}
