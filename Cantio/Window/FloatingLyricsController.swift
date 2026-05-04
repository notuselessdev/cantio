import AppKit
import Combine
import SwiftUI

/// Owns the floating lyrics `NSWindow` and the SwiftUI hosting bridge.
///
/// Click-through policy (W4) is derived from `windowStyle`:
/// - `.pill` → window is interactive; `installClickMonitor` distinguishes a
///   true click (mouseDown + mouseUp without movement past the drag
///   threshold) from a drag, so future tap targets inside the pill receive
///   the click while drags trigger `performDrag`. Option-click is the
///   pass-through escape hatch — events propagate to whatever is beneath.
/// - `.minimal` → never click-through (real chrome window, must be interactive).
/// - `.fullscreen` → interactive (Esc exits via global key monitor; future
///   in-overlay controls need to receive clicks).
@MainActor
final class FloatingLyricsController {
    private let monitor: SpotifyMonitor
    private let lyrics: LyricsStore
    private let prefs: Preferences
    private let hitTarget: PillHitTarget

    private var window: FloatingLyricsWindow?
    private var clickMonitor: Any?
    private var localMouseMovedMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var fullscreenEscMonitor: Any?
    /// Style remembered before entering fullscreen so Esc can restore it.
    private var preFullscreenStyle: WindowStyle?
    private var cancellables = Set<AnyCancellable>()

    /// Drag detection threshold (points) — movement below this on mouseDown
    /// is classified as a click, so embedded tap targets receive the event.
    private static let dragThresholdPoints: CGFloat = 4

    /// W3: minimal style has its own autosave so resizes survive launches.
    /// Pill is a fixed-size capsule and must NOT inherit a stale resized frame.
    private static let pillAutosaveName = "CantioFloatingLyricsWindow"
    private static let minimalAutosaveName = "CantioFloatingLyricsWindow.minimal"

    /// Saved frame to restore when leaving fullscreen — never written to autosave.
    private var preFullscreenFrame: NSRect?
    /// True while the window is currently sized to fullscreen.
    private var isFullscreenActive = false

    /// Minimal content size constraints (W3) — keep lyric text readable.
    private static let minimalMinSize = NSSize(width: 320, height: 60)
    private static let minimalMaxSize = NSSize(width: 1600, height: 600)
    private static let minimalDefaultSize = NSSize(width: 520, height: 120)
    private static let pillDefaultSize = NSSize(width: 520, height: 80)

    init(monitor: SpotifyMonitor, lyrics: LyricsStore, prefs: Preferences,
         hitTarget: PillHitTarget) {
        self.monitor = monitor
        self.lyrics = lyrics
        self.prefs = prefs
        self.hitTarget = hitTarget
    }

    /// Creates the window if needed and applies current preferences.
    func start() {
        if window == nil { buildWindow() }
        applyStyleGeometry(previous: nil)
        applyClickThrough()
        applyWindowChrome()
        applyVisibility(animated: false)
        installClickMonitor()
        installScreenChangeObserver()
        observePreferences()
        observePlayback()
        installGlobalHotKey()
    }

