import AppKit
import MusicPlayground
import MusicPlaygourndCore
import SwiftUI

struct EditorDocumentState: Equatable {
    var selection = NSRange(location: 0, length: 0)
    var scrollOffset: CGFloat = 0
    var horizontalScrollOffset: CGFloat = 0
}

struct CodeEditor: NSViewRepresentable {
    @AppStorage("editor.fontSize") private var fontSize = 12.0
    @AppStorage("editor.theme") private var theme: EditorTheme = .midnight
    @Binding var text: String
    let inlineLoop: PreparedLoop?
    let inlineEnabled: Bool
    let resultLines: [Int: Int]
    let beatPosition: Double
    let isPlaying: Bool
    let selectionLine: Int?
    let selectionToken: Int
    let rhythmLines: [Int]
    let rowLines: [Int: Int]
    let patternTexts: [Int: String]
    let activeTokens: [Int: Set<Int>]
    let scrollDelta: CGFloat
    let onLayout: ([Int: CGRect]) -> Void
    let beforeEdit: (NSRange, String) -> Void
    let onEdit: () -> Void
    let completions: @MainActor (String, Int) async throws -> [SwiftCompletion]
    let onCompletionStatus: (String) -> Void
    var semanticTokens: (@MainActor (String) async throws -> [SwiftSemanticToken])? = nil
    var syntaxContext = ""
    var onHighlightStatus: (String) -> Void = { _ in }
    var isReadOnly = false
    var switches: [SwitchControl] = []
    var switchSelections: [Int] = []
    var switchesEnabled = false
    var onSelectSwitch: (Int, Int) -> Void = { _, _ in }
    var activeSwitchRanges: [NSRange] = []
    var sliders: [SliderDefinition] = []
    var sliderValues: [String: Double] = [:]
    var onSliderChange: (String, Double) -> Void = { _, _ in }
    var mutedTracks: [Int: Bool] = [:]
    var onToggleTrackMute: (Int) -> Void = { _ in }
    var onFormat: (@MainActor (String) async throws -> String)? = nil
    var onFormatFailure: @MainActor (String) -> Void = { _ in }
    var selectionRange: NSRange? = nil
    var visualization: PreparedControlVisualization? = nil
    var documentID: UUID? = nil
    var editorState = EditorDocumentState()
    var openDocumentIDs: Set<UUID> = []
    var onEditorStateChange: (UUID, EditorDocumentState) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func viewportRect(_ glyphRect: CGRect, editor: NSTextView, scroll: NSScrollView) -> CGRect {
        let documentRect = glyphRect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        let clipRect = editor.convert(documentRect, to: scroll.contentView)
        return clipRect.offsetBy(dx: -scroll.contentView.bounds.minX, dy: -scroll.contentView.bounds.minY)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.clipsToBounds = true
        scroll.contentView.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = CompletionTextView()
        editor.isEditable = !isReadOnly
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = []
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: 100_000, height: 100_000)
        editor.textContainerInset = NSSize(width: 3, height: 20)
        context.coordinator.applyAppearance(editor)
        context.coordinator.installDocument(documentID, editor: editor, state: editorState)
        editor.string = text
        context.coordinator.restoreSelection(editorState.selection, in: editor)
        editor.delegate = context.coordinator
        context.coordinator.inlineLayout = InlineRhythmLayout(editor: editor)
        editor.setAccessibilityIdentifier("swift-source-editor")
        editor.setAccessibilityLabel("Swift source code")
        scroll.documentView = editor
        let ruler = LineNumberRulerView(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = editor
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.scroll = scroll
        context.coordinator.lineNumberRuler = ruler
        ruler.backgroundColor = theme.palette.background
        ruler.labelColor = theme.palette.comment
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        editor.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.inlineLayout?.layoutCards()
            coordinator?.publishLayout()
        }
        editor.onCompletionRequest = { [weak coordinator = context.coordinator, weak editor] in
            guard let editor else { return }
            coordinator?.requestCompletion(editor, immediate: true)
        }
        editor.onFormatRequest = { [weak coordinator = context.coordinator, weak editor] in
            guard let editor else { return }
            coordinator?.requestFormat(editor)
        }
        context.coordinator.highlight(editor)
        context.coordinator.publishLayout()
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelCompletion()
        coordinator.cancelFormat()
        coordinator.cancelHighlight()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pruneUndoManagers(keeping: openDocumentIDs)
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.isEditable = !isReadOnly
        if context.coordinator.documentID != documentID {
            context.coordinator.switchDocument(to: documentID, text: text, editor: editor, scroll: scroll, state: editorState)
        }
        // AppKit owns marked text until the input method commits it.
        guard !editor.hasMarkedText() else { return }
        context.coordinator.applyAppearance(editor)
        context.coordinator.updateHighlightContext(editor)
        if editor.string != text {
            context.coordinator.cancelCompletion()
            context.coordinator.cancelFormat()
            context.coordinator.replaceText(text, in: editor)
            context.coordinator.highlight(editor)
        }
        let delta = scrollDelta - context.coordinator.lastScrollDelta
        if delta != 0 {
            context.coordinator.lastScrollDelta = scrollDelta
            let clip = scroll.contentView
            var proposed = clip.bounds
            proposed.origin.y -= delta
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
        }
        context.coordinator.inlineLayout?.update(loop: inlineLoop, rowLines: resultLines, enabled: inlineEnabled,
            beat: beatPosition, isPlaying: isPlaying, mutedTracks: mutedTracks,
            onToggleTrackMute: onToggleTrackMute, visualization: visualization,
            switches: switches, selections: switchSelections, switchesEnabled: switchesEnabled,
            onSelectSwitch: onSelectSwitch)
        context.coordinator.publishLayout()
        context.coordinator.highlightPlayback(editor)
        if context.coordinator.lastSelection != selectionToken, let range = selectionRange {
            context.coordinator.lastSelection = selectionToken
            let count = (editor.string as NSString).length
            guard range.location >= 0, range.location <= count, range.length >= 0, range.length <= count - range.location else { return }
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            editor.window?.makeFirstResponder(editor)
        } else if context.coordinator.lastSelection != selectionToken, let selectionLine {
            context.coordinator.lastSelection = selectionToken
            let lines = editor.string.components(separatedBy: "\n")
            guard selectionLine > 0, selectionLine <= lines.count else { return }
            let offset = lines.prefix(selectionLine - 1).reduce(0) { $0 + $1.utf16.count + 1 }
            let range = NSRange(location: offset, length: lines[selectionLine - 1].utf16.count)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            editor.window?.makeFirstResponder(editor)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var lastSelection = 0
        var lastScrollDelta: CGFloat = 0
        weak var scroll: NSScrollView?
        weak var lineNumberRuler: LineNumberRulerView?
        var inlineLayout: InlineRhythmLayout?
        private var sliderViews: [String: NSSlider] = [:]
        private var published: [Int: CGRect] = [:]
        private var rangeSource = ""
        private var rangeLines: [Int: Int] = [:]
        private var rangePatterns: [Int: String] = [:]
        private var literalRanges: [Int: [NSRange]] = [:]
        private var completionTask: Task<Void, Never>?
        private var completionGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var highlightGeneration = 0
        private var highlightedSource: String?
        private var highlightedTokens: [SwiftSemanticToken] = []
        private var highlightedContext = ""

        private var formatTask: Task<Void, Never>?
        private var formatGeneration = 0
        private var previousSwitchRanges: [NSRange] = []
        private var previousActive: [Int: Set<Int>] = [:]
        private(set) var documentID: UUID?
        private var undoManagers: [UUID: UndoManager] = [:]
        private let untitledUndoManager = UndoManager()

        func highlightPlayback(_ editor: NSTextView) {
            guard let layout = editor.layoutManager else { return }
            let text = editor.string as NSString
            let changed = rangeSource != editor.string || rangeLines != parent.rowLines || rangePatterns != parent.patternTexts
            guard changed || previousActive != parent.activeTokens || previousSwitchRanges != parent.activeSwitchRanges else { return }
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
            if changed {
                rangeSource = editor.string
                rangeLines = parent.rowLines
                rangePatterns = parent.patternTexts
                literalRanges = [:]
                for (id, pattern) in parent.patternTexts {
                    guard let line = parent.rowLines[id] else { continue }
                    literalRanges[id] = PlayingLiteral.tokenRanges(pattern: pattern, line: line, source: editor.string)
                }
            }
            previousSwitchRanges = parent.activeSwitchRanges
            for range in previousSwitchRanges where range.location >= 0 && NSMaxRange(range) <= text.length {
                layout.addTemporaryAttribute(.backgroundColor,
                    value: parent.theme.palette.accent.withAlphaComponent(0.08), forCharacterRange: range)
            }
            previousActive = parent.activeTokens
            for (id, ranges) in literalRanges {
                for (index, range) in ranges.enumerated() {
                    let active = parent.activeTokens[id]?.contains(index) == true
                    layout.addTemporaryAttributes([
                        .backgroundColor: parent.theme.palette.accent.withAlphaComponent(active ? 0.9 : 0.04),
                        .foregroundColor: active ? parent.theme.palette.background : parent.theme.palette.accent
                    ], forCharacterRange: range)
                }
            }
        }
        private var viewportSize = NSSize.zero

        @objc func scrolled() {
            if let size = scroll?.contentView.bounds.size, size != viewportSize {
                viewportSize = size
                inlineLayout?.layoutCards()
            }
            publishEditorState()
            publishLayout()
        }

        func installDocument(_ id: UUID?, editor: CompletionTextView, state: EditorDocumentState) {
            documentID = id
            editor.useUndoManager(undoManager(for: id))
        }

        func switchDocument(to id: UUID?, text: String, editor: NSTextView, scroll: NSScrollView, state: EditorDocumentState) {
            publishEditorState()
            cancelHighlight()
            highlightedSource = nil
            highlightedTokens = []
            cancelCompletion()
            cancelFormat()
            if let editor = editor as? CompletionTextView {
                editor.dismissCompletions()
                editor.breakUndoCoalescing()
                editor.useUndoManager(undoManager(for: id))
            }
            documentID = id
            lastSelection = 0
            lastScrollDelta = parent.scrollDelta
            previousActive = [:]
            rangeSource = ""
            rangeLines = [:]
            rangePatterns = [:]
            published = [:]
            replaceText(text, in: editor)
            highlight(editor)
            restoreSelection(state.selection, in: editor)
            let clip = scroll.contentView
            var proposed = clip.bounds
            proposed.origin = CGPoint(x: max(0, state.horizontalScrollOffset) - clip.contentInsets.left,
                                      y: max(0, state.scrollOffset) - clip.contentInsets.top)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
        }

        func replaceText(_ text: String, in editor: NSTextView) {
            let selection = editor.selectedRange()
            let undo = editor.undoManager
            undo?.disableUndoRegistration()
            editor.string = text
            editor.textStorage?.addAttribute(.foregroundColor, value: parent.theme.palette.foreground,
                range: NSRange(location: 0, length: (text as NSString).length))
            let count = (text as NSString).length
            let location = min(selection.location, count)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
            undo?.enableUndoRegistration()
        }

        func restoreSelection(_ selection: NSRange, in editor: NSTextView) {
            let length = (editor.string as NSString).length
            guard selection.location >= 0, selection.location <= length,
                  selection.length >= 0, selection.length <= length - selection.location else {
                editor.setSelectedRange(NSRange(location: 0, length: 0))
                return
            }
            editor.setSelectedRange(selection)
        }

        private func undoManager(for id: UUID?) -> UndoManager {
            guard let id else { return untitledUndoManager }
            if let manager = undoManagers[id] { return manager }
            let manager = UndoManager()
            undoManagers[id] = manager
            return manager
        }

        func pruneUndoManagers(keeping ids: Set<UUID>) {
            guard !ids.isEmpty else { return }
            undoManagers = undoManagers.filter { ids.contains($0.key) }
        }

        private func publishEditorState() {
            guard let scroll, let editor = scroll.documentView as? NSTextView, let id = documentID else { return }
            let clip = scroll.contentView
            parent.onEditorStateChange(id, EditorDocumentState(selection: editor.selectedRange(),
                scrollOffset: max(0, clip.bounds.minY + clip.contentInsets.top),
                horizontalScrollOffset: max(0, clip.bounds.minX + clip.contentInsets.left)))
        }
        @objc private func sliderChanged(_ sender: NSSlider) {
            guard let id = sender.identifier?.rawValue else { return }
            sender.setAccessibilityValue(sender.doubleValue)
            parent.onSliderChange(id, sender.doubleValue)
        }

        private func layoutSliders(_ editor: NSTextView) {
            let wanted = Set(parent.sliders.map(\.id))
            for id in Array(sliderViews.keys) where !wanted.contains(id) {
                sliderViews.removeValue(forKey: id)?.removeFromSuperview()
            }
            guard let manager = editor.layoutManager, let container = editor.textContainer else { return }
            manager.ensureLayout(for: container)
            let text = editor.string as NSString
            var starts = [0]
            var offset = 0
            while offset < text.length {
                offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
                starts.append(offset)
            }
            var rightEdges: [Int: CGFloat] = [:]
            for definition in parent.sliders {
                guard definition.line > 0, definition.line <= starts.count,
                      starts[definition.line - 1] < text.length else { continue }
                let slider: NSSlider
                if let existing = sliderViews[definition.id] { slider = existing }
                else {
                    slider = NSSlider(value: definition.value, minValue: definition.range.lowerBound,
                        maxValue: definition.range.upperBound, target: self, action: #selector(sliderChanged(_:)))
                    slider.controlSize = .mini
                    slider.isContinuous = true
                    slider.identifier = NSUserInterfaceItemIdentifier(definition.id)
                    slider.setAccessibilityLabel("Slider, line \(definition.line)")
                    sliderViews[definition.id] = slider
                    editor.addSubview(slider)
                }
                slider.minValue = definition.range.lowerBound
                slider.maxValue = definition.range.upperBound
                // AppKit owns the knob during tracking; adoption must not pull it backward.
                if NSEvent.pressedMouseButtons == 0 { slider.doubleValue = parent.sliderValues[definition.id] ?? definition.value }
                let glyph = manager.glyphIndexForCharacter(at: starts[definition.line - 1])
                let rect = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
                let x = rightEdges[definition.line] ?? (editor.textContainerOrigin.x + rect.maxX + 14)
                slider.frame = NSRect(x: x, y: editor.textContainerOrigin.y + rect.minY,
                                      width: 120, height: rect.height)
                rightEdges[definition.line] = slider.frame.maxX + 14
            }
            let width = rightEdges.values.max() ?? 0
            if inlineLayout?.minimumContentWidth != width {
                inlineLayout?.minimumContentWidth = width
                inlineLayout?.layoutCards()
            }
            let otherChildren = editor.subviews.filter { !($0 is NSSlider) }
            editor.setAccessibilityChildren(otherChildren + sliderViews.values.sorted { $0.frame.minY < $1.frame.minY })
        }

        func publishLayout() {
            guard let scroll, let editor = scroll.documentView as? NSTextView,
                  let layout = editor.layoutManager, let container = editor.textContainer else { return }
            layout.ensureLayout(for: container)
            lineNumberRuler?.needsDisplay = true
            layoutSliders(editor)
            let text = editor.string as NSString
            let requested = Set(parent.rhythmLines)
            var rectangles: [Int: CGRect] = [:]
            var offset = 0
            var line = 1
            while offset < text.length {
                if requested.contains(line) {
                    let glyph = layout.glyphIndexForCharacter(at: offset)
                    let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    rectangles[line] = CodeEditor.viewportRect(rect, editor: editor, scroll: scroll)
                }
                offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
                line += 1
            }
            guard rectangles != published else { return }
            published = rectangles
            let identity = documentID
            Task { @MainActor [weak self] in
                guard let self, self.documentID == identity, self.published == rectangles else { return }
                self.parent.onLayout(rectangles)
            }
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !parent.isReadOnly else { return false }
            cancelHighlight()
            if let replacementString { parent.beforeEdit(affectedCharRange, replacementString) }
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            cancelFormat()
            publishEditorState()
        }
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText(), parent.text != editor.string else { return }
            cancelFormat()
            parent.text = editor.string
            highlight(editor)
            parent.onEdit()
            publishLayout()
            guard let editor = editor as? CompletionTextView else { return }
            let offset = editor.selectedRange().location
            let text = editor.string as NSString
            guard editor.selectedRange().length == 0, offset > 0, offset <= text.length else {
                completionTask?.cancel()
                return
            }
            let last = text.character(at: offset - 1)
            if last == 46 || (65...90).contains(last) || (97...122).contains(last) || last == 95 {
                requestCompletion(editor, immediate: last == 46)
            } else {
                completionTask?.cancel()
                parent.onCompletionStatus("")
            }
        }

        func requestCompletion(_ editor: CompletionTextView, immediate: Bool) {
            completionTask?.cancel()
            completionGeneration += 1
            let generation = completionGeneration
            let source = editor.string
            let selection = editor.selectedRange()
            let identity = documentID
            guard selection.length == 0 else { return }
            completionTask = Task { @MainActor [weak self, weak editor] in
                do {
                    if !immediate { try await Task.sleep(for: .milliseconds(250)) }
                    guard let self, let editor, self.documentID == identity else { return }
                    self.parent.onCompletionStatus("Swift completion…")
                    let values = try await self.parent.completions(source, selection.location)
                    try Task.checkCancellation()
                    guard generation == self.completionGeneration, self.documentID == identity else { return }
                    guard editor.string == source, editor.selectedRange() == selection else {
                        self.parent.onCompletionStatus("")
                        return
                    }
                    self.parent.onCompletionStatus(values.isEmpty ? "No Swift completions" : "")
                    editor.presentCompletions(values, source: source, selection: selection)
                } catch is CancellationError {
                    // A later source/cursor request owns completion presentation.
                } catch {
                    guard let self, generation == self.completionGeneration, self.documentID == identity else { return }
                    self.parent.onCompletionStatus("Completion: \(error.localizedDescription)")
                }
            }
        }

        func requestFormat(_ editor: CompletionTextView) {
            guard !parent.isReadOnly, let format = parent.onFormat, !editor.hasMarkedText() else { return }
            cancelCompletion()
            formatTask?.cancel()
            formatGeneration += 1
            let generation = formatGeneration
            let identity = documentID
            let source = editor.string
            let selection = editor.selectedRange()
            editor.dismissCompletions()
            parent.onCompletionStatus("Formatting Swift…")
            formatTask = Task { @MainActor [weak self, weak editor] in
                do {
                    let formatted = try await format(source)
                    try Task.checkCancellation()
                    guard let self, let editor,
                          self.formatGeneration == generation,
                          self.documentID == identity,
                          editor.string == source,
                          editor.selectedRange() == selection else { return }
                    guard formatted.utf8.count <= 65_536 else {
                        throw EvaluationError.invalidSource("Formatted source exceeds the 64 KiB editor limit.")
                    }
                    guard formatted != source else {
                        self.formatTask = nil
                        self.parent.onCompletionStatus("")
                        return
                    }
                    self.formatTask = nil
                    let range = NSRange(location: 0, length: (source as NSString).length)
                    editor.breakUndoCoalescing()
                    editor.insertText(formatted, replacementRange: range)
                    editor.breakUndoCoalescing()
                    editor.setSelectedRange(restoredSelection(selection, in: formatted))
                    editor.breakUndoCoalescing()
                    self.parent.onCompletionStatus("")
                } catch is CancellationError {
                    // A newer source, selection, document, or format request owns the result.
                } catch {
                    guard let self, self.formatGeneration == generation, self.documentID == identity else { return }
                    self.formatTask = nil
                    self.parent.onCompletionStatus("")
                    self.parent.onFormatFailure(error.localizedDescription)
                }
            }
        }

        func cancelCompletion() {
            completionTask?.cancel()
            completionGeneration += 1
            parent.onCompletionStatus("")
        }

        func cancelFormat() {
            formatTask?.cancel()
            formatTask = nil
            formatGeneration += 1
            parent.onCompletionStatus("")
        }

        private func restoredSelection(_ selection: NSRange, in formatted: String) -> NSRange {
            let text = formatted as NSString
            let length = text.length
            let location = min(max(0, selection.location), length)
            let requestedLength = max(0, selection.length)
            let end = min(length, location + requestedLength)
            let proposed = NSRange(location: location, length: max(0, end - location))
            if let range = Range(proposed, in: formatted) {
                return text.rangeOfComposedCharacterSequences(for: NSRange(range, in: formatted))
            }

            var safeLocation = location
            while safeLocation > 0 {
                let candidate = NSRange(location: safeLocation, length: 0)
                if Range(candidate, in: formatted) != nil {
                    return candidate
                }
                safeLocation -= 1
            }
            return NSRange(location: 0, length: 0)
        }

        private var appliedFontSize: Double?
        private var appliedTheme: EditorTheme?

        func applyAppearance(_ editor: NSTextView) {
            let size = parent.fontSize.isFinite ? min(24, max(10, parent.fontSize)) : 12
            guard appliedFontSize != size || appliedTheme != parent.theme else { return }
            appliedFontSize = size
            appliedTheme = parent.theme
            let palette = parent.theme.palette
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.tabStops = []
            paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
            editor.font = font
            editor.defaultParagraphStyle = paragraph
            let range = NSRange(location: 0, length: (editor.string as NSString).length)
            editor.textStorage?.addAttributes([.font: font, .paragraphStyle: paragraph], range: range)
            editor.typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: palette.foreground]
            editor.textColor = palette.foreground
            editor.backgroundColor = palette.background
            editor.insertionPointColor = palette.accent
            editor.selectedTextAttributes = [.backgroundColor: palette.accent.withAlphaComponent(0.25)]
            if let ruler = lineNumberRuler {
                ruler.backgroundColor = palette.background
                ruler.labelColor = palette.comment
                ruler.needsDisplay = true
            }
            rangeSource = ""
            highlight(editor)
        }

