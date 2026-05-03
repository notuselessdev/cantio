import SwiftUI
import AppKit

/// Quick toggles inside the menu-bar dropdown — kept for the legacy menu
/// style. The new `.window` MenuBarExtra renders `MenuBarPanel` instead.
struct PreferencesMenu: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Menu("Appearance") {
            Picker("Window style", selection: $prefs.windowStyle) {
                ForEach(WindowStyle.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.inline)
            Picker("Theme", selection: $prefs.tone) {
                ForEach(Tone.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.inline)
        }
    }
}

/// Cantio Settings — single-pane, no tabs. Mirrors the layout from
/// `preferences.jsx`: hero header + grouped rows for Appearance, Lyrics,
/// Window, Sources & cache, Shortcuts.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @Environment(\.colorScheme) private var colorScheme

    private var tone: FL.Tone {
        switch prefs.tone {
        case .auto: return colorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
    private var palette: FL.Palette { FL.palette(tone: tone, hue: prefs.accentHue) }

    var body: some View {
        ZStack {
            (tone == .dark ? FL.oklch(0.16, 0.008, 250) : FL.oklch(0.97, 0.003, 250))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero.padding(.bottom, 28)

                    PrefGroup(title: "Appearance", palette: palette) {
                        PrefRow(label: "Window style", palette: palette) {
                            SegmentedPicker(
                                value: Binding(get: { prefs.windowStyle.label },
                                               set: { newLabel in
                                                   if let p = WindowStyle.allCases.first(where: { $0.label == newLabel }) {
                                                       prefs.windowStyle = p
                                                   }
                                               }),
                                options: WindowStyle.allCases.map(\.label),
                                palette: palette)
                        }
                        PrefRow(label: "Color theme", palette: palette) {
                            SegmentedPicker(
                                value: Binding(get: { prefs.tone.label },
                                               set: { newLabel in
                                                   if let t = Tone.allCases.first(where: { $0.label == newLabel }) {
                                                       prefs.tone = t
                                                   }
                                               }),
                                options: ["Light", "Dark", "Auto"],
                                palette: palette)
                        }
                        PrefRow(label: "Accent", palette: palette) {
                            AccentRow(hue: $prefs.accentHue, palette: palette)
                        }
                    }

                    PrefGroup(title: "Liquid Glass", palette: palette) {
                        let glassAvailable: Bool = {
                            if #available(macOS 26, *) { return true }
                            return false
                        }()
                        PrefRow(label: "Style",
                                sub: glassAvailable ? nil : "Requires macOS 26 (Tahoe)",
                                palette: palette) {
                            SegmentedPicker(
                                value: Binding(
                                    get: { prefs.glassStyle.displayName },
                                    set: { newLabel in
                                        if let g = GlassStyle.allCases.first(where: { $0.displayName == newLabel }) {
                                            prefs.glassStyle = g
                                        }
                                    }),
                                options: GlassStyle.allCases.map(\.displayName),
                                palette: palette)
                                .disabled(!glassAvailable)
                                .opacity(glassAvailable ? 1 : 0.5)
                                .accessibilityLabel("Liquid Glass style")
                        }
                        if prefs.glassStyle == .tinted && glassAvailable {
                            PrefRow(label: "Tint strength",
                                    sub: "Higher = more accent color over the glass",
                                    palette: palette) {
                                FlSlider(value: Binding(
                                    get: { prefs.glassOpacity * 100 },
                                    set: { prefs.glassOpacity = $0 / 100 }),
                                    range: 0...100, suffix: "%", palette: palette)
                                    .accessibilityLabel("Tint strength")
                                    .accessibilityValue("\(Int(prefs.glassOpacity * 100)) percent")
                            }
                        }
                    }

                    PrefGroup(title: "Lyrics", palette: palette) {
                        PrefRow(label: "Lines visible", palette: palette) {
                            SegmentedPicker(
                                value: Binding(
                                    get: {
                                        let v = prefs.linesVisible
                                        if v <= 1 { return "1" }
                                        if v <= 3 { return "3" }
                                        return "5"
                                    },
                                    set: { prefs.linesVisible = Int($0) ?? 3 }),
                                options: ["1", "3", "5"],
                                palette: palette)
                        }
                        PrefRow(label: "Font size",
                                sub: "Ignored in fullscreen — auto-scales to screen",
                                palette: palette) {
                            SegmentedPicker(
                                value: Binding(
                                    get: { prefs.fontSize.shortLabel },
                                    set: { newLabel in
                                        if let s = FontSize.allCases.first(where: { $0.shortLabel == newLabel }) {
                                            prefs.fontSize = s
                                        }
                                    }),
                                options: FontSize.allCases.map(\.shortLabel),
                                palette: palette)
                                .accessibilityLabel("Lyric font size")
                        }
                    }

                    PrefGroup(title: "Window", palette: palette) {
                        PrefRow(label: "Always on top", palette: palette) {
                            FlToggle(value: $prefs.alwaysOnTop, palette: palette)
                        }
                        PrefRow(label: "Hide window when no music", palette: palette) {
                            FlToggle(value: $prefs.hideWhenPaused, palette: palette)
                        }
                        PrefRow(label: "Show floating lyrics", palette: palette) {
                            FlToggle(value: $prefs.windowVisible, palette: palette)
                        }
                        PrefRow(label: "Launch at login", palette: palette) {
                            FlToggle(value: $prefs.launchAtLogin, palette: palette)
                        }
                    }

                    PrefGroup(title: "Sources & cache", palette: palette) {
                        PrefRow(label: "Read playback from", palette: palette) {
                            InfoPill(text: "Spotify (local)", palette: palette)
                        }
                        PrefRow(label: "Lyrics provider", palette: palette) {
                            InfoPill(text: "LRCLIB", palette: palette)
                        }
                        PrefRow(label: "Cached songs",
                                sub: "Stored in ~/Library/Caches/Cantio",
                                palette: palette) {
                            HStack(spacing: 10) {
                                Text(LyricsCache.shared.summary())
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.textMuted)
                                SmallButton(label: "Clear", palette: palette) {
                                    LyricsCache.shared.clear()
                                }
                            }
                        }
                    }

                    PrefGroup(title: "Shortcuts", palette: palette) {
                        PrefRow(label: "Toggle lyrics window", palette: palette) {
                            HotKeyRecorder(hotKey: $prefs.toggleHotKey)
                                .frame(width: 180)
                        }
                    }

                    Text("No telemetry. No accounts. No network calls except to fetch lyrics.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
            }
        }
        .frame(width: 560, height: 680)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            CantioIcon(size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text("Cantio")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.text)
                Text(versionString)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textMuted)
                HStack(spacing: 6) {
                    Chip(text: connectionLabel, accent: true, palette: palette)
                    Chip(text: "Privacy first · No accounts", accent: false, palette: palette)
                }
            }
            Spacer()
        }
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(v) · Reading Spotify · Lyrics from LRCLIB"
    }

    private var connectionLabel: String {
        // Reflect playback availability in the chip — small honest signal.
        switch Preferences.shared.windowVisible {
        case true: return "Connected"
        case false: return "Idle"
        }
    }
}

