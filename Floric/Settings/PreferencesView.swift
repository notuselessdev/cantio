import SwiftUI

/// Preferences UI surfaced in the menu bar. Designed for the SwiftUI
/// `MenuBarExtra` `.menu` style — uses `Picker` and `Toggle` which render as
/// proper `NSMenuItem` rows.
struct PreferencesMenu: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Picker("Display", selection: $prefs.displayMode) {
            ForEach(LyricsDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        Toggle("Click-through", isOn: $prefs.clickThrough)
        Toggle("Hide when paused", isOn: $prefs.hideWhenPaused)
        Toggle("Show floating lyrics", isOn: $prefs.windowVisible)
    }
}
