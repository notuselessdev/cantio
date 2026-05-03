import AppKit

/// Borderless, floating, draggable-from-anywhere window used for lyrics.
///
/// - `.floating` window level keeps it above ordinary app windows.
/// - `canJoinAllSpaces` makes it follow the user across spaces and into
///   full-screen apps (auxiliary).
/// - Drag-from-background is enabled so the user can grab the window from
///   any non-interactive part of its surface.
final class FloatingLyricsWindow: NSWindow {
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
}
