import SwiftUI
import AppKit

/// Custom menu-bar dropdown card. Replaces the system `.menu` style with a
/// `MenuBarExtra(.window)` panel — now-playing card with real transport
/// controls (play/pause, prev, next, scrubber), then a small action list,
/// then Settings/Quit.
struct MenuBarPanel: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences
    let onAppear: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Liquid Glass for the panel is suppressed when the user has Reduce
    /// Transparency or Increase Contrast on, OR when running on macOS < 26
    /// (`effectiveGlassStyle` already enforces the runtime cap).
    private var panelGlassStyle: GlassStyle {
        if reduceTransparency || colorSchemeContrast == .increased { return .off }
        return prefs.effectiveGlassStyle
    }

    private var tone: FL.Tone {
        switch prefs.tone {
        case .auto: return colorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
    private var palette: FL.Palette { FL.palette(tone: tone, hue: prefs.accentHue) }

    var body: some View {
        Group {
            if #available(macOS 26, *), panelGlassStyle != .off {
                GlassEffectContainer(spacing: 0) {
                    panelContent
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.borderStrong.opacity(0.45), lineWidth: 0.5))
                }
            } else {
                panelContent
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.borderStrong, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: 290)
        .onAppear(perform: onAppear)
    }

    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 0) {
            nowPlayingCard
            ScrubberRow(monitor: monitor, palette: palette)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            if lyrics.state == .notFound, monitor.nowPlaying != nil {
                LyricsNudgeRow(palette: palette)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Divider().background(palette.border)
            VStack(spacing: 2) {
                MenuRow(icon: .window,
                        label: prefs.windowVisible ? "Hide lyrics window" : "Show lyrics window",
                        shortcut: "⌥⌘L", palette: palette) {
                    prefs.windowVisible.toggle()
                }
                MenuRow(icon: .eye,
                        label: "Auto-hide",
                        trailing: Toggle("", isOn: .constant(prefs.hideWhenPaused))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true),
                        palette: palette) {
                    prefs.hideWhenPaused.toggle()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Auto-hide")
                .accessibilityValue(prefs.hideWhenPaused ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            VStack(spacing: 2) {
                HoverableSettingsRow(palette: palette)
                    .keyboardShortcut(",")

                MenuRow(icon: .quit, label: "Quit Cantio",
                        shortcut: "⌘Q", destructive: true, palette: palette) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    /// Panel chrome background for non-Liquid-Glass branches:
    /// 1. Reduce Transparency / Increase Contrast → solid `palette.bgElev`.
    /// 2. Fallback (macOS 14/15 or `glassStyle == .off`) → existing
    ///    `NSVisualEffectView .popover`.
    /// macOS 26+ glass is applied directly to `panelContent` in `body` —
    /// `.glassEffect()` needs a real surface to render against.
    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            palette.bgElev
        } else {
            VisualEffectBackground(material: .popover, blending: .behindWindow)
        }
    }

    @ViewBuilder
    private var nowPlayingCard: some View {
        HStack(spacing: 11) {
            Button(action: focusSpotify) {
                AlbumArtView(hues: trackHues, size: 42,
                             artworkURL: monitor.nowPlaying?.artworkURL)
            }
            .buttonStyle(.plain)
            .help("Show Spotify")
            .accessibilityLabel("Show Spotify")

            VStack(alignment: .leading, spacing: 1) {
                LinkButton(action: openTrack,
                           enabled: monitor.nowPlaying != nil,
                           help: "Open track in Spotify",
                           a11yLabel: monitor.nowPlaying.map { "Open track \($0.title) in Spotify" } ?? "Not playing") { underlined in
                    MarqueeText(text: monitor.nowPlaying?.title ?? "Not playing",
                                font: .system(size: 12.5, weight: .semibold),
                                color: palette.text,
                                underline: underlined)
                }

                LinkButton(action: openArtist,
                           enabled: !(monitor.nowPlaying?.artist.isEmpty ?? true),
                           help: "Open artist in Spotify",
                           a11yLabel: monitor.nowPlaying.map { "Open artist \($0.artist) in Spotify" } ?? "") { underlined in
                    MarqueeText(text: monitor.nowPlaying?.artist ?? "—",
                                font: .system(size: 11),
                                color: palette.textMuted,
                                underline: underlined)
                }
            }
            Spacer(minLength: 4)
            TransportControls(monitor: monitor, palette: palette)
                .accessibilityHidden(false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func openTrack() {
        guard let id = monitor.nowPlaying?.trackId, !id.isEmpty,
              let url = URL(string: id) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openArtist() {
        guard let artist = monitor.nowPlaying?.artist,
              !artist.isEmpty,
              let encoded = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "spotify:search:\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func focusSpotify() {
        // `NSRunningApplication.activate` doesn't deminiaturize a Dock-minimized
        // window. Route through Launch Services instead so Spotify restores
        // its main window when activating.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }

    private var nowPlayingA11yLabel: String {
        guard let np = monitor.nowPlaying else { return "Not playing" }
        return "Now playing: \(np.title) by \(np.artist)"
    }

    private var trackHues: [Double] {
        let seed = monitor.nowPlaying?.trackId ?? "cantio"
        var hash = UInt64(5381)
        for ch in seed.unicodeScalars { hash = hash &* 33 &+ UInt64(ch.value) }
        let h0 = Double(hash % 360)
        return [h0, (h0 + 56).truncatingRemainder(dividingBy: 360),
                (h0 + 110).truncatingRemainder(dividingBy: 360)]
    }
}

// MARK: - Transport controls

/// Three-button transport row (prev / play-pause / next). Uses SF Symbols,
/// 28pt hit targets, full VoiceOver labels, keyboard shortcuts, and disables
/// itself when Spotify isn't available.
struct TransportControls: View {
    @ObservedObject var monitor: SpotifyMonitor
    let palette: FL.Palette

    private var disabled: Bool { monitor.availability != .available }
    private var isPlaying: Bool { monitor.nowPlaying?.state == .playing }

    var body: some View {
        HStack(spacing: 2) {
            // No `.keyboardShortcut(...)` on these buttons. SwiftUI registers
            // shortcuts in the responder chain; for `MenuBarExtra(.window)`
            // the panel window can stay key after closing, which leaks Space
            // / ⌘← / ⌘→ into other apps and randomly skips Spotify tracks.
            // Mouse + VoiceOver-only for now; system-wide hotkey is a
            // separate Carbon `RegisterEventHotKey` opt-in.
            TransportButton(symbol: "backward.fill",
                            label: "Previous track",
                            palette: palette,
                            disabled: disabled,
                            primary: false) {
                monitor.previousTrack()
            }

            TransportButton(symbol: isPlaying ? "pause.fill" : "play.fill",
                            label: isPlaying ? "Pause" : "Play",
                            palette: palette,
                            disabled: disabled,
                            primary: true) {
                monitor.playPause()
            }

            TransportButton(symbol: "forward.fill",
                            label: "Next track",
                            palette: palette,
                            disabled: disabled,
                            primary: false) {
                monitor.nextTrack()
            }
        }
    }
}

private struct TransportButton: View {
    let symbol: String
    let label: String
    let palette: FL.Palette
    let disabled: Bool
    let primary: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(background)
                Image(systemName: symbol)
                    .font(.system(size: primary ? 12 : 10, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: primary ? 30 : 26, height: primary ? 30 : 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hover = $0 && !disabled }
        .accessibilityLabel(label)
        .help(label)
        .frame(minWidth: 30, minHeight: 30)
    }

    private var background: Color {
        if primary { return palette.accent }
        return hover ? palette.accentSoft : .clear
    }
    private var foreground: Color {
        if primary { return .white }
        return hover ? palette.accent : palette.text
    }
}

// MARK: - Scrubber

/// Interactive progress bar bound to `monitor.interpolatedPosition(now:)`.
/// Drag to scrub — emits a single seek on drag end + tap. Reduce-Motion
/// skips the smooth tick so the displayed position snaps to truth.
struct ScrubberRow: View {
    @ObservedObject var monitor: SpotifyMonitor
    let palette: FL.Palette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragPosition: Double?
    @State private var tickedNow: Date = Date()
    @State private var tickerTask: Task<Void, Never>?

    private var disabled: Bool {
        monitor.availability != .available
            || (monitor.nowPlaying?.durationSeconds ?? 0) <= 0
    }

    private var duration: Double { monitor.nowPlaying?.durationSeconds ?? 0 }

    private var displayedPosition: Double {
        if let dragPosition { return dragPosition }
        return monitor.interpolatedPosition(now: tickedNow)
            ?? monitor.nowPlaying?.positionSeconds ?? 0
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let pct = duration > 0
                    ? max(0, min(1, displayedPosition / duration))
                    : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderStrong)
                        .frame(height: 3)
                    Capsule()
                        .fill(disabled ? palette.textFaint : palette.accent)
                        .frame(width: geo.size.width * pct, height: 3)
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 10, height: 10)
                        .opacity(disabled ? 0 : (dragPosition != nil ? 1 : 0))
                        .offset(x: geo.size.width * pct - 5)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: geo.size.width))
            }
            .frame(height: 18)

            HStack {
                Text(format(displayedPosition))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textMuted)
                Spacer(minLength: 0)
                Text(format(duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textMuted)
            }
        }
        .opacity(disabled ? 0.35 : 1)
        .allowsHitTesting(!disabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(format(displayedPosition)) of \(format(duration))")
        .accessibilityAdjustableAction { dir in
            guard !disabled else { return }
            let delta: Double = (dir == .increment) ? 5 : -5
            let target = max(0, min(duration, displayedPosition + delta))
            monitor.seek(to: target)
        }
        .onAppear { startTicker() }
        .onDisappear { tickerTask?.cancel(); tickerTask = nil }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard !disabled, duration > 0, width > 0 else { return }
                let p = max(0, min(1, g.location.x / width))
                dragPosition = p * duration
            }
            .onEnded { _ in
                guard !disabled, let target = dragPosition else { return }
                monitor.seek(to: target)
                // Hold drag value briefly so the next poll has time to land
                // (~500 ms) — otherwise UI snaps back to stale position.
                let hold = dragPosition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if dragPosition == hold { dragPosition = nil }
                }
            }
    }

    private func startTicker() {
        guard tickerTask == nil, !reduceMotion else {
            tickedNow = Date()
            return
        }
        tickerTask = Task { @MainActor in
            while !Task.isCancelled {
                tickedNow = Date()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func format(_ s: Double) -> String {
        let total = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Compact row shown beneath the scrubber when LRCLIB returned no lyrics
/// for the current track. Floating window stays empty in that state — this
/// is the only place the user is told.
private struct LyricsNudgeRow: View {
    let palette: FL.Palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(palette.textMuted)
            Text("No lyrics found for this track")
                .font(.system(size: 11))
                .foregroundStyle(palette.textMuted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Menu rows

enum MenuIconKind { case window, theme, pause, play, gear, quit, eye }

struct MenuRow<Trailing: View>: View {
    let icon: MenuIconKind
    let label: String
    let shortcut: String?
    let trailing: Trailing
    let active: Bool
    let muted: Bool
    let destructive: Bool
    let palette: FL.Palette
    let action: () -> Void

    @State private var hover = false

    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         trailing: Trailing,
         active: Bool = false, muted: Bool = false, destructive: Bool = false,
         palette: FL.Palette, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.shortcut = shortcut
        self.trailing = trailing; self.active = active; self.muted = muted
        self.destructive = destructive
        self.palette = palette; self.action = action
    }

    var body: some View {
        Button(action: action) {
            MenuRowLabel(icon: icon, label: label, shortcut: shortcut,
                         trailing: trailing, active: active || hover,
                         muted: muted, destructive: destructive, palette: palette)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

extension MenuRow where Trailing == EmptyView {
    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         active: Bool = false, muted: Bool = false, destructive: Bool = false,
         palette: FL.Palette, action: @escaping () -> Void) {
        self.init(icon: icon, label: label, shortcut: shortcut,
                  trailing: EmptyView(), active: active, muted: muted,
                  destructive: destructive,
                  palette: palette, action: action)
    }
}

struct MenuRowLabel<Trailing: View>: View {
    let icon: MenuIconKind
    let label: String
    let shortcut: String?
    let trailing: Trailing
    let active: Bool
    let muted: Bool
    let destructive: Bool
    let palette: FL.Palette

    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         trailing: Trailing,
         active: Bool = false, muted: Bool = false, destructive: Bool = false,
         palette: FL.Palette) {
        self.icon = icon; self.label = label; self.shortcut = shortcut
        self.trailing = trailing; self.active = active; self.muted = muted
        self.destructive = destructive
        self.palette = palette
    }

    private var iconColor: Color {
        if destructive && active { return Color(nsColor: .systemRed) }
        return active ? palette.accent : palette.textMuted
    }
    private var labelColor: Color {
        if destructive && active { return Color(nsColor: .systemRed) }
        return muted ? palette.textMuted : palette.text
    }
    private var bgColor: Color {
        if destructive && active { return Color(nsColor: .systemRed).opacity(0.14) }
        return active ? palette.accentSoft : .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            MenuIcon(kind: icon, color: iconColor)
            Text(label)
                .font(.system(size: 12.5, weight: active ? .medium : .regular))
                .foregroundStyle(labelColor)
            Spacer(minLength: 6)
            trailing
            if let s = shortcut {
                Text(s)
                    .font(.system(size: 11))
                    .tracking(0.4)
                    .foregroundStyle(palette.textFaint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bgColor))
        .contentShape(Rectangle())
    }
}

extension MenuRowLabel where Trailing == EmptyView {
    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         active: Bool = false, muted: Bool = false, destructive: Bool = false,
         palette: FL.Palette) {
        self.init(icon: icon, label: label, shortcut: shortcut,
                  trailing: EmptyView(), active: active, muted: muted,
                  destructive: destructive, palette: palette)
    }
}

/// Settings row that focuses an existing window when one is already on
/// screen, instead of letting `SettingsLink` spawn / re-open. Falls back to
/// `SettingsLink` when no Settings window exists.
private struct HoverableSettingsRow: View {
    let palette: FL.Palette
    @State private var hover = false

    var body: some View {
        if let _ = Self.findSettingsWindow() {
            // Existing window — render a Button that focuses it directly.
            Button {
                Self.focusExistingSettingsWindow()
            } label: {
                MenuRowLabel(icon: .gear, label: "Settings…",
                             shortcut: "⌘,", active: hover, palette: palette)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        } else {
            SettingsLink {
                MenuRowLabel(icon: .gear, label: "Settings…",
                             shortcut: "⌘,", active: hover, palette: palette)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }

    /// Locates the SwiftUI Settings scene window. SwiftUI gives it a stable
    /// identifier (`com_apple_SwiftUI_Settings_window`); also tolerate a
    /// frame-autosave-name fallback in case Apple changes that contract.
    static func findSettingsWindow() -> NSWindow? {
        for w in NSApp.windows {
            let id = w.identifier?.rawValue ?? ""
            if id.contains("Settings") || id.contains("settings") {
                return w
            }
            if w.frameAutosaveName.contains("Settings") {
                return w
            }
        }
        return nil
    }

    static func focusExistingSettingsWindow() {
        guard let w = findSettingsWindow() else { return }
        if w.isMiniaturized { w.deminiaturize(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct MenuIcon: View {
    let kind: MenuIconKind
    let color: Color

    private var symbolName: String {
        switch kind {
        case .window: return "macwindow"
        case .theme: return "circle.righthalf.filled"
        case .pause: return "pause.fill"
        case .play: return "play.fill"
        case .gear: return "gearshape"
        case .quit: return "power"
        case .eye: return "eye"
        }
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Marquee text

/// Single-line text that scrolls horizontally when the rendered width
/// exceeds the available container. Static + truncated when the text fits,
/// or when Reduce Motion is on (HIG: never animate purely decorative
/// motion if the user has opted out).
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var underline: Bool = false
    var pointsPerSecond: CGFloat = 18
    /// Explicit line-height override. Defaults to 16pt (panel rows). Pill
    /// callers pass the active font size so larger lyric text isn't clipped.
    var lineHeight: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startDate = Date()

    private var overflows: Bool { contentWidth > containerWidth + 0.5 }
    private var animate: Bool { overflows && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if animate {
                    TimelineView(.animation) { ctx in
                        Text(text)
                            .font(font)
                            .underline(underline, color: color)
                            .lineLimit(1)
                            .fixedSize()
                            .offset(x: -bounceOffset(at: ctx.date))
                    }
                } else {
                    Text(text)
                        .font(font)
                        .underline(underline, color: color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(color)
            .frame(width: geo.size.width, alignment: .leading)
            .background(
                Text(text).font(font).fixedSize()
                    .hidden()
                    .background(GeometryReader { g in
                        Color.clear.preference(key: MarqueeWidthKey.self, value: g.size.width)
                    })
            )
            .onPreferenceChange(MarqueeWidthKey.self) { contentWidth = $0 }
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in
                containerWidth = w
                resetBounce()
            }
            .onChange(of: animate) { _, on in
                if on { resetBounce() }
            }
            .onChange(of: text) { _, _ in
                resetBounce()
            }
            .clipped()
        }
        .frame(height: lineHeight)
    }

    private func bounceOffset(at date: Date) -> CGFloat {
        let maxOffset = max(0, contentWidth - containerWidth)
        guard maxOffset > 0 else { return 0 }
        let cycleDistance = maxOffset * 2
        let traveled = CGFloat(date.timeIntervalSince(startDate)) * pointsPerSecond
        let phase = traveled.truncatingRemainder(dividingBy: cycleDistance)
        return phase <= maxOffset ? phase : cycleDistance - phase
    }

    private func resetBounce() {
        startDate = Date()
    }
}

/// Button that styles its label like a hyperlink: pointing-hand cursor +
/// underline while hovered. Label closure receives the current hover state
/// so it can apply underline (or any other hover-driven style) to the inner
/// `MarqueeText` / `Text`.
private struct LinkButton<Label: View>: View {
    let action: () -> Void
    let enabled: Bool
    let help: String
    let a11yLabel: String
    @ViewBuilder let label: (Bool) -> Label

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label(hover && enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(a11yLabel)
        .onHover { hovering in
            hover = hovering
            guard enabled else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
