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
            StatusItemLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(prefs: prefs)
        }
    }
}

/// Status-bar label: music glyph + truncated track title when available.
private struct StatusItemLabel: View {
    @ObservedObject var monitor: SpotifyMonitor
    private static let maxTitleLength = 28

    var body: some View {
        if let title = displayTitle {
            Label(title, systemImage: "music.note")
        } else {
            Image(systemName: "music.note")
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

private struct MenuBarContent: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var prefs: Preferences
    let onAppear: () -> Void

    var body: some View {
        Toggle(prefs.windowVisible ? "Hide Lyrics" : "Show Lyrics", isOn: $prefs.windowVisible)
            .keyboardShortcut("l", modifiers: [.command, .option])
        Divider()
        PreferencesMenu(prefs: prefs)
        Divider()
        Button("Preferences…") {
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Floric") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear(perform: onAppear)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
