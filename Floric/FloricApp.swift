import SwiftUI

@main
struct FloricApp: App {
    @StateObject private var monitor = SpotifyMonitor()
    @StateObject private var lyrics = LyricsStore()
    @StateObject private var prefs = Preferences.shared
    @State private var floatingController: FloatingLyricsController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                monitor: monitor,
                lyrics: lyrics,
                prefs: prefs,
                onAppear: {
                    monitor.start()
                    lyrics.bind(to: monitor)
                    if floatingController == nil {
                        let controller = FloatingLyricsController(
                            monitor: monitor,
                            lyrics: lyrics,
                            prefs: prefs
                        )
                        controller.start()
                        floatingController = controller
                    }
                }
            )
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences
    let onAppear: () -> Void

    var body: some View {
        Group {
            switch monitor.availability {
            case .notInstalled:
                Text("Spotify not installed")
            case .notRunning:
                Text("Spotify not running")
            case .available:
                if let np = monitor.nowPlaying {
                    Text("\(np.title) — \(np.artist)")
                    Text(np.state.rawValue.capitalized)
                    Text(lyricsLabel(lyrics.state))
                } else {
                    Text("Nothing playing")
                }
            }
        }
        Divider()
        PreferencesMenu(prefs: prefs)
        Divider()
        Button("Quit Floric") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear(perform: onAppear)
    }

    private func lyricsLabel(_ state: LyricsState) -> String {
        switch state {
        case .idle: return "Lyrics: —"
        case .loading: return "Loading lyrics…"
        case .synced(let lines): return "Synced lyrics (\(lines.count) lines)"
        case .plain: return "Plain lyrics"
        case .notFound: return "No lyrics found"
        case .error(let msg): return "Lyrics error: \(msg)"
        }
    }
}
