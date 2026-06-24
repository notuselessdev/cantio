import SwiftUI

@main
struct CantioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        Settings {
            SettingsView(prefs: prefs)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SpotifyMonitor()
    let lyrics = LyricsStore()
    let prefs = Preferences.shared
    let pillHitTarget = PillHitTarget()
    private var floatingController: FloatingLyricsController?
    private var statusBar: StatusBarPopover?
    private var onboarding: OnboardingController?
    private var didBootstrap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusBar()
        bootstrapIfNeeded()
        presentOnboardingIfNeeded()
    }

    private func presentOnboardingIfNeeded() {
        // While the assistant is up, the Spotify consent prompt must come only
        // from its dedicated step — hold off the polling loop's lazy prompt so
        // it can't pop standalone over the splash. Re-enable on completion.
        guard !prefs.didCompleteOnboarding else { return }
        monitor.allowsPermissionPrompt = false
        let controller = OnboardingController(prefs: prefs) { [weak self] in
            self?.monitor.allowsPermissionPrompt = true
        }
        onboarding = controller
        controller.presentIfNeeded()
    }

    private func installStatusBar() {
        let bar = StatusBarPopover(monitor: monitor)
        bar.setContent { [unowned self, unowned bar] in
            MenuBarPanel(
                monitor: self.monitor,
                lyrics: self.lyrics,
                prefs: self.prefs,
                onAppear: {},
                onDismiss: { bar.dismiss() },
                onRecenter: { [unowned self] in self.floatingController?.recenter() }
            )
        }
        statusBar = bar
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        monitor.start()
        lyrics.bind(to: monitor)
        let controller = FloatingLyricsController(
            monitor: monitor,
            lyrics: lyrics,
            prefs: prefs,
            hitTarget: pillHitTarget
        )
        controller.start()
        floatingController = controller
    }
}
