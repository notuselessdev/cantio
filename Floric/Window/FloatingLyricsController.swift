import AppKit
import Combine
import SwiftUI

/// Owns the floating lyrics `NSWindow` and the SwiftUI hosting bridge.
///
/// Click-through policy (W4) is derived from `windowStyle`:
/// - `.pill` → always click-through (per-pixel alpha hit-test refines the silhouette;
///   Option-click on opaque pixels still flips the grab affordance for drag).
/// - `.minimal` → never click-through (real chrome window, must be interactive).
/// - `.fullscreen` → always click-through (overlay covers the screen edge-to-edge).
@MainActor
final class FloatingLyricsController {
    private let monitor: SpotifyMonitor
    private let lyrics: LyricsStore
    private let prefs: Preferences

    private var window: FloatingLyricsWindow?
    private var clickMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// W3: minimal style has its own autosave so resizes survive launches.
    /// Pill is a fixed-size capsule and must NOT inherit a stale resized frame.
    private static let pillAutosaveName = "FloricFloatingLyricsWindow"
    private static let minimalAutosaveName = "FloricFloatingLyricsWindow.minimal"

    /// Saved frame to restore when leaving fullscreen — never written to autosave.
    private var preFullscreenFrame: NSRect?
    /// True while the window is currently sized to fullscreen.
    private var isFullscreenActive = false
    /// Pill grab affordance: when user Option-clicks an opaque pixel we drop
    /// click-through briefly so they can drag the window.
    private var pillGrabActive = false

    /// Minimal content size constraints (W3) — keep lyric text readable.
    private static let minimalMinSize = NSSize(width: 320, height: 60)
    private static let minimalMaxSize = NSSize(width: 1600, height: 600)
    private static let minimalDefaultSize = NSSize(width: 520, height: 120)
    private static let pillDefaultSize = NSSize(width: 520, height: 80)

    init(monitor: SpotifyMonitor, lyrics: LyricsStore, prefs: Preferences) {
        self.monitor = monitor
        self.lyrics = lyrics
        self.prefs = prefs
    }

    /// Creates the window if needed and applies current preferences.
    func start() {
        if window == nil { buildWindow() }
        applyStyleGeometry(previous: nil)
        applyClickThrough()
        applyWindowChrome()
        applyVisibility(animated: false)
        installClickMonitor()
        installMousePassthroughMonitors()
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
        ))
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
            // Cocoa quirk: setFrameAutosaveName must be set BEFORE the first
            // setFrame so the saved origin is read from defaults. Clear any
            // prior autosave first to avoid a name collision warning.
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(Self.pillAutosaveName)
            window.contentMinSize = Self.pillDefaultSize
            window.contentMaxSize = Self.pillDefaultSize
            // Fixed-size capsule: clamp to canonical size; keep autosaved origin.
            var f = window.frame
            f.size = Self.pillDefaultSize
            if window.frame.origin == .zero { f.origin = Self.defaultOrigin(for: Self.pillDefaultSize) }
            window.setFrame(f, display: true)
            window.isMovable = true

        case .minimal:
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(Self.minimalAutosaveName)
            window.contentMinSize = Self.minimalMinSize
            window.contentMaxSize = Self.minimalMaxSize
            // If no autosave restored the frame yet, seed a sensible default.
            if window.frame.size.width < Self.minimalMinSize.width
                || window.frame.size.height < Self.minimalMinSize.height
                || window.frame.origin == .zero {
                let size = Self.minimalDefaultSize
                let origin = Self.defaultOrigin(for: size)
                window.setFrame(NSRect(origin: origin, size: size), display: true)
            }
            window.isMovable = true

        case .fullscreen:
            // Save the prior style's frame so we can restore on exit. Don't
            // save another fullscreen-sized frame on top.
            if !isFullscreenActive { preFullscreenFrame = window.frame }
            // Detach autosave: we don't want the screen-sized frame to clobber
            // the user's saved pill/minimal position.
            window.setFrameAutosaveName("")
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
        case .pill, .fullscreen: return true
        case .minimal:           return false
        }
    }

    private func applyClickThrough() {
        guard let window else { return }
        switch prefs.windowStyle {
        case .pill:
            // Per-pixel alpha hit-test breaks against `.glassEffect()` (Metal
            // compositor writes the glass blend after the bitmap snapshot, so
            // sampled pixels read transparent). Make the whole pill window
            // interactive — the borderless frame is sized to the visible
            // silhouette, so pixels outside the pill body don't exist to
            // intercept clicks.
            window.ignoresMouseEvents = false
        case .minimal:
            // W1: minimal is always interactive regardless of any other state.
            window.ignoresMouseEvents = false
        case .fullscreen:
            window.ignoresMouseEvents = true
        }
    }

    private func installClickMonitor() {
        if clickMonitor != nil { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            // Pill drag: NSHostingView consumes mouseDown before
            // `isMovableByWindowBackground` can fire, so any click on the
            // pill stays put. Trigger the drag programmatically — Cocoa
            // hands off to the standard window drag pipeline.
            if self.prefs.windowStyle == .pill {
                self.window?.performDrag(with: event)
                return nil
            }
            return event
        }
    }

    // MARK: - Pill click-through (transparent areas pass through)

    private func installMousePassthroughMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.updatePillPassthrough() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.updatePillPassthrough() }
            return event
        }
    }

    private func updatePillPassthrough() {
        guard let window, prefs.windowStyle == .pill else { return }
        // Option-click grab pinned: keep window fully interactive so the user
        // can drag from any pixel.
        if pillGrabActive {
            window.ignoresMouseEvents = false
            return
        }
        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else {
            window.ignoresMouseEvents = true
            return
        }
        window.ignoresMouseEvents = !isOpaqueAt(screenPoint: screenPoint)
    }

    private func isOpaqueAt(screenPoint: NSPoint) -> Bool {
        guard let window, let contentView = window.contentView else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = contentView.convert(windowPoint, from: nil)
        guard contentView.bounds.contains(viewPoint) else { return false }
        let rect = NSRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: rect) else { return false }
        contentView.cacheDisplay(in: rect, to: rep)
        guard let color = rep.colorAt(x: 0, y: 0) else { return false }
        return color.alphaComponent > 0.05
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
