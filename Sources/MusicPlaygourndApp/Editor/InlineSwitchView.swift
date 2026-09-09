import AppKit

/// Source-attached native buttons with generous live-performance hit targets.
@MainActor
final class InlineSwitchView: NSView {
    static let height: CGFloat = 48
    private let scrolling = NSScrollView()
    private let content = NSView()
    private var buttons: [NSButton] = []
    private var titles: [String] = []
    private var select: (Int) -> Void = { _ in }
    private var enabled = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrolling.drawsBackground = false
        scrolling.hasHorizontalScroller = true
        scrolling.autohidesScrollers = true
        scrolling.scrollerStyle = .overlay
        scrolling.documentView = content
        addSubview(scrolling)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func update(name: String, cases: [String], selected: Int, enabled: Bool,
                select: @escaping (Int) -> Void) {
        self.select = select
        self.enabled = enabled
        if titles != cases {
            buttons.forEach { $0.removeFromSuperview() }
            titles = cases
            buttons = cases.enumerated().map { index, title in
                let button = NSButton(title: title.uppercased(), target: self, action: #selector(changed(_:)))
                button.tag = index
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                button.layer?.borderWidth = 1
                button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                button.setAccessibilityLabel("\(name): \(title)")
                content.addSubview(button)
                return button
            }
        }
        for (index, button) in buttons.enumerated() {
            button.isEnabled = enabled
            let active = index == selected
            button.contentTintColor = active ? .black : .labelColor
            button.layer?.backgroundColor = (active ? NSColor.systemMint : NSColor.white.withAlphaComponent(0.045)).cgColor
            button.layer?.borderColor = (active ? NSColor.systemMint : NSColor.white.withAlphaComponent(0.2)).cgColor
            button.setAccessibilityValue(index == selected ? "Selected" : "Not selected")
        }
        setAccessibilityLabel("Switch \(name)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scrolling.frame = bounds
        var x: CGFloat = 0
        for button in buttons {
            let width = max(96, button.intrinsicContentSize.width + 32)
            button.frame = CGRect(x: x, y: 4, width: width, height: 40)
            x += width + 8
        }
        content.frame = CGRect(x: 0, y: 0, width: x, height: Self.height)

    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled else { return nil }
        return super.hitTest(point)
    }

    @objc private func changed(_ sender: NSButton) {
        select(sender.tag)
    }
}
