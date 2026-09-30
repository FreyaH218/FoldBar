import CoreGraphics

/// Associates a hosted status window with exactly one accessibility item.
public enum MenuWindowGeometry {
    public static func uniqueItem(in frames: [CGRect?], hostedBy window: CGRect) -> Int? {
        let matches = frames.indices.filter { index in
            guard let frame = frames[index], frame.width > 1, frame.height > 1 else { return false }
            let overlap = frame.intersection(window)
            return !overlap.isNull && overlap.width >= frame.width * 0.75 &&
                overlap.height >= frame.height * 0.75 &&
                window.width <= frame.width + 32 && window.height <= frame.height + 20
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
