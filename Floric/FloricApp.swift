import SwiftUI

@main
struct FloricApp: App {
    @StateObject private var monitor = SpotifyMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(monitor: monitor)
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var monitor: SpotifyMonitor

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
                    Text("\(np.state.rawValue.capitalized)")
                } else {
                    Text("Nothing playing")
                }
            }
        }
        Divider()
        Button("Quit Floric") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear { monitor.start() }
    }
}
