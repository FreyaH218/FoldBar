import Foundation
import CoreGraphics

public enum NativeLayoutGeometry {
    public static func isAdjacent(_ item: CGRect, to boundary: CGRect, onRight: Bool) -> Bool {
        guard item.width > 0, item.height > 0, boundary.width > 0,
              abs(item.midY - boundary.midY) < 10 else { return false }
        let gap = onRight ? item.minX - boundary.maxX : boundary.minX - item.maxX
        return gap >= -1 && gap <= 8
    }

    /// Input frames follow the requested order. Every real icon must be right of the divider.
    public static func matches(_ ordered: [CGRect], after boundary: CGRect) -> Bool {
        guard boundary.width > 0, boundary.height > 0 else { return false }
        var edge = boundary.maxX
        for rect in ordered {
            guard rect.width > 0, rect.height > 0, rect.minX >= edge - 1,
                  abs(rect.midY - boundary.midY) < 10 else { return false }
            edge = rect.maxX
        }
        return true
    }
}
