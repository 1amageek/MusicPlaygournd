#if os(iOS)
import SwiftUI
import UIKit

public struct SourceEditor: UIViewRepresentable {
    @AppStorage("editor.fontSize") private var fontSize = 12.0
    @AppStorage("editor.theme") private var theme: EditorTheme = .midnight
    public let documentID: UUID
    public let source: String
    public var inlineResults: [InlineSourceResult]
    public var requestedLines: Set<Int>
    public var scrollPosition: Double
    public var onLineRects: ([Int: CGRect]) -> Void
    public var retainedDocuments: Set<UUID>
    public var isReadOnly: Bool
    public var formatRequest: Int
    public var completionRequest: Int
    public var isSyntaxEnabled: Bool
    public var revealRequest: Int
    public var revealRange: NSRange?
    public var analyzer: any SwiftSourceAnalyzing
    public var onEdit: (UUID, String) -> Void
    public var onCommittedEdits: ((UUID, String, [(NSRange, String)]) -> Void)?
    public var onAnalysis: (UUID, SourceAnalysis) -> Void
    public var onFailure: (String) -> Void

    public init(documentID: UUID, source: String, retainedDocuments: Set<UUID>? = nil,
                isReadOnly: Bool = false, formatRequest: Int = 0, completionRequest: Int = 0,
                isSyntaxEnabled: Bool = true, revealRequest: Int = 0, revealRange: NSRange? = nil,
                analyzer: any SwiftSourceAnalyzing = SwiftSourceAnalyzer(),
                onEdit: @escaping (UUID, String) -> Void,
                onCommittedEdits: ((UUID, String, [(NSRange, String)]) -> Void)? = nil,
                onAnalysis: @escaping (UUID, SourceAnalysis) -> Void = { _, _ in },
                onFailure: @escaping (String) -> Void, inlineResults: [InlineSourceResult] = [], requestedLines: Set<Int> = [], scrollPosition: Double = 0, onLineRects: @escaping ([Int: CGRect]) -> Void = { _ in }) {
        self.inlineResults = inlineResults; self.requestedLines = requestedLines; self.scrollPosition = scrollPosition; self.onLineRects = onLineRects
        self.documentID = documentID; self.source = source
        self.retainedDocuments = retainedDocuments ?? [documentID]
        self.isReadOnly = isReadOnly; self.formatRequest = formatRequest; self.completionRequest = completionRequest; self.analyzer = analyzer
        self.isSyntaxEnabled = isSyntaxEnabled; self.revealRequest = revealRequest; self.revealRange = revealRange
        self.onCommittedEdits = onCommittedEdits; self.onEdit = onEdit; self.onAnalysis = onAnalysis; self.onFailure = onFailure
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeUIView(context: Context) -> UIView {
        let host = UIView(); host.accessibilityIdentifier = "native-editor-host"
        context.coordinator.host = host; context.coordinator.update(self)
        return host
    }
    public func updateUIView(_ view: UIView, context: Context) { context.coordinator.update(self) }
    public static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.shutdown() }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: SourceEditor
        weak var host: UIView?
        private var editors: [UUID: SourceTextView] = [:]
        private var active: SourceTextView?
        private var task: Task<Void, Never>?
        private var generation = 0
        private var tokenSource: String?
        private var tokenSnapshot = SourceAnalysis(tokens: [], diagnostics: [])
        private var lastFormatRequest = 0
        private var lastCompletionRequest = 0
        private var lastRevealRequest = 0
        private var appearanceKey = ""
        private var previousScroll = 0.0
        private var previousRects: [Int: CGRect] = [:]
        private var updating = false
        private var pendingEdits: [UUID: [(NSRange, String)]] = [:]
        init(_ parent: SourceEditor) {
            self.parent = parent
            lastFormatRequest = parent.formatRequest; lastCompletionRequest = parent.completionRequest
            lastRevealRequest = parent.revealRequest
        }