        func cancelHighlight() {
            highlightTask?.cancel()
            highlightGeneration += 1
        }

        func updateHighlightContext(_ editor: NSTextView) {
            guard highlightedContext != parent.syntaxContext else { return }
            highlightedContext = parent.syntaxContext
            highlightedSource = nil
            highlightedTokens = []
            highlight(editor)
        }

        func highlight(_ editor: NSTextView) {
            guard !editor.hasMarkedText() else { return }
            if highlightedSource == editor.string {
                applySyntaxColors(editor)
                rangeSource = ""
                highlightPlayback(editor)
                return
            }
            cancelHighlight()
            highlightedSource = nil
            highlightedTokens = []
            guard let request = parent.semanticTokens else { return }
            let source = editor.string
            let identity = documentID
            let context = parent.syntaxContext
            let generation = highlightGeneration
            highlightTask = Task { @MainActor [weak self, weak editor] in
                do {
                    try await Task.sleep(for: .milliseconds(180))
                    var tokens: [SwiftSemanticToken] = []
                    for attempt in 0..<2 {
                        do {
                            tokens = try await request(source)
                            break
                        } catch let error as SwiftCompletionError {
                            let transient: Bool
                            switch error {
                            case .timedOut, .processExited, .processFailed: transient = true
                            default: transient = false
                            }
                            guard attempt == 0, transient else { throw error }
                            try Task.checkCancellation()
                            self?.parent.onHighlightStatus("Reconnecting syntax highlighting…")
                            try await Task.sleep(for: .milliseconds(500))
                        }
                    }
                    try Task.checkCancellation()
                    guard let self, let editor, generation == self.highlightGeneration,
                          self.documentID == identity, self.parent.syntaxContext == context,
                          editor.string == source, !editor.hasMarkedText() else { return }
                    self.highlightedSource = source
                    self.highlightedTokens = tokens
                    self.applySyntaxColors(editor)
                    self.rangeSource = ""
                    self.highlightPlayback(editor)
                    self.parent.onHighlightStatus("")
                } catch is CancellationError {
                    // The next committed source snapshot owns its presentation.
                } catch {
                    guard let self, generation == self.highlightGeneration, self.documentID == identity else { return }
                    self.parent.onHighlightStatus("Syntax highlighting: \(error.localizedDescription)")
                }
            }
        }

        private func applySyntaxColors(_ editor: NSTextView) {
            guard !editor.hasMarkedText(), highlightedSource == editor.string, let storage = editor.textStorage else { return }
            let length = storage.length
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: parent.theme.palette.foreground, range: NSRange(location: 0, length: length))
            for token in highlightedTokens where token.range.location >= 0 && NSMaxRange(token.range) <= length {
                storage.addAttribute(.foregroundColor, value: parent.theme.palette.color(for: token), range: token.range)
            }
            storage.endEditing()
        }
    }
}
