import SwiftUI

@main
struct FloricApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Text("Floric — Floating Lyrics")
        Divider()
        Button("Quit Floric") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
