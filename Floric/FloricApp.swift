import SwiftUI

@main
struct FloricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(
                monitor: appDelegate.monitor,
                lyrics: appDelegate.lyrics,
                prefs: prefs,
                onAppear: { appDelegate.bootstrapIfNeeded() }
            )
        } label: {
            StatusItemLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)

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
    private var floatingController: FloatingLyricsController?
    private var didBootstrap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapIfNeeded()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        monitor.start()
        lyrics.bind(to: monitor)
        let controller = FloatingLyricsController(
            monitor: monitor,
            lyrics: lyrics,
            prefs: prefs
        )
        controller.start()
        floatingController = controller
    }
}

/// Status-bar label: waveform glyph + truncated track title when available.
private struct StatusItemLabel: View {
    @ObservedObject var monitor: SpotifyMonitor
    private static let maxTitleLength = 28

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note")
            if let title = displayTitle {
                Text(title)
            }
        }
    }

    private var displayTitle: String? {
        guard let np = monitor.nowPlaying, !np.title.isEmpty else { return nil }
        if np.title.count > Self.maxTitleLength {
            return String(np.title.prefix(Self.maxTitleLength)) + "…"
        }
        return np.title
    }
}