// MARK: - Group / row scaffolding

private struct PrefGroup<Content: View>: View {
    let title: String
    let palette: FL.Palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.textFaint)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(palette.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.bottom, 22)
    }
}

private struct PrefRow<Control: View>: View {
    let label: String
    var sub: String? = nil
    let palette: FL.Palette
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.text)
                if let sub {
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textMuted)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }
}

// MARK: - Custom controls

struct SegmentedPicker: View {
    @Binding var value: String
    let options: [String]
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.self) { o in
                let active = o.lowercased() == value.lowercased()
                Text(o)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(active ? palette.text : palette.textMuted)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(active ? palette.bgElev : .clear)
                            .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1, y: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { value = o }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.border))
    }
}

struct FlToggle: View {
    @Binding var value: Bool
    let palette: FL.Palette

    var body: some View {
        ZStack(alignment: value ? .trailing : .leading) {
            Capsule()
                .fill(value ? palette.accent : Color.white.opacity(0.18))
                .frame(width: 32, height: 19)
            Circle()
                .fill(.white)
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .padding(2)
        }
        .animation(.easeInOut(duration: 0.2), value: value)
        .contentShape(Capsule())
        .onTapGesture { value.toggle() }
    }
}

struct FlSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    Capsule().fill(palette.accent)
                        .frame(width: geo.size.width * pct, height: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .offset(x: geo.size.width * pct - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let p = max(0, min(1, g.location.x / geo.size.width))
                            value = range.lowerBound + p * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 18)
            Text("\(Int(value))\(suffix)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textMuted)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(width: 200)
    }
}

struct FlStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 0) {
            stepBtn("−") { if value > range.lowerBound { value -= 1 } }
            Text("\(value)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text)
                .frame(minWidth: 28)
                .padding(.vertical, 4)
            stepBtn("+") { if value < range.upperBound { value += 1 } }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5))
        )
    }

    private func stepBtn(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s)
                .font(.system(size: 13))
                .foregroundStyle(palette.textMuted)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InfoPill: View {
    let text: String
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(palette.accent).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08))
            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.5)))
    }
}

struct Chip: View {
    let text: String
    let accent: Bool
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 5) {
            if accent { Circle().fill(palette.accent).frame(width: 5, height: 5) }
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(accent ? palette.accent : palette.textMuted)
        .background(Capsule().fill(accent ? palette.accentSoft : Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(accent ? .clear : palette.border, lineWidth: 0.5))
    }
}

struct SmallButton: View {
    let label: String
    let palette: FL.Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }
}

struct AccentRow: View {
    @Binding var hue: Double
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach([220.0, 200.0, 160.0, 120.0, 50.0, 20.0, 340.0, 280.0], id: \.self) { h in
                let active = abs(h - hue) < 1
                Circle()
                    .fill(FL.oklch(0.78, 0.12, h))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().strokeBorder(active ? FL.oklch(0.78, 0.12, h) : .clear,
                                              lineWidth: 1.5)
                            .padding(-3)
                    )
                    .contentShape(Circle())
                    .onTapGesture { hue = h }
            }
        }
    }
}
