#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class SourceInlineLayout: NSObject, @MainActor NSLayoutManagerDelegate {
    private weak var editor: SourceTextView?
    private var source = ""
    private var anchors: [Int: Int] = [:]
    private var endings: [Int: CGFloat] = [:]
    private var lineEnds: [Int: Int] = [:]
    private var cards: [Int: UIView & UIContentView] = [:]
    init(editor: SourceTextView) { self.editor = editor; super.init(); editor.layoutManager.delegate = self }
    func update(_ results: [InlineSourceResult]) throws {
        guard let editor else { return }
        let text = editor.text as NSString
        guard results.count <= 32, Set(results.map(\.id)).count == results.count,
              results.allSatisfy({ $0.line > 0 && $0.line <= editor.lineStarts.count }) else {
            throw SourceResultError.invalidAnchors
        }
        let valid = results
        let mapped = Dictionary(valid.map { ($0.id, $0.line) }, uniquingKeysWith: { first, _ in first })
        if source != editor.text || anchors != mapped {
            source = editor.text; anchors = mapped; endings = [:]; lineEnds = [:]
            for line in Set(mapped.values) {
                let start = editor.lineStarts[line - 1]
                guard start < text.length else { continue }
                let end = NSMaxRange(text.lineRange(for: NSRange(location: start, length: 0))) - 1
                endings[end] = CGFloat(mapped.values.filter { $0 == line }.count) * 52
                lineEnds[line] = end
            }
            editor.layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: text.length), actualCharacterRange: nil)
        }
        for id in Array(cards.keys) where mapped[id] == nil { cards.removeValue(forKey: id)?.removeFromSuperview() }
        for result in valid {
            let configuration = UIHostingConfiguration { result.content }.margins(.all, 0)
            let card = cards[result.id] ?? configuration.makeContentView()
            card.configuration = configuration
            if card.superview == nil { editor.addSubview(card) }
            cards[result.id] = card
        }
        editor.setNeedsLayout()
    }
    func layoutManager(_ layoutManager: NSLayoutManager, paragraphSpacingAfterGlyphAt glyphIndex: Int,
                       withProposedLineFragmentRect rect: CGRect) -> CGFloat {
        endings[layoutManager.characterIndexForGlyph(at: glyphIndex)] ?? 0
    }
    func layout() {
        guard let editor else { return }
        let manager = editor.layoutManager; manager.ensureLayout(for: editor.textContainer)
        let width = max(160, editor.bounds.width - editor.textContainerInset.left - editor.textContainerInset.right)
        for (line, end) in lineEnds {
            guard end < editor.textStorage.length else { continue }
            let glyph = manager.glyphIndexForCharacter(at: end)
            let rect = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            for (index, id) in anchors.keys.filter({ anchors[$0] == line }).sorted().enumerated() {
                cards[id]?.frame = CGRect(x: editor.textContainerInset.left, y: editor.textContainerInset.top + rect.maxY + 4 + CGFloat(index) * 52, width: width, height: 48)
            }
        }
    }
}
#endif
