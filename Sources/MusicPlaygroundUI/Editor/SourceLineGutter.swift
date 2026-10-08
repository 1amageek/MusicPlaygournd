#if os(iOS)
import UIKit

@MainActor
final class SourceLineGutter: UIView {
    weak var textView: SourceTextView?
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { fatalError("Use the programmatic gutter initializer.") }

    override func draw(_ rect: CGRect) {
        guard let view = textView, let font = view.font else { return }
        view.theme.palette.background.setFill(); UIRectFill(bounds)
        let manager = view.layoutManager
        let visible = CGRect(x: 0, y: view.contentOffset.y - view.textContainerInset.top,
                             width: view.textContainer.size.width, height: bounds.height)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: view.textContainer)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: view.theme.palette.comment, .paragraphStyle: paragraph]
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            let character = manager.characterIndexForGlyph(at: range.location)
            var low = 0, high = view.lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                if view.lineStarts[middle] <= character { low = middle + 1 } else { high = middle }
            }
            let line = max(0, low - 1)
            guard view.lineStarts[line] == character else { return }
            let y = used.minY + view.textContainerInset.top - view.contentOffset.y
            (String(line + 1) as NSString).draw(in: CGRect(x: 0, y: y, width: 33, height: font.lineHeight + 4), withAttributes: attributes)
        }
    }
}
#endif