        func update(_ parent: SourceEditor) {
            guard !updating else { return }
            updating = true
            defer { updating = false }
            self.parent = parent
            guard let host, active?.markedTextRange == nil else { return }
            for id in editors.keys where !parent.retainedDocuments.contains(id) {
                editors[id]?.undoManager?.removeAllActions(); editors.removeValue(forKey: id); pendingEdits.removeValue(forKey: id)
            }
            if active?.documentID != parent.documentID {
                task?.cancel(); generation += 1; tokenSource = nil
                active?.removeFromSuperview()
                let editor = editors[parent.documentID] ?? SourceTextView()
                editor.documentID = parent.documentID; editor.delegate = self
                editor.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(editor)
                NSLayoutConstraint.activate([editor.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    editor.trailingAnchor.constraint(equalTo: host.trailingAnchor), editor.topAnchor.constraint(equalTo: host.topAnchor),
                    editor.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
                editors[parent.documentID] = editor; active = editor; appearanceKey = ""
            }
            guard let editor = active else { return }
            editor.isEditable = !parent.isReadOnly
            if editor.text != parent.source {
                let selection = editor.selectedRange, offset = editor.contentOffset
                editor.textStorage.replaceCharacters(in: NSRange(location: 0, length: editor.textStorage.length), with: parent.source)
                editor.selectedRange = Self.bounded(selection, length: editor.textStorage.length)
                editor.contentOffset = offset; tokenSource = nil; editor.refreshLines()
            }
            do { try editor.inlineLayout.update(parent.inlineResults) }
            catch {
                let identity = editor.documentID, message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.active?.documentID == identity else { return }
                    self.parent.onFailure(message)
                }
            }
            if previousScroll != parent.scrollPosition {
                let delta = parent.scrollPosition - previousScroll; previousScroll = parent.scrollPosition
                let maxY = max(0, editor.contentSize.height - editor.bounds.height)
                editor.setContentOffset(CGPoint(x: editor.contentOffset.x, y: min(maxY, max(0, editor.contentOffset.y - delta))), animated: false)
            }
            publishLineRects()
            let key = "\(parent.theme.rawValue):\(parent.fontSize):\(parent.isSyntaxEnabled)"
            if appearanceKey != key {
                editor.appearance(theme: parent.theme, size: parent.fontSize)
                appearanceKey = key
                if !parent.isSyntaxEnabled { tokenSource = nil }
                if tokenSource == editor.text {
                    do { try apply(tokenSnapshot, to: editor) }
                    catch { parent.onFailure(error.localizedDescription) }
                }
            }
            if lastCompletionRequest != parent.completionRequest {
                lastCompletionRequest = parent.completionRequest
                editor.showCompletions()
            }
            if lastRevealRequest != parent.revealRequest, let range = parent.revealRange {
                lastRevealRequest = parent.revealRequest
                guard range.location >= 0, range.location <= editor.textStorage.length, range.length >= 0,
                      range.length <= editor.textStorage.length - range.location else {
                    parent.onFailure(SourceAnalysisError.invalidParserRange.localizedDescription); return
                }
                editor.selectedRange = range; editor.scrollRangeToVisible(range)
            }
            if lastFormatRequest != parent.formatRequest {
                lastFormatRequest = parent.formatRequest
                format(editor)
            } else if tokenSource != editor.text { analyze(editor) }
        }

        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !updating, let editor = textView as? SourceTextView, editor.isEditable else { return false }
            pendingEdits[editor.documentID, default: []].append((range, text))
            return true
        }
        public func textViewDidChange(_ textView: UITextView) {
            guard !updating, let editor = textView as? SourceTextView, editor.markedTextRange == nil else { return }
            let candidates = pendingEdits.removeValue(forKey: editor.documentID) ?? []
            var replay = parent.source
            var valid = true
            for (range, replacement) in candidates {
                let text = replay as NSString
                guard range.location >= 0, range.length >= 0, range.location <= text.length,
                      range.length <= text.length - range.location else { valid = false; break }
                replay = text.replacingCharacters(in: range, with: replacement)
            }
            if let commit = parent.onCommittedEdits {
                commit(editor.documentID, editor.text, valid && replay == editor.text ? candidates : [])
            } else { parent.onEdit(editor.documentID, editor.text) }
            editor.analyzedSource = nil; editor.symbols = []
            editor.refreshLines(); tokenSource = nil
            if editor === active { analyze(editor) }
            if editor.documentID != parent.documentID { update(parent) }
        }
        public func textViewDidChangeSelection(_ textView: UITextView) {
            if !updating, textView.markedTextRange == nil, active?.documentID != parent.documentID { update(parent) }
        }
        public func scrollViewDidScroll(_ scrollView: UIScrollView) { active?.gutter.setNeedsDisplay(); publishLineRects() }
        private func publishLineRects() {
            guard let editor = active else { return }
            editor.layoutManager.ensureLayout(for: editor.textContainer)
            var rects: [Int: CGRect] = [:]
            for line in parent.requestedLines where line > 0 && line <= editor.lineStarts.count {
                let start = editor.lineStarts[line - 1]
                guard start < editor.textStorage.length else { continue }
                let glyph = editor.layoutManager.glyphIndexForCharacter(at: start)
                var rect = editor.layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
                rect.origin.y += editor.textContainerInset.top - editor.contentOffset.y
                rects[line] = rect
            }
            guard rects != previousRects else { return }; previousRects = rects
            let id = parent.documentID
            Task { [weak self] in
                guard let self, parent.documentID == id else { return }
                parent.onLineRects(rects)
            }
        }

