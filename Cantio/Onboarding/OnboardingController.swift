import AppKit
import SwiftUI

/// Presents the first-run onboarding assistant in its own window and records
/// completion so it never shows again.
///
/// Mirrors the Settings activation dance (`SettingsActivator`): a menu-bar
/// (`.accessory`) app can't front a window until it flips to `.regular`, and
/// the flip commits a runloop tick later — so activation is deferred. Closing
/// the window (button or programmatic finish) finalizes via the delegate, so
/// both paths converge on one place.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let prefs: Preferences
    private let chime = OnboardingChime()
    private var splashWindow: NSWindow?
    private var window: NSWindow?
    private var finishing = false
    private var transitioned = false

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
    }

    func presentIfNeeded() {
        guard !prefs.didCompleteOnboarding, window == nil, splashWindow == nil else { return }
        presentSplash()
    }

    // MARK: - Splash

    /// Full-screen welcome flourish shown before the setup steps.
    private func presentSplash() {
        let screen = NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let content = OnboardingSplashView(
            accentHue: prefs.accentHue,
            playChime: { [weak self] in self?.chime.play() },
            onContinue: { [weak self] in self?.transitionToSteps() }
        )
        let hosting = NSHostingView(rootView: content)
        // Clear backing so the SwiftUI `VisualEffectBackground` blurs the
        // desktop behind the splash instead of an opaque window fill.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let splash = KeyableBorderlessWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        splash.isReleasedWhenClosed = false
        splash.level = .floating
        splash.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        splash.isOpaque = false
        splash.backgroundColor = .clear
        splash.hasShadow = false
        splash.contentView = hosting
        splash.setFrame(frame, display: true)
        self.splashWindow = splash

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            splash.makeKeyAndOrderFront(nil)
        }
    }

    /// Fade the splash out and open the setup steps. Guarded so the auto-advance
    /// timer and an early tap/Esc can't both fire it.
    private func transitionToSteps() {
        guard !transitioned else { return }
        transitioned = true
        guard let splash = splashWindow else { present(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            splash.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            splash.orderOut(nil)
            self?.splashWindow = nil
            self?.present()
        })
    }

    // MARK: - Steps

    private func present() {
        let content = OnboardingView(
            prefs: prefs,
            onFinish: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: content)
        // The window paints a clear background so the SwiftUI
        // `VisualEffectBackground` is the visible surface — clear the host
        // layer too so no opaque backing hides the material.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = hosting
        window.delegate = self
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }

    /// Programmatic finish (Done button). Routes through `close()` so the
    /// delegate is the single finalize site.
    private func dismiss() {
        guard let window, !finishing else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !finishing else { return }
        finishing = true
        prefs.didCompleteOnboarding = true
        window?.delegate = nil
        window = nil
        // Drop back to menu-bar-only unless a Settings window is up.
        SettingsActivator.demoteIfNoSettingsWindow()
    }
}

/// Borderless windows can't become key by default, which would swallow the
/// splash's Return/Esc skip. Override so the keyboard shortcuts land.
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
