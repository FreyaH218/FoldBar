import Foundation
import CoreGraphics

public enum MenuDropGeometry {
    /// AppKit screen coordinates. Never cover the notch, app menus, or another screen.
    public static func target(screen: CGRect, topInset: CGFloat, visibleRightStart: CGFloat, dividerEnd: CGFloat) -> CGRect? {
        guard screen.width > 0, screen.height > 0, topInset > 0, topInset < screen.height else { return nil }
        let left = max(screen.midX, visibleRightStart, dividerEnd)
        guard left < screen.maxX else { return nil }
        return CGRect(x: left, y: screen.maxY - topInset, width: screen.maxX - left, height: topInset)
    }

    /// Returns the next real item in left-to-right order, regardless of inventory order.
    public static func insertionIndex(at x: CGFloat, frames: [CGRect]) -> Int? {
        frames.indices.filter { frames[$0].width > 0 && x <= frames[$0].midX }
            .min { frames[$0].midX < frames[$1].midX }
    }
}
