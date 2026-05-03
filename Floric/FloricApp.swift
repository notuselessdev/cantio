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
    let pillHitTarget = PillHitTarget()
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
private struct StatusItemLabel: View {
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
