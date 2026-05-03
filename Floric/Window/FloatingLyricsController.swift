import AppKit
import Combine
import SwiftUI

/// Owns the floating lyrics `NSWindow` and the SwiftUI hosting bridge.
///
/// Responsibilities:
/// - Create and lazily show the window
/// - Persist frame across launches (via `setFrameAutosaveName`)
/// - Position near top-center of the primary display on first launch
/// - Apply click-through (`ignoresMouseEvents`) from `Preferences`
/// - Toggle click-through with Option-click via a local mouse-event monitor
/// - Auto-hide when Spotify is not playing (when preference enabled)
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

    private static let frameAutosaveName = "FloricFloatingLyricsWindow"

    init(monitor: SpotifyMonitor, lyrics: LyricsStore, prefs: Preferences) {
        self.monitor = monitor
        self.lyrics = lyrics
        self.prefs = prefs
    }

    /// Creates the window if needed and applies current preferences.
    func start() {
        if window == nil { buildWindow() }
        applyClickThrough()
        applyWindowChrome()
        applyVisibility(animated: false)
        installClickMonitor()
        installMousePassthroughMonitors()
        observePreferences()
        observePlayback()
        installGlobalHotKey()
    }

    /// Pill / pillStack / fullscreen presets render their own silhouette
    /// (capsule shadow, full-bleed backdrop) and the rectangular NSWindow
    /// shadow ends up framing them with a dark halo. Disable the window
    /// shadow for those presets; keep it for chrome-bearing presets.
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
        let initialFrame = Self.defaultFrame()
        let window = FloatingLyricsWindow(contentRect: initialFrame)

        let host = NSHostingView(rootView: LyricsContentView(
            monitor: monitor,
            lyrics: lyrics,
            prefs: prefs
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = host

        // Persist position/size across launches. If no autosave exists yet
        // the initial frame above is used.
        window.setFrameAutosaveName(Self.frameAutosaveName)

        self.window = window
    }

    /// Default frame: ~520x80 near the top-center of the main display.
    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 520
        let height: CGFloat = 80
        let x = screen.midX - width / 2
        // 60pt below the top of the visible area.
        let y = screen.maxY - height - 60
        return NSRect(x: x, y: y, width: width, height: height)
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
        // Hide when Spotify is unavailable or not playing.
        switch monitor.availability {
        case .available:
            return monitor.nowPlaying?.state == .playing
        case .notInstalled, .notRunning, .permissionDenied:
            return false
        }
    }

    // MARK: - Click-through

    private func applyClickThrough() {
        guard let window else { return }
        if prefs.windowStyle == .pill {
            updatePillPassthrough()
        } else {
            window.ignoresMouseEvents = prefs.clickThrough
        }
    }

    private func installClickMonitor() {
        if clickMonitor != nil { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            if event.modifierFlags.contains(.option) {
                Task { @MainActor in
                    self.prefs.clickThrough.toggle()
                }
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
        if prefs.clickThrough {
            window.ignoresMouseEvents = true
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

    // MARK: - Observation

    private func observePreferences() {
        prefs.$clickThrough
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyClickThrough() }
            .store(in: &cancellables)

        prefs.$windowVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)

        prefs.$hideWhenPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility(animated: true) }
            .store(in: &cancellables)

        prefs.$windowStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWindowChrome() }
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
