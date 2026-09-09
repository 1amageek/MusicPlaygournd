import AppKit
import MusicPlaygourndCore

/// Keeps keyboard focus in the editor while presenting semantic candidates.
@MainActor
final class CompletionTextView: NSTextView, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate {
    var onLayout: (() -> Void)?
    var onCompletionRequest: (() -> Void)?
    var onFormatRequest: (() -> Void)?
    var onTempoSwipe: ((Double) -> Void)?
    private var documentUndoManager = UndoManager()
    private var candidates: [SwiftCompletion] = []
    private var candidateSource = ""
    private var candidateSelection = NSRange(location: 0, length: 0)
    private let completionPopover = NSPopover()
    private let completionTable = NSTableView()
    private let tempoGesture = TempoGestureRecognizer()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tempoGesture.onChange = { [weak self] delta in self?.onTempoSwipe?(delta) }
        tempoGesture.attach(to: window)
    }

    override var undoManager: UndoManager? { documentUndoManager }

    @objc func undo(_ sender: Any?) {
        breakUndoCoalescing()
        documentUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        breakUndoCoalescing()
        documentUndoManager.redo()
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleComment(_:)): return isEditable && !hasMarkedText()
        case #selector(undo(_:)): return documentUndoManager.canUndo
        case #selector(redo(_:)): return documentUndoManager.canRedo
        default: return super.validateMenuItem(menuItem)
        }
    }

    func useUndoManager(_ manager: UndoManager) {
        resetTempoSwipe()
        documentUndoManager = manager
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    func resetTempoSwipe() {
        tempoGesture.reset()
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertNewline(sender); return }
        let source = string as NSString
        let originalLength = source.length
        let selection = selectedRange()
        guard selection.location <= source.length, selection.length <= source.length - selection.location else { return }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
        let opensBlock = prefix.trimmingCharacters(in: .whitespaces).hasSuffix("{")
        let nextIndent = indent + (opensBlock ? (indent.contains("\t") ? "\t" : "    ") : "")
        var insertion = "\n" + nextIndent
        let tail = source.substring(from: NSMaxRange(selection))
        if opensBlock, tail.hasPrefix("}") { insertion += "\n" + indent }
        breakUndoCoalescing()
        insertText(insertion, replacementRange: selection)
        if (string as NSString).length == originalLength - selection.length + insertion.utf16.count {
            setSelectedRange(NSRange(location: selection.location + 1 + nextIndent.utf16.count, length: 0))
        }
        breakUndoCoalescing()
    }

    @objc func toggleComment(_ sender: Any?) {
        guard isEditable, !hasMarkedText() else { return }
        let source = string as NSString
        let selection = selectedRange()
        guard selection.location <= source.length, selection.length <= source.length - selection.location else { return }
        let first = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let last = source.lineRange(for: NSRange(location: selection.location + max(0, selection.length - 1), length: 0))
        let range = NSUnionRange(first, last)
        var lines: [(offset: Int, content: String)] = []
        var position = range.location
        repeat {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            let text = source.substring(with: NSRange(location: position, length: contentsEnd - position))
            let indent = text.prefix { $0 == " " || $0 == "\t" }
            lines.append((position + indent.utf16.count, String(text.dropFirst(indent.count))))
            guard end > position else { break }
            position = end
        } while position < NSMaxRange(range)
        let nonempty = lines.filter { !$0.content.isEmpty }
        let uncomment = !nonempty.isEmpty && nonempty.allSatisfy { $0.content.hasPrefix("//") }
        let replacement = NSMutableString(string: source.substring(with: range))
        var edits: [(offset: Int, removed: Int, added: Int)] = []
        for line in lines.reversed() where !line.content.isEmpty || lines.count == 1 {
            let removed = uncomment ? (line.content.hasPrefix("// ") ? 3 : 2) : 0
            let inserted = uncomment ? "" : "// "
            replacement.replaceCharacters(in: NSRange(location: line.offset - range.location, length: removed), with: inserted)
            edits.append((line.offset, removed, inserted.utf16.count))
        }
        func adjusted(_ offset: Int) -> Int {
            var result = offset
            for edit in edits where edit.offset <= offset {
                result += edit.added - min(edit.removed, offset - edit.offset)
            }
            return result
        }
        let start = adjusted(selection.location)
        let end = adjusted(NSMaxRange(selection))
        dismissCompletions()
        breakUndoCoalescing()
        insertText(replacement as String, replacementRange: range)
        setSelectedRange(NSRange(location: start, length: end - start))
        breakUndoCoalescing()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers == "/" {
            toggleComment(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func complete(_ sender: Any?) { onCompletionRequest?() }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .control,
           event.charactersIgnoringModifiers == "i" {
            onFormatRequest?()
            return
        }
        if modifiers == .control,
           event.charactersIgnoringModifiers == " " {
            complete(nil)
            return
        }
        if !candidates.isEmpty {
            if string == candidateSource, selectedRange() == candidateSelection {
                switch event.keyCode {
                case 125: moveCompletion(by: 1); return
                case 126: moveCompletion(by: -1); return
                case 36, 48: acceptSelectedCompletion(); return
                case 53: dismissCompletions(); return
                default: dismissCompletions()
                }
            } else {
                dismissCompletions()
            }
        }
        if event.keyCode == 48, modifiers.isEmpty, !hasMarkedText() {
            insertSpacesToNextTabStop()
            return
        }
        super.keyDown(with: event)
    }

    private func insertSpacesToNextTabStop() {
        let source = string as NSString
        let selection = selectedRange()
        guard selection.location >= 0, selection.location <= source.length,
              selection.length >= 0, selection.length <= source.length - selection.location else { return }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        var column = 0
        for character in prefix {
            if character == "\t" { column += 4 - column % 4 }
            else { column += 1 }
        }
        let count = 4 - column % 4
        breakUndoCoalescing()
        insertText(String(repeating: " ", count: count), replacementRange: selection)
        breakUndoCoalescing()
    }

    func presentCompletions(_ values: [SwiftCompletion], source: String, selection: NSRange) {
        guard string == source, selectedRange() == selection else { return }
        guard !values.isEmpty else { dismissCompletions(); return }
        candidates = values
        candidateSource = source
        candidateSelection = selection
        if completionTable.tableColumns.isEmpty {
            completionTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("signature")))
            completionTable.headerView = nil
            completionTable.rowHeight = 25
            completionTable.dataSource = self
            completionTable.delegate = self
            completionTable.target = self
            completionTable.action = #selector(chooseCompletion)
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.documentView = completionTable
            let controller = NSViewController()
            controller.view = scroll
            completionPopover.contentViewController = controller
            completionPopover.behavior = .semitransient
            completionPopover.animates = false
            completionPopover.delegate = self
        }
        completionTable.reloadData()
        completionTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let width = min(560, max(300, values.map { CGFloat($0.label.count) * 8 + 32 }.max() ?? 300))
        completionPopover.contentSize = NSSize(width: width, height: CGFloat(min(values.count, 8)) * 27)
        completionTable.tableColumns[0].width = width - 20
        guard window?.isKeyWindow == true, let window else { return }
        let screenRect = firstRect(forCharacterRange: selection, actualRange: nil)
        let rect = convert(window.convertFromScreen(screenRect), from: nil)
        completionPopover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        window.makeFirstResponder(self)
    }

    func moveCompletion(by offset: Int) {
        guard !candidates.isEmpty else { return }
        let row = min(candidates.count - 1, max(0, completionTable.selectedRow + offset))
        completionTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        completionTable.scrollRowToVisible(row)
    }

    @objc private func chooseCompletion() { acceptSelectedCompletion() }

    func acceptSelectedCompletion() {
        let row = completionTable.selectedRow
        guard string == candidateSource, selectedRange() == candidateSelection,
              candidates.indices.contains(row) else { dismissCompletions(); return }
        let candidate = candidates[row]
        dismissCompletions()
        window?.makeFirstResponder(self)
        accept(candidate)
    }

    func dismissCompletions() {
        candidates = []
        completionPopover.close()
    }

    func popoverDidClose(_ notification: Notification) { candidates = [] }

    func numberOfRows(in tableView: NSTableView) -> Int { candidates.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let candidate = candidates[row]
        let label = NSTextField(labelWithString: candidate.label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = candidate.detail
        guard let annotation = candidate.annotation else { return label }
        var text = annotation.unit ?? ""
        if let minimum = annotation.minimum, let maximum = annotation.maximum {
            text += String(format: " %.3g…%.3g", minimum, maximum)
        }
        if annotation.scale == "logarithmic" { text += " log" }
        let detail = NSTextField(labelWithString: text)
        detail.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        detail.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [label, detail])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.toolTip = [candidate.label, text, candidate.detail].compactMap { $0 }.joined(separator: "\n")
        return stack
    }

    func accept(_ candidate: SwiftCompletion) {
        let range = candidate.replacementRange
        let length = (string as NSString).length
        guard range.location >= 0, range.location <= length,
              range.length >= 0, range.length <= length - range.location,
              Range(range, in: string) != nil else { return }
        if let selection = candidate.selectionRange {
            let insertedLength = candidate.insertion.utf16.count
            guard selection.location >= 0, selection.location <= insertedLength,
                  selection.length >= 0, selection.length <= insertedLength - selection.location else { return }
        }
        insertText(candidate.insertion, replacementRange: range)
        if let selection = candidate.selectionRange {
            setSelectedRange(NSRange(location: range.location + selection.location, length: selection.length))
        }
    }
}
