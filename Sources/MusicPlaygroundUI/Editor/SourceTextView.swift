#if os(iOS)
import UIKit

/// UIKit owns character edits, marked text, selection and undo for one document.
@MainActor
public final class SourceTextView: UITextView, @MainActor UIEditMenuInteractionDelegate {
    let gutter = SourceLineGutter()
    private(set) var lineStarts = [0]
    private var sourceWidth: CGFloat = 0
    var theme = EditorTheme.midnight
    var documentID = UUID()
    var symbols: [String] = []
    var identifierRanges: [NSRange] = []
    var analyzedSource: String?
    private lazy var symbolMenu = UIEditMenuInteraction(delegate: self)

    public init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        textContainerInset = UIEdgeInsets(top: 8, left: 48, bottom: 8, right: 12)
        autocorrectionType = .no; autocapitalizationType = .none
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        spellCheckingType = .no
        keyboardDismissMode = .interactive
        accessibilityIdentifier = "source-editor"
        gutter.textView = self
        addSubview(gutter)
        addInteraction(symbolMenu)
        inputAssistantItem.leadingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems: [
            UIBarButtonItem(title: "Symbols", style: .plain, target: self, action: #selector(showCompletions))
        ], representativeItem: nil)]
    }
    required init?(coder: NSCoder) { fatalError("Use the programmatic source editor initializer.") }

    override public var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [UIKeyCommand(input: " ", modifierFlags: .control, action: #selector(showCompletions))]
    }

    @objc public func showCompletions() {
        guard isEditable, markedTextRange == nil, analyzedSource == text else { return }
        becomeFirstResponder()
        let caret = selectedTextRange.map { caretRect(for: $0.start) } ?? bounds
        symbolMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: "source-symbols" as NSString,
                                                               sourcePoint: CGPoint(x: caret.midX, y: caret.maxY)))
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                    suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard analyzedSource == text, markedTextRange == nil else { return nil }
        let prefix = (text as NSString).substring(with: completionRange())
        let snapshot = text, selection = selectedRange
        let actions = symbols.filter { prefix.isEmpty || $0.hasPrefix(prefix) }.prefix(24).map { symbol in
            UIAction(title: symbol) { [weak self] _ in
                guard let self, self.text == snapshot, self.selectedRange == selection else { return }
                self.insertCompletion(symbol)
            }
        }
        return UIMenu(title: actions.isEmpty ? "No syntax symbols" : "Syntax symbols · not type-checked", children: actions)
    }

    private func completionRange() -> NSRange {
        let source = text as NSString
        let end = min(source.length, selectedRange.location)
        guard selectedRange.length == 0 else { return selectedRange }
        let start = identifierRanges.first { $0.location < end && end <= NSMaxRange($0) }?.location ?? end
        return NSRange(location: start, length: end - start)
    }

    public func insertCompletion(_ symbol: String) {
        guard isEditable, markedTextRange == nil, analyzedSource == text, symbols.contains(symbol) else { return }
        selectedRange = completionRange()
        insertText(symbol)
    }

    func refreshLines() {
        lineStarts = [0]
        let value = text as NSString
        value.enumerateSubstrings(in: NSRange(location: 0, length: value.length), options: .byLines) { _, content, enclosing, _ in
            let end = NSMaxRange(enclosing)
            if end <= value.length, enclosing.length > content.length {
                self.lineStarts.append(end)
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        sourceWidth = 0
        value.enumerateSubstrings(in: NSRange(location: 0, length: value.length), options: .byLines) { line, _, _, _ in
            if let line { self.sourceWidth = max(self.sourceWidth, (line as NSString).size(withAttributes: attributes).width) }
        }
        setNeedsLayout(); gutter.setNeedsDisplay()
    }

    func appearance(theme: EditorTheme, size: Double) {
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(min(24, max(10, size.isFinite ? size : 12))), weight: .regular)
        self.theme = theme; self.font = font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4; paragraph.tabStops = []
        paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        textStorage.addAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        typingAttributes = attributes.merging([.foregroundColor: theme.palette.foreground]) { _, new in new }
        backgroundColor = theme.palette.background; textColor = theme.palette.foreground
        tintColor = theme.palette.accent
        refreshLines()
    }

    override public func layoutSubviews() {
        let width = max(bounds.width - textContainerInset.left - textContainerInset.right, sourceWidth + 16)
        if textContainer.size.width != width { textContainer.size.width = width }
        super.layoutSubviews()
        gutter.frame = CGRect(x: contentOffset.x, y: contentOffset.y, width: 42, height: bounds.height)
        gutter.setNeedsDisplay()
    }

    override public func insertText(_ text: String) {
        if text == "\t" { super.insertText("    "); return }
        if text == "\n", markedTextRange == nil {
            let source = self.text as NSString
            let selection = selectedRange
            let prefix = source.substring(to: min(selection.location, source.length))
            let line = prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            super.insertText("\n" + indent + (line.trimmingCharacters(in: .whitespaces).hasSuffix("{") ? "    " : ""))
            return
        }
        super.insertText(text)
    }
}
#endif
