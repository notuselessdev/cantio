import AppKit

/// Borderless, floating, draggable-from-anywhere window used for lyrics.
///
/// - `.floating` window level keeps it above ordinary app windows.
/// - `canJoinAllSpaces` makes it follow the user across spaces and into
///   full-screen apps (auxiliary).
/// - Drag-from-background is enabled so the user can grab the window from
///   any non-interactive part of its surface.
final class FloatingLyricsWindow: NSWindow {
    /// When true (default), `constrainFrameRect` keeps the window inside the
    /// active screen's visible frame — covers user drags + system frame
    /// changes. Controllers flip this off for fullscreen so the window can
    /// occupy the full screen.frame (menu bar + Dock area).
    var clampToVisibleFrame: Bool = true

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Hide standard window buttons even though styleMask is borderless.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        // Don't steal focus from frontmost app when shown.
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    // Borderless windows return false by default; we want to be able to
    // become the key window so option-click toggling works.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard clampToVisibleFrame else {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        let target = screen ?? self.screen ?? NSScreen.main
        guard let visible = target?.visibleFrame else {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        var f = frameRect
        f.size.width = min(f.size.width, visible.width)
        f.size.height = min(f.size.height, visible.height)
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.size.width }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.size.height }
        if f.minX < visible.minX { f.origin.x = visible.minX }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        return f
    }
}
