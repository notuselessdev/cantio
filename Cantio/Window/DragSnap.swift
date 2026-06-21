import AppKit

/// Pure geometry for re-center / drag-snapping the floating pill. No
/// `NSWindow` or `NSScreen` instance required — takes raw rects so it's unit
/// testable. AppKit coordinates (origin bottom-left, +Y up).
/// Fixed footprint of the drag placeholder pill — and therefore the guide
/// slot. Deliberately independent of the live lyric so the rulers never
/// resize per line. Scales with the active font size so the box tracks the
/// user's size preference.
enum DragPill {
    static let text = "♪ Cantio ♪"

    static func size(activeFontSize fs: CGFloat) -> NSSize {
        NSSize(width: max(150, fs * 7.2), height: fs * 2.0 + 12)
    }
}

enum DragSnap {
    /// Distance (points) within which a proposed origin snaps to a guide.
    static let threshold: CGFloat = 8

    /// Gap (points) between the visible-frame bottom and the window's bottom
    /// edge for the default "toward the bottom" resting position.
    static let bottomInset: CGFloat = 120

    /// The factory resting origin: horizontally centered in the visible frame,
    /// anchored `bottomInset` above its bottom.
    static func defaultOrigin(in visibleFrame: NSRect, size: NSSize) -> NSPoint {
        NSPoint(x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + bottomInset)
    }

    /// Snap a proposed bottom-left origin toward the H-center guide (window
    /// center X → screen midX) and the default baseline guide (origin Y →
    /// `defaultOrigin.y`). Returns the resolved origin plus which axes snapped
    /// so the overlay can highlight the matching guide.
    static func snap(proposedOrigin: NSPoint,
                     windowSize: NSSize,
                     visibleFrame: NSRect,
                     defaultOrigin: NSPoint,
                     threshold: CGFloat = threshold) -> (origin: NSPoint, snapX: Bool, snapY: Bool) {
        var origin = proposedOrigin
        let centerX = proposedOrigin.x + windowSize.width / 2
        let snapX = abs(centerX - visibleFrame.midX) <= threshold
        if snapX { origin.x = visibleFrame.midX - windowSize.width / 2 }
        let snapY = abs(proposedOrigin.y - defaultOrigin.y) <= threshold
        if snapY { origin.y = defaultOrigin.y }
        return (origin, snapX, snapY)
    }
}
