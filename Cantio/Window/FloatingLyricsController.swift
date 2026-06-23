import AppKit
import Combine
import SwiftUI

/// Owns the floating lyrics `NSWindow` and the SwiftUI hosting bridge.
///
/// Click-through policy (W4) is derived from `windowStyle`:
/// - `.floating` → window is interactive; `installClickMonitor` distinguishes a
///   true click (mouseDown + mouseUp without movement past the drag
///   threshold) from a drag, so future tap targets inside the pill receive
///   the click while drags trigger `performDrag`. Option-click is the
///   pass-through escape hatch — events propagate to whatever is beneath.
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

    /// Raycast-style alignment guides, shown only while dragging.
    private let guideOverlay = DragGuideOverlay()

    /// Drag detection threshold (points) — movement below this on mouseDown
    /// is classified as a click, so embedded tap targets receive the event.
    private static let dragThresholdPoints: CGFloat = 4

    /// Pill is a fixed-size capsule; autosave persists its origin only.
    private static let pillAutosaveName = "CantioFloatingLyricsWindow"

    /// True while the window is currently sized to fullscreen.
    private var isFullscreenActive = false

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
    /// doesn't halo the silhouette.
    private func applyWindowChrome() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
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

        let leavingFullscreen = previous == .fullscreen && prefs.windowStyle != .fullscreen
        if leavingFullscreen {
            isFullscreenActive = false
            window.isMovable = true
            window.level = .floating // fullscreen raised it to .statusBar
        }

        switch prefs.windowStyle {
        case .floating:
            // The user's last pill position lives in the durable autosave store
            // (written on every drag, and on fullscreen-enter below). Reload it
            // verbatim on every reattach. `setFrameAutosaveName` only enables
            // autosave; pair it with `setFrameUsingName` to actually restore.
            window.level = .floating
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(Self.pillAutosaveName)
            window.contentMinSize = Self.pillDefaultSize
            window.contentMaxSize = Self.pillDefaultSize
            // Disable clamping while we place the frame so a position near a
            // screen edge is honored exactly — otherwise constrainFrameRect
            // nudges the restored pill inward (up/left of where it was).
            window.clampToVisibleFrame = false
            let restored = window.setFrameUsingName(Self.pillAutosaveName)
            var f = window.frame
            f.size = Self.pillDefaultSize
            if !restored { f.origin = Self.defaultOrigin(for: Self.pillDefaultSize, on: window.screen) }
            window.setFrame(f, display: true)
            window.clampToVisibleFrame = true
            window.isMovable = true

        case .fullscreen:
            if !isFullscreenActive {
                // Persist the live pill position so the floating branch can
                // reload it on exit. Skip at launch (previous == nil): the
                // window still holds the placeholder frame, which would clobber
                // the real position saved by the prior session.
                if previous == .floating { persistFrame() }
                preFullscreenStyle = previous
            }
            // Detach autosave: we don't want the screen-sized frame to clobber
            // the user's saved pill position. Allow off-screen frames so
            // fullscreen can occupy the menu bar / Dock area.
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

    private static func defaultOrigin(for size: NSSize, on screen: NSScreen? = nil) -> NSPoint {
        let vf = (screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return DragSnap.defaultOrigin(in: vf, size: size)
    }

    /// Reset the pill to its factory resting position: horizontally centered,
    /// anchored toward the bottom of the screen it currently lives on.
    func recenter() {
        guard let window, prefs.windowStyle == .floating else { return }
        // Use the exact inputs the drag snap uses — live window size + the
        // window's own screen visibleFrame — so the landing point is the same
        // origin the guide rulers center on (no constant-vs-actual drift).
        let size = window.frame.size
        let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = DragSnap.defaultOrigin(in: visible, size: size)
        // Keep the live size (no resize → no center shift); animate via
        // setFrame, the only frame setter the NSWindow animator drives
        // (animator().setFrameOrigin is a silent no-op).
        let frame = NSRect(origin: target, size: size)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        }
        persistFrame()
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
        case .floating:   return true
        case .fullscreen: return false
        }
    }

    private func applyClickThrough() {
        guard let window else { return }
        switch prefs.windowStyle {
        case .floating:
            // Shape-based hit-test: the 520x80 borderless frame contains a
            // capsule that hugs its content, leaving transparent margins.
            // Per-pixel alpha sampling can't probe `.glassEffect()` reliably
            // (Metal blend happens after the bitmap snapshot), so instead we
            // toggle `ignoresMouseEvents` on mouse move based on whether the
            // cursor sits inside the published capsule rect. Default to
            // pass-through until the first move event lands.
            window.ignoresMouseEvents = true
            installPillMouseMovedMonitors()
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
        guard let window, prefs.windowStyle == .floating else { return }
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
            // Activate the app first — when toggled from the menu the panel
            // holds key focus and the app may be inactive, so makeKey alone
            // won't stick and Esc wouldn't fire until the user clicks in.
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            // The menu-bar panel dismiss races this and can steal key focus back
            // a tick later, leaving Esc dead until the user clicks in. Re-assert
            // key + first responder across the next few runloop ticks so the
            // window reliably owns keyDown by the time the dust settles.
            for delay in [0.05, 0.15, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let window = self?.window, self?.prefs.windowStyle == .fullscreen else { return }
                    if !window.isKeyWindow {
                        NSApp.activate(ignoringOtherApps: true)
                        window.makeKeyAndOrderFront(nil)
                    }
                    window.makeFirstResponder(window.contentView)
                }
            }
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
        let restore = preFullscreenStyle ?? .floating
        prefs.windowStyle = restore
    }

    private func installClickMonitor() {
        if clickMonitor != nil { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            guard self.prefs.windowStyle == .floating else { return event }

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
                    self.beginMonitorDrag()
                    return nil
                }
            }
            return nil
        }
    }

    /// Per-drag state captured at mouse-down. Held while the monitor-driven
    /// drag is live so each move event can snap + redraw without recomputing.
    private struct DragSession {
        let grab: CGPoint
        let visible: NSRect
        let defOrigin: NSPoint
        let windowSize: NSSize
        let screen: NSScreen
        let tint: Color
    }
    private var dragSession: DragSession?
    private var dragMonitors: [Any] = []

    /// Start a non-blocking drag. We intentionally do NOT spin a synchronous
    /// `nextEvent` loop — that monopolizes the main run loop, so SwiftUI never
    /// swaps in the `isDragging` placeholder and the capsule frame reporter
    /// stays frozen on the previous lyric, making the guide slot jump per
    /// line. Local event monitors let the run loop breathe between moves.
    private func beginMonitorDrag() {
        guard let window,
              let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let size = window.frame.size
        let visible = screen.visibleFrame
        let tone: FL.Tone = window.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        // Grab the window by its center, not the cursor's offset within the
        // (520pt-wide) frame. The drag swaps the live capsule for the small
        // centered placeholder; preserving the original offset would leave
        // the placeholder far from the cursor when you grabbed a wide lyric's
        // edge. Centering keeps the placeholder under the pointer.
        dragSession = DragSession(
            grab: CGPoint(x: size.width / 2, y: size.height / 2),
            visible: visible,
            defOrigin: DragSnap.defaultOrigin(in: visible, size: size),
            windowSize: size,
            screen: screen,
            tint: FL.palette(tone: tone, hue: prefs.accentHue).accent)

        hitTarget.isDragging = true

        let dragged = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] ev in
            self?.updateDrag(); return ev
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            self?.endMonitorDrag(); return ev
        }
        dragMonitors = [dragged, up].compactMap { $0 }
        // Snap the placeholder under the cursor immediately, before the first
        // drag event lands.
        updateDrag()
    }

    private func updateDrag() {
        guard let window, let s = dragSession else { return }
        let mouse = NSEvent.mouseLocation
        let proposed = NSPoint(x: mouse.x - s.grab.x, y: mouse.y - s.grab.y)
        let snapped = DragSnap.snap(proposedOrigin: proposed, windowSize: s.windowSize,
                                    visibleFrame: s.visible, defaultOrigin: s.defOrigin)
        window.setFrameOrigin(snapped.origin)
        // Fixed-size slot, centered on the window's default center — identical
        // to where Re-center parks the pill, and never lyric-dependent.
        let slot = Self.slotRect(defaultOrigin: s.defOrigin, windowSize: s.windowSize,
                                 slotSize: DragPill.size(activeFontSize: prefs.fontSize.activeSize))
        guideOverlay.update(screen: s.screen, slot: slot,
                            snapX: snapped.snapX, snapY: snapped.snapY, tint: s.tint)
    }

    private func endMonitorDrag() {
        for m in dragMonitors { NSEvent.removeMonitor(m) }
        dragMonitors = []
        dragSession = nil
        hitTarget.isDragging = false
        guideOverlay.hide()
        persistFrame()
    }

    /// Persist the pill's frame durably. `saveFrame` writes to UserDefaults,
    /// but a SIGTERM (e.g. `killall` during dev rebuilds) kills the process
    /// before cfprefsd's lazy flush — so force a synchronize to survive an
    /// abrupt exit.
    private func persistFrame() {
        guard let window else { return }
        window.saveFrame(usingName: Self.pillAutosaveName)
        UserDefaults.standard.synchronize()
    }

    /// Pure helper: the default parking-slot rect in AppKit screen coords —
    /// a fixed `slotSize` centered on the window's default center. The pill
    /// capsule is itself centered in the (fixed) window, so the slot lands
    /// exactly where the pill sits when parked. No measurement involved, so
    /// the rulers never resize with the playing lyric.
    /// Exposed for unit tests — no `NSWindow` required.
    static func slotRect(defaultOrigin: NSPoint, windowSize: NSSize,
                         slotSize: NSSize) -> NSRect {
        let centerX = defaultOrigin.x + windowSize.width / 2
        let centerY = defaultOrigin.y + windowSize.height / 2
        return NSRect(x: centerX - slotSize.width / 2,
                      y: centerY - slotSize.height / 2,
                      width: slotSize.width, height: slotSize.height)
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
