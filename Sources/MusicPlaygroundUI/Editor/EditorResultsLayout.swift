import SwiftUI

/// Keeps the native editor at one stable child identity while arranging accepted results.
public struct EditorResultsLayout: Layout {
    public let mode: Int
    public let size: CGSize
    public init(mode: Int, size: CGSize) { self.mode = mode; self.size = size }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: mode == 1 ? max(620, size.width) : size.width, height: size.height)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let resultHeight = mode == 2 ? min(280, max(100, bounds.height * 0.38)) : 0
        let sideWidth = mode == 1 ? max(280, bounds.width * 0.38) : 0
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width - sideWidth, height: bounds.height - resultHeight))
        subviews[1].place(at: CGPoint(x: bounds.maxX - sideWidth, y: bounds.minY), proposal: ProposedViewSize(width: sideWidth, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - resultHeight), proposal: ProposedViewSize(width: bounds.width, height: resultHeight))
    }
}
