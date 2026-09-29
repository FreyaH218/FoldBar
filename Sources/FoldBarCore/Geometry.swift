import Foundation
import CoreGraphics

public enum BarGeometry {
    /// AppKit's global coordinate system is anchored to the primary screen.
    public static func quartzRect(_ appKitRect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: appKitRect.minX, y: primaryHeight - appKitRect.maxY,
               width: appKitRect.width, height: appKitRect.height)
    }

    public static func panelOrigin(anchor: CGPoint, size: CGSize, screen: CGRect,
                                   topInset: CGFloat, margin: CGFloat = 12) -> CGPoint {
        let x = min(max(anchor.x - size.width / 2, screen.minX + margin),
                    max(screen.minX + margin, screen.maxX - size.width - margin))
        let y = max(screen.minY + margin, screen.maxY - topInset - size.height - 8)
        return CGPoint(x: x, y: y)
    }

    /// Off-screen and notch-covered rectangles must not be treated as clickable.
    public static func isObscured(_ item: CGRect, screens: [CGRect], notches: [CGRect]) -> Bool {
        guard item.width > 0, item.height > 0, item.origin.x.isFinite, item.origin.y.isFinite else { return true }
        let contained = screens.contains { $0.contains(item) }
        return !contained || notches.contains { $0.intersects(item) }
    }
}

public enum ItemSearch {
    public static func matches(_ query: String, name: String, detail: String) -> Bool {
        let tokens = query.split(whereSeparator: { $0.isWhitespace })
        return tokens.allSatisfy {
            (name + " " + detail).range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