        private func analyze(_ editor: SourceTextView) {
            task?.cancel(); generation += 1
            let snapshot = editor.text ?? "", id = editor.documentID, revision = generation
            let analyzer = parent.analyzer, syntaxEnabled = parent.isSyntaxEnabled
            task = Task { [weak self, weak editor] in
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    let result = syntaxEnabled ? try await analyzer.analyze(source: snapshot) : SourceAnalysis(tokens: [], diagnostics: [])
                    try Task.checkCancellation()
                    guard let self, let editor, revision == self.generation,
                          editor === self.active, id == self.parent.documentID,
                          editor.text == snapshot, editor.markedTextRange == nil else { return }
                    try self.apply(result, to: editor)
                    self.tokenSource = snapshot; self.tokenSnapshot = result
                    self.parent.onAnalysis(id, result); self.parent.onFailure("")
                } catch is CancellationError { }
                catch { if let self, revision == self.generation { self.parent.onFailure(error.localizedDescription) } }
            }
        }

        private func apply(_ result: SourceAnalysis, to editor: SourceTextView) throws {
            guard editor.markedTextRange == nil else { return }
            let selection = editor.selectedRange, offset = editor.contentOffset
            let storage = editor.textStorage, palette = editor.theme.palette
            guard result.tokens.allSatisfy({
                $0.range.location >= 0 && $0.range.location <= storage.length && $0.range.length >= 0 &&
                    $0.range.length <= storage.length - $0.range.location
            }) else { throw SourceAnalysisError.invalidParserRange }
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: palette.foreground, range: NSRange(location: 0, length: storage.length))
            for token in result.tokens {
                storage.addAttribute(.foregroundColor, value: palette.color(for: token.kind), range: token.range)
            }
            storage.endEditing()
            editor.symbols = result.symbols; editor.analyzedSource = editor.text
            editor.identifierRanges = result.tokens.filter { ["property", "type", "function"].contains($0.kind) }.map(\.range)
            editor.selectedRange = selection; editor.contentOffset = offset
        }

        private func format(_ editor: SourceTextView) {
            guard !parent.isReadOnly, parent.isSyntaxEnabled, editor.markedTextRange == nil else { return }
            task?.cancel(); generation += 1
            let snapshot = editor.text ?? "", revision = generation, selection = editor.selectedRange
            let analyzer = parent.analyzer
            task = Task { [weak self, weak editor] in
                do {
                    let formatted = try await analyzer.format(source: snapshot)
                    try Task.checkCancellation()
                    guard let self, let editor, editor === self.active, revision == self.generation,
                          editor.text == snapshot, editor.selectedRange == selection, editor.markedTextRange == nil else { return }
                    guard formatted != snapshot else { return }
                    editor.selectedRange = NSRange(location: 0, length: editor.textStorage.length)
                    editor.insertText(formatted)
                    editor.selectedRange = Self.bounded(selection, length: editor.textStorage.length)
                    self.textViewDidChange(editor)
                } catch is CancellationError { }
                catch { if let self, revision == self.generation { self.parent.onFailure(error.localizedDescription) } }
            }
        }
        private static func bounded(_ range: NSRange, length: Int) -> NSRange {
            let start = min(length, max(0, range.location))
            return NSRange(location: start, length: min(max(0, range.length), length - start))
        }
        func shutdown() { task?.cancel(); task = nil; generation += 1; editors.removeAll(); pendingEdits.removeAll(); active = nil }
    }
}
#endif
