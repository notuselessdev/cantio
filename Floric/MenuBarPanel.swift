import SwiftUI
import AppKit

/// Custom menu-bar dropdown card. Replaces the system `.menu` style with a
/// `MenuBarExtra(.window)` panel that mirrors `menu-bar.jsx`: now-playing
/// row + three actions + Settings/Quit footer.
struct MenuBarPanel: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences
    let onAppear: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    private var tone: FL.Tone {
        switch prefs.tone {
        case .auto: return colorScheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
    private var palette: FL.Palette { FL.palette(tone: tone, hue: prefs.accentHue) }

    var body: some View {
        VStack(spacing: 0) {
            nowPlayingCard
            Divider().background(palette.border)
            VStack(spacing: 2) {
                MenuRow(icon: .window,
                        label: prefs.windowVisible ? "Hide lyrics window" : "Show lyrics window",
                        shortcut: "⌥⌘L", active: prefs.windowVisible, palette: palette) {
                    prefs.windowVisible.toggle()
                }
                MenuRow(icon: .theme,
                        label: "Theme",
                        trailing: Text(prefs.tone.label).font(.system(size: 11.5))
                            .foregroundStyle(palette.textMuted),
                        palette: palette) {
                    let order: [Tone] = [.auto, .light, .dark]
                    let i = order.firstIndex(of: prefs.tone) ?? 0
                    prefs.tone = order[(i + 1) % order.count]
                }
                MenuRow(icon: prefs.hideWhenPaused ? .play : .pause,
                        label: prefs.hideWhenPaused ? "Resume sync" : "Pause sync",
                        palette: palette) {
                    prefs.hideWhenPaused.toggle()
                }
            }
            .padding(4)

            Divider().background(palette.border)

            VStack(spacing: 2) {
                HoverableSettingsRow(palette: palette)
                    .keyboardShortcut(",")

                MenuRow(icon: .quit, label: "Quit Floric",
                        shortcut: "⌘Q", palette: palette) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
        }
        .frame(width: 268)
        .background(
            ZStack {
                VisualEffectBackground(material: .popover, blending: .behindWindow)
                (tone == .dark
                    ? Color(.sRGB, red: 28/255, green: 30/255, blue: 36/255, opacity: 0.30)
                    : Color(.sRGB, red: 252/255, green: 252/255, blue: 254/255, opacity: 0.40))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(palette.borderStrong, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(WindowTransparencyApplier())
        .preferredColorScheme(tone == .dark ? .dark : .light)
        .onAppear(perform: onAppear)
    }

    @ViewBuilder
    private var nowPlayingCard: some View {
        HStack(spacing: 11) {
            AlbumArtView(hues: trackHues, size: 42,
                         artworkURL: monitor.nowPlaying?.artworkURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.nowPlaying?.title ?? "Not playing")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(monitor.nowPlaying?.artist ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                if let np = monitor.nowPlaying, np.durationSeconds > 0 {
                    GeometryReader { geo in
                        let pct = max(0, min(1, np.positionSeconds / np.durationSeconds))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(palette.accent)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 2)
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var trackHues: [Double] {
        let seed = monitor.nowPlaying?.trackId ?? "floric"
        var hash = UInt64(5381)
        for ch in seed.unicodeScalars { hash = hash &* 33 &+ UInt64(ch.value) }
        let h0 = Double(hash % 360)
        return [h0, (h0 + 56).truncatingRemainder(dividingBy: 360),
                (h0 + 110).truncatingRemainder(dividingBy: 360)]
    }
}

// MARK: - Menu rows

enum MenuIconKind { case window, theme, pause, play, gear, quit }

struct MenuRow<Trailing: View>: View {
    let icon: MenuIconKind
    let label: String
    let shortcut: String?
    let trailing: Trailing
    let active: Bool
    let muted: Bool
    let palette: FL.Palette
    let action: () -> Void

    @State private var hover = false

    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         trailing: Trailing,
         active: Bool = false, muted: Bool = false,
         palette: FL.Palette, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.shortcut = shortcut
        self.trailing = trailing; self.active = active; self.muted = muted
        self.palette = palette; self.action = action
    }

    var body: some View {
        Button(action: action) {
            MenuRowLabel(icon: icon, label: label, shortcut: shortcut,
                         trailing: trailing, active: active || hover,
                         muted: muted, palette: palette)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

extension MenuRow where Trailing == EmptyView {
    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         active: Bool = false, muted: Bool = false,
         palette: FL.Palette, action: @escaping () -> Void) {
        self.init(icon: icon, label: label, shortcut: shortcut,
                  trailing: EmptyView(), active: active, muted: muted,
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
    let palette: FL.Palette

    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         trailing: Trailing,
         active: Bool = false, muted: Bool = false,
         palette: FL.Palette) {
        self.icon = icon; self.label = label; self.shortcut = shortcut
        self.trailing = trailing; self.active = active; self.muted = muted
        self.palette = palette
    }

    var body: some View {
        HStack(spacing: 10) {
            MenuIcon(kind: icon, color: active ? palette.accent : palette.textMuted)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 12.5, weight: active ? .medium : .regular))
                .foregroundStyle(muted ? palette.textMuted : palette.text)
            Spacer(minLength: 6)
            trailing
            if let s = shortcut {
                Text(s)
                    .font(.system(size: 11))
                    .tracking(0.4)
                    .foregroundStyle(palette.textFaint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? palette.accentSoft : .clear))
        .contentShape(Rectangle())
    }
}

extension MenuRowLabel where Trailing == EmptyView {
    init(icon: MenuIconKind, label: String,
         shortcut: String? = nil,
         active: Bool = false, muted: Bool = false,
         palette: FL.Palette) {
        self.init(icon: icon, label: label, shortcut: shortcut,
                  trailing: EmptyView(), active: active, muted: muted, palette: palette)
    }
}

private struct HoverableSettingsRow: View {
    let palette: FL.Palette
    @State private var hover = false

    var body: some View {
        SettingsLink {
            MenuRowLabel(icon: .gear, label: "Settings…",
                         shortcut: "⌘,", active: hover, palette: palette)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Walks up to the enclosing NSWindow (the MenuBarExtra panel host) and
/// clears its opaque background so our SwiftUI VisualEffectBackground shows
/// through. Without this, the panel's default solid backing masks the blur.
private struct WindowTransparencyApplier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        scheduleApply(from: v)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleApply(from: nsView)
    }

    /// SwiftUI re-installs an opaque backing on `MenuBarExtra(.window)`
    /// after our first pass, so retry across a few runloop ticks.
    private func scheduleApply(from view: NSView) {
        for delay in [0.0, 0.05, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                apply(from: view)
            }
        }
    }

    private func apply(from view: NSView) {
        guard let win = view.window else { return }
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        // Clear every ancestor layer between the SwiftUI host and the
        // window's contentView — any opaque NSVisualEffectView / backing
        // view in that chain will otherwise mask our blur.
        var cur: NSView? = view
        while let v = cur {
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.clear.cgColor
            if let ve = v as? NSVisualEffectView {
                ve.state = .active
                ve.blendingMode = .behindWindow
            }
            cur = v.superview
        }
        if let content = win.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }
        win.invalidateShadow()
    }
}

struct MenuIcon: View {
    let kind: MenuIconKind
    let color: Color

    var body: some View {
        Canvas { ctx, sz in
            let s = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            let c = GraphicsContext.Shading.color(color)
            let w = sz.width
            switch kind {
            case .window:
                var p = Path(roundedRect: CGRect(x: 1.5, y: 2.5, width: w - 3, height: w - 5),
                             cornerSize: CGSize(width: 1.5, height: 1.5))
                ctx.stroke(p, with: c, style: s)
                p = Path()
                p.move(to: CGPoint(x: 1.5, y: 5))
                p.addLine(to: CGPoint(x: w - 1.5, y: 5))
                ctx.stroke(p, with: c, style: s)
            case .theme:
                var p = Path()
                p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 9, height: 9))
                ctx.stroke(p, with: c, style: s)
            case .pause:
                var p = Path()
                p.move(to: CGPoint(x: 5, y: 3.5)); p.addLine(to: CGPoint(x: 5, y: 10.5))
                p.move(to: CGPoint(x: 9, y: 3.5)); p.addLine(to: CGPoint(x: 9, y: 10.5))
                ctx.stroke(p, with: c, style: s)
            case .play:
                var p = Path()
                p.move(to: CGPoint(x: 4, y: 3))
                p.addLine(to: CGPoint(x: 11, y: 7))
                p.addLine(to: CGPoint(x: 4, y: 11))
                p.closeSubpath()
                ctx.fill(p, with: c)
            case .gear:
                var p = Path()
                p.addEllipse(in: CGRect(x: 5, y: 5, width: 4, height: 4))
                ctx.stroke(p, with: c, style: s)
                p = Path()
                let pts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (7, 1, 7, 3), (7, 11, 7, 13), (1, 7, 3, 7), (11, 7, 13, 7)
                ]
                for (x1, y1, x2, y2) in pts {
                    p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
                }
                ctx.stroke(p, with: c, style: s)
            case .quit:
                var p = Path()
                p.move(to: CGPoint(x: 5.5, y: 11))
                p.addLine(to: CGPoint(x: 2.5, y: 11))
                p.addLine(to: CGPoint(x: 2.5, y: 3))
                p.addLine(to: CGPoint(x: 5.5, y: 3))
                ctx.stroke(p, with: c, style: s)
                p = Path()
                p.move(to: CGPoint(x: 9.5, y: 9.5))
                p.addLine(to: CGPoint(x: 12, y: 7))
                p.addLine(to: CGPoint(x: 9.5, y: 4.5))
                p.move(to: CGPoint(x: 5, y: 7))
                p.addLine(to: CGPoint(x: 12, y: 7))
                ctx.stroke(p, with: c, style: s)
            }
        }
    }
}
