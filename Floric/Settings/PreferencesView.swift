import SwiftUI

/// Quick toggles inside the menu-bar dropdown. Renders as `NSMenuItem` rows
/// because `MenuBarExtra` uses `.menu` style.
struct PreferencesMenu: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Menu("Appearance") {
            Picker("Appearance", selection: $prefs.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// Full Preferences window opened via the "Preferences…" menu item.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Floating Window") {
                Picker("Display", selection: $prefs.displayMode) {
                    ForEach(LyricsDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Appearance", selection: $prefs.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("Click-through", isOn: $prefs.clickThrough)
                Toggle("Hide when paused", isOn: $prefs.hideWhenPaused)
                Toggle("Show floating lyrics", isOn: $prefs.windowVisible)
            }

            Section("Global Hotkey") {
                LabeledContent("Toggle lyrics window") {
                    HotKeyRecorder(hotKey: $prefs.toggleHotKey)
                        .frame(width: 160)
                }
                Button("Reset to ⌥⌘L") {
                    prefs.toggleHotKey = .defaultToggle
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}