    /// Pill / fullscreen render their own silhouette (capsule shadow,
    /// full-bleed backdrop) — disable the rectangular NSWindow shadow so it
    /// doesn't halo the silhouette. Minimal keeps the chrome shadow.
    private func applyWindowChrome() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        switch prefs.windowStyle {
        case .pill, .fullscreen:
            window.hasShadow = false
        case .minimal:
            window.hasShadow = true
        }
        window.invalidateShadow()
    }

    func toggleVisibility() {
        prefs.windowVisible.toggle()
    }

    // MARK: - Build

    private func buildWindow() {
        // Initial frame is a placeholder; applyStyleGeometry installs the
        // real frame (and the autosave name) for the active style.
        let initialFrame = NSRect(origin: .zero, size: Self.pillDefaultSize)
        let window = FloatingLyricsWindow(contentRect: initialFrame)

        let host = NSHostingView(rootView: LyricsContentView(
            monitor: monitor,
            lyrics: lyrics,
            prefs: prefs
        ).environmentObject(hitTarget))
        host.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = host

        self.window = window
    }

    // MARK: - Style geometry (W2 + W3)

    /// Reflow window for the active style. `previous` lets us save/restore
    /// the prior style's frame around fullscreen / minimal transitions.
    private func applyStyleGeometry(previous: WindowStyle?) {
        guard let window else { return }

        // Leaving fullscreen: restore the saved frame and re-enable movement
        // before swapping autosave / setting style frames.
        if previous == .fullscreen, prefs.windowStyle != .fullscreen {
            isFullscreenActive = false
            window.isMovable = true
            if let saved = preFullscreenFrame {
                window.setFrame(saved, display: true)
            }
            preFullscreenFrame = nil
        }

        switch prefs.windowStyle {
        case .pill:
            // `setFrameAutosaveName` only enables autosave; it doesn't restore
            // immediately. Pair with `setFrameUsingName` so the user's last
            // origin loads on every reattach. The window's
            // `constrainFrameRect` keeps later drags inside the visible
            // frame, so we don't need to re-clamp here.
            window.clampToVisibleFrame = true
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(Self.pillAutosaveName)
            window.contentMinSize = Self.pillDefaultSize
            window.contentMaxSize = Self.pillDefaultSize
            let restored = window.setFrameUsingName(Self.pillAutosaveName)
            var f = window.frame
            f.size = Self.pillDefaultSize
            if !restored { f.origin = Self.defaultOrigin(for: Self.pillDefaultSize) }
            window.setFrame(f, display: true)
            window.isMovable = true

        case .minimal:
            window.clampToVisibleFrame = true
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(Self.minimalAutosaveName)
            window.contentMinSize = Self.minimalMinSize
            window.contentMaxSize = Self.minimalMaxSize
            let restored = window.setFrameUsingName(Self.minimalAutosaveName)
            var f = window.frame
            if !restored
                || f.size.width < Self.minimalMinSize.width
                || f.size.height < Self.minimalMinSize.height {
                f.size = Self.minimalDefaultSize
                f.origin = Self.defaultOrigin(for: Self.minimalDefaultSize)
            }
            window.setFrame(f, display: true)
            window.isMovable = true

        case .fullscreen:
            // Save the prior style's frame + style so we can restore on exit.
            // Don't save another fullscreen-sized frame on top.
            if !isFullscreenActive {
                preFullscreenFrame = window.frame
                preFullscreenStyle = previous
            }
            // Detach autosave: we don't want the screen-sized frame to clobber
            // the user's saved pill/minimal position. Allow off-screen frames
            // so fullscreen can occupy the menu bar / Dock area.
            window.setFrameAutosaveName("")
            window.clampToVisibleFrame = false
            window.contentMinSize = NSSize(width: 100, height: 100)
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                           height: CGFloat.greatestFiniteMagnitude)
            applyFullscreenFrame()
            window.isMovable = false
            isFullscreenActive = true
        }
    }

    /// W2: pick the screen the window currently lives on (fall back to .main),
    /// and use `screen.frame` (NOT visibleFrame) so the overlay covers the
    /// menubar + Dock for a true fullscreen feel.
    private func applyFullscreenFrame() {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let target = screen else { return }
        // W2: window level — `.statusBar` sits above `.floating` and above
        // native fullscreen Spaces, which `.floating` cannot guarantee.
        window.level = .statusBar
        window.setFrame(target.frame, display: true)
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height - 60
        return NSPoint(x: x, y: y)
    }

    // MARK: - Visibility

    private func applyVisibility(animated: Bool) {
        guard let window else { return }
        let shouldShow = computeShouldShow()
        if shouldShow {
            if !window.isVisible {
                window.orderFrontRegardless()
            }
        } else {
            if window.isVisible {
                window.orderOut(nil)
            }
        }
    }

    private func computeShouldShow() -> Bool {
        guard prefs.windowVisible else { return false }
        // Always keep the window visible when permission is denied so the
        // user can see the recovery instructions and "Open System Settings"
        // affordance — overriding `hideWhenPaused`.
        if monitor.availability == .permissionDenied { return true }
        guard prefs.hideWhenPaused else { return true }
        switch monitor.availability {
        case .available:
            return monitor.nowPlaying?.state == .playing
        case .notInstalled, .notRunning, .permissionDenied:
            return false
        }
    }

    // MARK: - Click-through (W4)

    /// Pure rule: does the active style accept clicks at all?
    /// Exposed for unit tests as a free function on the type.
    static func effectiveClickThrough(for style: WindowStyle) -> Bool {
        switch style {
        case .pill:       return true
        case .minimal:    return false
        case .fullscreen: return false
        }
    }

    private func applyClickThrough() {
        guard let window else { return }
        switch prefs.windowStyle {
        case .pill:
            // Shape-based hit-test: the 520x80 borderless frame contains a
            // capsule that hugs its content, leaving transparent margins.
            // Per-pixel alpha sampling can't probe `.glassEffect()` reliably
            // (Metal blend happens after the bitmap snapshot), so instead we
            // toggle `ignoresMouseEvents` on mouse move based on whether the
            // cursor sits inside the published capsule rect. Default to
            // pass-through until the first move event lands.
            window.ignoresMouseEvents = true
            installPillMouseMovedMonitors()
        case .minimal:
            // W1: minimal is always interactive regardless of any other state.
            window.ignoresMouseEvents = false
            removePillMouseMovedMonitors()
        case .fullscreen:
            // Fullscreen accepts clicks so the user can interact with the
            // overlay (and so Esc / future close affordance lives inside it).
            window.ignoresMouseEvents = false
            removePillMouseMovedMonitors()
        }
        installFullscreenEscMonitorIfNeeded()
    }

    private func installPillMouseMovedMonitors() {
        if localMouseMovedMonitor == nil {
            localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                Task { @MainActor in self?.updatePillIgnoresMouseEvents() }
                return event
            }
        }
        if globalMouseMovedMonitor == nil {
            globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                Task { @MainActor in self?.updatePillIgnoresMouseEvents() }
            }
        }
    }

    private func removePillMouseMovedMonitors() {
        if let m = localMouseMovedMonitor { NSEvent.removeMonitor(m); localMouseMovedMonitor = nil }
        if let m = globalMouseMovedMonitor { NSEvent.removeMonitor(m); globalMouseMovedMonitor = nil }
    }

    private func updatePillIgnoresMouseEvents() {
        guard let window, prefs.windowStyle == .pill else { return }
        let mouse = NSEvent.mouseLocation
        let inside = Self.pointInsideCapsuleRect(
            mouseScreen: mouse,
            capsuleInContentView: hitTarget.capsuleRectInContentView,
            windowFrame: window.frame
        )
        let shouldIgnore = !inside
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
    }

    /// Pure helper: is the screen-space mouse point inside the capsule's
    /// SwiftUI rect (top-left origin, content-view space)? Converts the
    /// SwiftUI rect into AppKit screen coords by Y-flipping against the
    /// window's height, then offsetting by the window's bottom-left origin.
    /// Exposed for unit tests — no `NSWindow` required.
    static func pointInsideCapsuleRect(mouseScreen: NSPoint,
                                       capsuleInContentView: CGRect,
                                       windowFrame: NSRect) -> Bool {
        guard capsuleInContentView != .zero else { return false }
        let h = windowFrame.height
        let screenMinX = windowFrame.minX + capsuleInContentView.minX
        let screenMinY = windowFrame.minY + (h - capsuleInContentView.maxY)
        let screenRect = NSRect(x: screenMinX, y: screenMinY,
                                width: capsuleInContentView.width,
                                height: capsuleInContentView.height)
        return screenRect.contains(mouseScreen)
    }

    /// Esc key exits fullscreen — without this the user has no way out
    /// (window is click-through + has no chrome).
    private func installFullscreenEscMonitorIfNeeded() {
        let inFullscreen = prefs.windowStyle == .fullscreen
        if inFullscreen {
            // Make the window key so SwiftUI's responder chain (and our local
            // monitor) actually receive keyDown. addGlobalMonitorForEvents
            // would need Accessibility permission to observe Esc cross-app.
            window?.makeKeyAndOrderFront(nil)
            if fullscreenEscMonitor != nil { return }
            fullscreenEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard event.keyCode == 53 else { return event } // 53 = Escape
                Task { @MainActor in self?.exitFullscreen() }
                return nil
            }
        } else if let m = fullscreenEscMonitor {
            NSEvent.removeMonitor(m)
            fullscreenEscMonitor = nil
        }
    }

    func exitFullscreen() {
        let restore = preFullscreenStyle ?? .pill
        prefs.windowStyle = restore
    }

    private func installClickMonitor() {
        if clickMonitor != nil { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            guard self.prefs.windowStyle == .pill else { return event }

            // Option-click escape hatch: do not drag, do not consume —
            // pass through so power users can interact with whatever is
            // beneath the pill.
            if event.modifierFlags.contains(.option) { return event }

            // Click-vs-drag: peek the upcoming event stream. If the user
            // releases without moving past the threshold, this is a click —
            // let it propagate so embedded tap targets fire. Otherwise
            // hand off to Cocoa's window drag.
            let threshold = Self.dragThresholdPoints
            let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
            while let next = NSApp.nextEvent(matching: mask,
                                             until: .distantFuture,
                                             inMode: .eventTracking,
                                             dequeue: true) {
                if next.type == .leftMouseUp {
                    // True click — re-dispatch the original mouseDown +
                    // mouseUp so embedded tap targets receive the full
                    // sequence. sendEvent bypasses the local event monitor
                    // pipeline, so this does not re-enter the loop.
                    self.window?.sendEvent(event)
                    self.window?.sendEvent(next)
                    return nil
                }
                if Self.shouldStartDrag(beginEvent: event, currentEvent: next,
                                        thresholdPoints: threshold) {
                    self.window?.performDrag(with: event)
                    return nil
                }
            }
            return nil
        }
    }

    /// Pure helper: classify a mouseDown follow-up event as drag-worthy.
    /// Exposed for unit tests — no `NSWindow` required.
    static func shouldStartDrag(beginEvent: NSEvent,
                                currentEvent: NSEvent,
                                thresholdPoints: CGFloat) -> Bool {
        let dx = currentEvent.locationInWindow.x - beginEvent.locationInWindow.x
        let dy = currentEvent.locationInWindow.y - beginEvent.locationInWindow.y
        return (dx * dx + dy * dy) >= (thresholdPoints * thresholdPoints)
    }

    // MARK: - Screen reflow (W2)

    private func installScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isFullscreenActive else { return }
                self.applyFullscreenFrame()
            }
        }
    }

    // MARK: - Observation

    private func observePreferences() {
        prefs.$windowVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)

        prefs.$hideWhenPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)

        prefs.$windowStyle
            .scan((WindowStyle?.none, prefs.windowStyle)) { acc, next in
                (acc.1, next)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] pair in
                guard let self else { return }
                self.applyStyleGeometry(previous: pair.0)
                self.applyWindowChrome()
                self.applyClickThrough()
            }
            .store(in: &cancellables)

        prefs.$backgroundStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWindowChrome() }
            .store(in: &cancellables)
    }

    // MARK: - Global hotkey

    private func installGlobalHotKey() {
        HotKeyManager.shared.onPress = { [weak self] in
            self?.toggleVisibility()
        }
        HotKeyManager.shared.register(prefs.toggleHotKey)

        prefs.$toggleHotKey
            .receive(on: RunLoop.main)
            .sink { hk in
                HotKeyManager.shared.register(hk)
            }
            .store(in: &cancellables)
    }

    private func observePlayback() {
        monitor.$availability
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)

        monitor.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)
    }
}
