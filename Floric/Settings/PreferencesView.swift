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
///
/// SwiftUI `Settings` scene with tabbed sections: General, Appearance,
/// Lyrics, Shortcuts. Each tab is a grouped `Form` so it adopts the standard
/// macOS preferences look-and-feel.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceTab(prefs: prefs)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            LyricsTab(prefs: prefs)
                .tabItem { Label("Lyrics", systemImage: "text.alignleft") }

            ShortcutsTab(prefs: prefs)
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
            Section("Behavior") {
                Toggle("Hide when paused", isOn: $prefs.hideWhenPaused)
                Toggle("Click-through", isOn: $prefs.clickThrough)
                Toggle("Show floating lyrics", isOn: $prefs.windowVisible)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Window") {
                Picker("Appearance", selection: $prefs.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Typography") {
                FontSizeSlider(fontSize: $prefs.fontSize)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LyricsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Display") {
                Picker("Layout", selection: $prefs.displayMode) {
                    ForEach(LyricsDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Global Hotkey") {
                LabeledContent("Toggle lyrics window") {
                    HotKeyRecorder(hotKey: $prefs.toggleHotKey)
                        .frame(width: 180)
                }
                Button("Reset to ⌥⌘L") {
                    prefs.toggleHotKey = .defaultToggle
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Discrete 4-step font size slider. The underlying `Slider` uses Doubles, so
/// we bridge to the `FontSize` enum via raw values and snap on every change.
private struct FontSizeSlider: View {
    @Binding var fontSize: FontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Font size")
                Spacer()
                Text(fontSize.label)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Slider(
                value: Binding(
                    get: { Double(fontSize.rawValue) },
                    set: { fontSize = FontSize(rawValue: Int($0.rounded())) ?? .medium }
                ),
                in: Double(FontSize.small.rawValue)...Double(FontSize.xlarge.rawValue),
                step: 1
            ) {
                Text("Font size")
            } minimumValueLabel: {
                Text("A").font(.system(size: 10))
            } maximumValueLabel: {
                Text("A").font(.system(size: 18))
            }
        }
    }
}
