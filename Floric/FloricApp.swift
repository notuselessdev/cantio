import SwiftUI

@main
struct FloricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        // Menu-bar UI is owned by `AppDelegate.statusBar` (NSStatusItem +
        // borderless NSPanel). SwiftUI's `MenuBarExtra(.window)` installs an
        // opaque MenuBarExtraWindow whose hosting chain defeats `.glassEffect()`
        // on macOS 26 — Liquid Glass needs a real transparent NSWindow to blur
        // the desktop behind it. Settings stays a SwiftUI Scene so SettingsLink
        // keeps working.
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
    private var didBootstrap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapIfNeeded()
        installStatusBar()
    }

    private func installStatusBar() {
        let bar = StatusBarPopover {
            StatusItemLabel(monitor: self.monitor)
        }
        bar.setContent { [unowned self] in
            MenuBarPanel(
                monitor: self.monitor,
                lyrics: self.lyrics,
                prefs: self.prefs,
                onAppear: {}
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

/// Status-bar label: waveform glyph + "Artist · Title" truncated when
/// available. Artist leads so multi-artist credits stay visible even when
/// the title gets clipped.
struct StatusItemLabel: View {
    @ObservedObject var monitor: SpotifyMonitor
    private static let maxTotalLength = 36

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note")
            if let label = displayText {
                Text(label)
            }
        }
    }

    private var displayText: String? {
        guard let np = monitor.nowPlaying, !np.title.isEmpty else { return nil }
        let artist = np.artist.trimmingCharacters(in: .whitespaces)
        let combined = artist.isEmpty
            ? np.title
            : "\(artist) · \(np.title)"
        if combined.count > Self.maxTotalLength {
            return String(combined.prefix(Self.maxTotalLength)) + "…"
        }
        return combined
    }
}
