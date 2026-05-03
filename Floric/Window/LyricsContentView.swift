import SwiftUI
import AppKit

/// Shared bridge between the SwiftUI capsule geometry and the AppKit window's
/// hit-testing. The pill window stays the same fixed 520x80 NSWindow but the
/// visible capsule hugs its content, leaving transparent margins. The view
/// publishes the capsule's frame (in the SwiftUI host's content coordinate
/// space — top-left origin) and the controller flips `ignoresMouseEvents`
/// based on whether the cursor is inside that rect.
@MainActor
final class PillHitTarget: ObservableObject {
    @Published var capsuleRectInContentView: CGRect = .zero
}

/// Floating lyrics window content. Implements the six visual presets from
/// the design handoff: pill / pillStack / glass / solid / minimal /
/// fullscreen.
struct LyricsContentView: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences
    @EnvironmentObject var hitTarget: PillHitTarget

    /// Coordinate space declared at the root of `pillBody` so PillCapsule
    /// can report its frame relative to the NSHostingView's contentView.
    private static let pillCoordinateSpace = "pillContent"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var style: WindowStyle { prefs.windowStyle }
    private var bgStyle: BackgroundStyle { prefs.backgroundStyle }
    private var resolvedTone: FL.Tone {
        switch prefs.tone {
        case .auto: return FL.resolveTone(nil)
        case .light: return .light
        case .dark: return .dark
        }
    }
    private var palette: FL.Palette {
        FL.palette(tone: effectiveTone, hue: prefs.accentHue)
    }
    /// When Reduce Transparency is on, glass / pill modes degrade to solid.
    private var effectiveTone: FL.Tone { resolvedTone }
    private var degradeToSolid: Bool { reduceTransparency }
    private var increaseContrast: Bool { colorSchemeContrast == .increased }

    /// Effective glass style for the pill. Honors accessibility:
    /// Reduce Transparency + Increase Contrast both force `.off` so the
    /// silhouette is solid and high-contrast against the wallpaper.
    private var pillGlassStyle: GlassStyle {
        if reduceTransparency || increaseContrast { return .off }
        return prefs.effectiveGlassStyle
    }

    /// Maps `prefs.linesVisible` (1 / 3 / 5) to the symmetric neighbor count
    /// shown around the current line: 0 / 1 / 2.
    private var linesAroundFromPref: Int {
        let v = prefs.linesVisible
        if v <= 1 { return 0 }
        if v <= 3 { return 1 }
        return 2
    }

    var body: some View {
        Group {
            switch style {
            case .pill: pillBody(linesAround: linesAroundFromPref)
            case .fullscreen: fullscreenBody
            case .minimal: windowBody
            }
        }
        .preferredColorScheme(effectiveTone == .dark ? .dark : .light)
    }

    // MARK: - Pill / Pill Stack

    @ViewBuilder
    private func pillBody(linesAround: Int) -> some View {
        ZStack {
            // No window chrome — capsule(s) hover over wallpaper.
            switch monitor.availability {
            case .permissionDenied:
                permissionCapsule.modifier(PillCapsuleFrameReporter(space: Self.pillCoordinateSpace, hitTarget: hitTarget))
            case .notInstalled:
                placeholderCapsule("Install Spotify to see lyrics")
                    .modifier(PillCapsuleFrameReporter(space: Self.pillCoordinateSpace, hitTarget: hitTarget))
            case .notRunning, .available:
                lyricsContent(forPill: true, linesAround: linesAround)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.pillCoordinateSpace)
    }

    // MARK: - Window (glass / solid / minimal)

    @ViewBuilder
    private var windowBody: some View {
        ZStack {
            background
            content
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 18)
        }
        .frame(minWidth: 280, minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderStrong, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) { trafficLights }
    }

    // MARK: - Fullscreen karaoke

    @ViewBuilder
    private var fullscreenBody: some View {
        ZStack(alignment: .topTrailing) {
            KaraokeBackdrop(hues: trackHues, tone: effectiveTone,
                            palette: palette, reduceMotion: reduceMotion)
            VStack(spacing: 0) {
                // Header — album art + title.
                if let np = monitor.nowPlaying {
                    HStack(spacing: 14) {
                        AlbumArtView(hues: trackHues, size: 56, artworkURL: np.artworkURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(np.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
                            Text("\(np.artist) · \(np.album)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
                        }
                        Spacer()
                    }
                    .padding(.top, 36)
                    .padding(.horizontal, 40)
                }
                Spacer(minLength: 0)
                // Fullscreen ignores prefs.fontSize and auto-scales to fill
                // — a 27" external and a 13" laptop both want different
                // absolute sizes, and the user shouldn't have to retune the
                // font slider when they plug in a display.
                GeometryReader { geo in
                    let active = min(96, max(28, geo.size.height / 8))
                    lyricsContent(forPill: false, linesAround: linesAroundFromPref,
                                  fullscreenActiveSize: active)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(.horizontal, 80)
                Spacer(minLength: 0)
                if monitor.nowPlaying != nil {
                    progressBar(fullscreen: true)
                        .padding(.horizontal, 80)
                        .padding(.bottom, 56)
                }
            }
            // Visible exit affordance — Esc also works (controller's local
            // key monitor) but a discoverable button matches HIG.
            Button {
                prefs.windowStyle = .pill
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Exit fullscreen")
            .accessibilityLabel("Exit fullscreen")
            .padding(.top, 24)
            .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Window chrome

    private var trafficLights: some View {
        HStack(spacing: 7) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34),
                     Color(red: 1, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { c in
                Circle()
                    .fill(c)
                    .overlay(Circle().strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
                    .frame(width: 11, height: 11)
            }
        }
        .padding(.top, 10)
        .padding(.leading, 12)
    }

    private var titleStrip: some View {
        Group {
            if let np = monitor.nowPlaying {
                Text("\(np.title) · \(np.artist)")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(palette.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 80)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let isSolid = bgStyle == .solid || degradeToSolid
        if isSolid {
            palette.bgElev
        } else {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                let t = max(0, min(1, prefs.glassOpacity))
                (effectiveTone == .dark
                    ? Color(.sRGB, red: 22/255, green: 24/255, blue: 30/255, opacity: t)
                    : Color(.sRGB, red: 252/255, green: 252/255, blue: 254/255, opacity: t))
            }
        }
    }

    // MARK: - Body content (glass/solid/minimal)

    @ViewBuilder
    private var content: some View {
        switch monitor.availability {
        case .permissionDenied: permissionDeniedView
        case .notInstalled: placeholder("Install Spotify to see lyrics here")
        case .notRunning: emptyStateView
        case .available:
            if monitor.nowPlaying == nil || monitor.nowPlaying?.state == .stopped {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    lyricsContent(forPill: false, linesAround: linesAroundFromPref)
                        .frame(maxHeight: .infinity)
                }
                .overlay(alignment: .bottom) { minimalFooter }
            }
        }
    }

    // MARK: - Lyrics renderer

    @ViewBuilder
    private func lyricsContent(forPill: Bool, linesAround: Int,
                               fullscreenActiveSize: CGFloat? = nil) -> some View {
        switch lyrics.state {
        // Floating window stays quiet when there are no lyrics — the
        // menubar panel surfaces the "No lyrics found" nudge instead.
        case .idle: EmptyView()
        case .loading: placeholderCapsuleOrText("Loading lyrics…", forPill: forPill)
        case .notFound: EmptyView()
        case .error(let msg): placeholderCapsuleOrText(msg, forPill: forPill)
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: prefs.fontSize.bodySize))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.text)
            }
        case .synced(let lines):
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in
                let pos = monitor.interpolatedPosition(now: ctx.date)
                    ?? monitor.nowPlaying?.positionSeconds ?? 0
                let lp = LyricPosition.compute(lines: lines, position: pos)
                syncedRender(lp: lp, forPill: forPill, linesAround: linesAround,
                             fullscreenActiveSize: fullscreenActiveSize)
                    // Reduce Motion: hard-cut between lines (no crossfade).
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                               value: lp.current?.timestamp)
            }
        }
    }

    @ViewBuilder
    private func syncedRender(lp: LyricPosition, forPill: Bool,
                              linesAround: Int,
                              fullscreenActiveSize: CGFloat? = nil) -> some View {
        let cur = lp.current
        let large = fullscreenActiveSize != nil
        let activeSize: CGFloat = fullscreenActiveSize ?? prefs.fontSize.activeSize
        let dimSize: CGFloat = large
            ? max(18, activeSize * 0.6)
            : max(12, prefs.fontSize.activeSize * 0.78)
        let curWords = cur?.words ?? (forPill ? ["♪"] : ["♪  ♪  ♪"])

        if forPill {
            // Pill sibling sizes scale with the active line so the user's
            // FontSize choice carries through to the whole pill, not just
            // the capsule.
            let pillActive = prefs.fontSize.activeSize
            let pillFar: CGFloat = max(10, pillActive * 0.55)
            let pillNear: CGFloat = max(11, pillActive * 0.7)
            // Spacing bumped from 8 → 16 so dim sibling lines sit outside
            // the pill's shadow falloff (~6pt). Within that band, sibling
            // crossfades read as a "pulsing dark edge" along the pill rim.
            VStack(spacing: 14) {
                if linesAround >= 2 {
                    pillSibling(words: lp.prev2?.words, exists: lp.prev2 != nil,
                                size: pillFar, opacity: 0.6)
                }
                if linesAround >= 1 {
                    pillSibling(words: lp.prev?.words, exists: lp.prev != nil,
                                size: pillNear, opacity: 1)
                }
                PillCapsule(words: curWords, palette: palette, tone: effectiveTone,
                            bgStyle: bgStyle, fontSize: pillActive,
                            glassOpacity: prefs.glassOpacity,
                            glassStyle: pillGlassStyle, increaseContrast: increaseContrast,
                            reduceTransparency: reduceTransparency)
                    .modifier(PillCapsuleFrameReporter(space: Self.pillCoordinateSpace, hitTarget: hitTarget))
                if linesAround >= 1 {
                    pillSibling(words: lp.next?.words, exists: lp.next != nil,
                                size: pillNear, opacity: 1)
                }
                if linesAround >= 2 {
                    pillSibling(words: lp.next2?.words, exists: lp.next2 != nil,
                                size: pillFar, opacity: 0.6)
                }
            }
        } else {
            VStack(spacing: large ? 26 : 10) {
                if linesAround >= 2 {
                    windowSibling(words: lp.prev2?.words, exists: lp.prev2 != nil,
                                  size: dimSize * 0.85, fade: 0.5)
                }
                if linesAround >= 1 {
                    windowSibling(words: lp.prev?.words, exists: lp.prev != nil,
                                  size: dimSize, fade: 1, highlighted: true)
                }
                LyricLineView(words: curWords, highlighted: true,
                              active: true, dim: false, color: palette.text,
                              accent: palette.accent, size: activeSize)
                if linesAround >= 1 {
                    windowSibling(words: lp.next?.words, exists: lp.next != nil,
                                  size: dimSize, fade: 1)
                }
                if linesAround >= 2 {
                    windowSibling(words: lp.next2?.words, exists: lp.next2 != nil,
                                  size: dimSize * 0.85, fade: 0.5)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func pillSibling(words: [String]?, exists: Bool,
                             size: CGFloat, opacity: Double) -> some View {
        // Single-line truncation with one trailing ellipsis — `LyricLineView`
        // wraps each word independently and produces per-word "..." when
        // the line overflows the pill window, which reads as garbled.
        // Sibling lines are blurred so attention stays on the active line.
        Text(words?.joined(separator: " ") ?? "♪")
            .font(.system(size: size, weight: .semibold))
            .tracking(max(0.3, size * 0.04))
            .foregroundStyle(palette.textFaint)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .blur(radius: 1.5)
            .opacity(exists ? opacity : 0)
            // Sibling fades go through the pill's shadow if they share the
            // parent's easeInOut(0.3); strip transactions and use a short
            // explicit fade instead.
            .transaction { $0.animation = .easeOut(duration: 0.18) }
    }

    @ViewBuilder
    private func windowSibling(words: [String]?, exists: Bool,
                               size: CGFloat, fade: Double,
                               highlighted: Bool = false) -> some View {
        // Sibling lines are blurred so attention stays on the active line.
        LyricLineView(words: words ?? ["♪"],
                      highlighted: highlighted,
                      active: false, dim: true, color: palette.textFaint,
                      accent: palette.accent, size: size)
            .opacity(exists ? fade : 0)
            .blur(radius: 2)
    }

    // MARK: - Footer

    @ViewBuilder
    private func progressBar(fullscreen: Bool) -> some View {
        if let np = monitor.nowPlaying, np.durationSeconds > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let pos = monitor.interpolatedPosition(now: ctx.date) ?? np.positionSeconds
                let pct = max(0, min(1, pos / np.durationSeconds))
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(fullscreen ? 0.18 : 0.10))
                            Capsule()
                                .fill(fullscreen ? Color.white.opacity(0.85) : palette.accent)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        Text(formatTime(pos))
                        Spacer()
                        Text("−" + formatTime(np.durationSeconds - pos))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textFaint)
                }
            }
        }
    }

    private var minimalFooter: some View {
        Group {
            if let np = monitor.nowPlaying, np.durationSeconds > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let pos = monitor.interpolatedPosition(now: ctx.date) ?? np.positionSeconds
                    let pct = max(0, min(1, pos / np.durationSeconds))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.08))
                            Rectangle().fill(palette.accent)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 2)
                }
            }
        }
    }

    // MARK: - Empty / permission

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Text("Open Spotify and play a song")
                .font(.system(size: prefs.fontSize.bodySize, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("Floric will follow along with synced lyrics.")
                .font(.system(size: max(11, prefs.fontSize.bodySize - 2)))
                .foregroundStyle(palette.textMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 10) {
            Text("Spotify access needed")
                .font(.system(size: prefs.fontSize.bodySize, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("Allow Floric to control Spotify in Privacy & Security → Automation.")
                .font(.system(size: max(11, prefs.fontSize.bodySize - 2)))
                .foregroundStyle(palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                SpotifyPermission.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionCapsule: some View {
        PillCapsule(words: ["Grant", "Spotify", "access"],
                    palette: palette, tone: effectiveTone,
                    bgStyle: bgStyle, fontSize: prefs.fontSize.activeSize,
                    glassOpacity: prefs.glassOpacity,
                    glassStyle: pillGlassStyle, increaseContrast: increaseContrast,
                    reduceTransparency: reduceTransparency)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: prefs.fontSize.bodySize, weight: .medium))
            .foregroundStyle(palette.textMuted)
            .frame(maxWidth: .infinity)
    }

    private func placeholderCapsule(_ text: String) -> some View {
        let words = text.split(separator: " ").map(String.init)
        return PillCapsule(words: words,
                           palette: palette, tone: effectiveTone,
                           bgStyle: bgStyle, fontSize: prefs.fontSize.activeSize,
                           glassOpacity: prefs.glassOpacity,
                           glassStyle: pillGlassStyle, increaseContrast: increaseContrast,
                           reduceTransparency: reduceTransparency)
    }

    @ViewBuilder
    private func placeholderCapsuleOrText(_ text: String, forPill: Bool) -> some View {
        if forPill { placeholderCapsule(text) } else { placeholder(text) }
    }

    // MARK: - Helpers

    private func formatTime(_ s: Double) -> String {
        let total = Int(max(0, s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Deterministic art hues from the current track id.
    private var trackHues: [Double] {
        let seed = monitor.nowPlaying?.trackId ?? "floric"
        var hash = UInt64(5381)
        for ch in seed.unicodeScalars { hash = hash &* 33 &+ UInt64(ch.value) }
        let h0 = Double(hash % 360)
        return [h0, (h0 + 56).truncatingRemainder(dividingBy: 360),
                (h0 + 110).truncatingRemainder(dividingBy: 360)]
    }
}

// MARK: - Lyric position (replaces old activeIndex)

struct LyricPosition {
    struct Line { let timestamp: Double; let text: String; let words: [String] }
    let prev2: Line?
    let prev: Line?
    let current: Line?
    let next: Line?
    let next2: Line?

    static func compute(lines: [LyricLine], position: Double) -> LyricPosition {
        guard !lines.isEmpty else {
            return LyricPosition(prev2: nil, prev: nil, current: nil, next: nil, next2: nil)
        }
        let idx = LyricLine.activeIndex(in: lines, at: position)
        guard let i = idx else {
            return LyricPosition(prev2: nil, prev: nil, current: nil,
                next: line(at: 0, in: lines),
                next2: lines.count > 1 ? line(at: 1, in: lines) : nil)
        }
        let cur = line(at: i, in: lines)
        let prev = i > 0 ? line(at: i - 1, in: lines) : nil
        let prev2 = i > 1 ? line(at: i - 2, in: lines) : nil
        let nxt = i + 1 < lines.count ? line(at: i + 1, in: lines) : nil
        let nxt2 = i + 2 < lines.count ? line(at: i + 2, in: lines) : nil
        return LyricPosition(prev2: prev2, prev: prev, current: cur, next: nxt, next2: nxt2)
    }

    private static func line(at i: Int, in lines: [LyricLine]) -> Line {
        let l = lines[i]
        let text = l.text.isEmpty ? "♪" : l.text
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return Line(timestamp: l.timestamp, text: text,
                    words: words.isEmpty ? ["♪"] : words)
    }
}

// MARK: - Lyric line renderer

struct LyricLineView: View {
    let words: [String]
    let highlighted: Bool
    let active: Bool
    let dim: Bool
    let color: Color
    let accent: Color
    let size: CGFloat

    var body: some View {
        let opacity: Double = active ? 1 : (dim ? 0.4 : 0.6)
        FlowLayout(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Text(w)
                    .font(.system(size: size, weight: active ? .bold : .semibold))
                    .tracking(max(0.3, size * 0.04))
                    .foregroundStyle(highlighted ? accent : color.opacity(0.55))
                    .fixedSize()
            }
        }
        .opacity(opacity)
    }
}

// MARK: - Pill capsule

struct PillCapsule: View {
    let words: [String]
    let palette: FL.Palette
    let tone: FL.Tone
    let bgStyle: BackgroundStyle
    /// Active-line font size driven by `Preferences.FontSize`. Defaults to
    /// the legacy hard-coded 16 so existing tests / call sites that don't
    /// pass a size still render at the previous default.
    var fontSize: CGFloat = 16
    var glassOpacity: Double = 0.4
    /// Liquid Glass style. `.off` keeps the existing solid/visual-effect
    /// rendering. Caller is expected to have already collapsed accessibility
    /// states (Reduce Transparency / Increase Contrast) into this value.
    var glassStyle: GlassStyle = .off
    var increaseContrast: Bool = false
    /// Reduce Transparency forces the legacy fill to fully opaque palette
    /// elev so the pill silhouette doesn't bleed wallpaper through. Caller
    /// passes the env value directly — keeps PillCapsule a pure View.
    var reduceTransparency: Bool = false

    var body: some View {
        // L2: When Liquid Glass is active and available, wrap the capsule in
        // a GlassEffectContainer so any sibling glass surfaces (e.g. future
        // controls inside the pill) merge into one silhouette. Falls back to
        // the legacy capsule fill on macOS < 26 or when glassStyle == .off.
        if #available(macOS 26, *), glassStyle != .off {
            GlassEffectContainer(spacing: 0) {
                pillContent
                    .glassEffectModifier(style: glassStyle,
                                         tint: palette.accent.opacity(glassOpacity))
            }
            .transaction { $0.animation = nil }
        } else {
            pillContent
                .background { legacyBackground }
                .transaction { $0.animation = nil }
        }
    }

    private var pillContent: some View {
        // Capsule hugs the rendered text so short lines stay tight and
        // long lines extend up to the parent's available width before
        // MarqueeText takes over the overflow. `.fixedSize(horizontal:)`
        // lets the inner Text report its natural width to the parent
        // layout instead of being stretched to maxWidth.
        Text(words.joined(separator: " "))
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(max(0.4, fontSize * 0.04))
            .foregroundStyle(palette.accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, max(12, fontSize * 0.9))
            .padding(.vertical, max(7, fontSize * 0.5))
    }

    private var legacyBackground: some View {
        let stroke = tone == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        return Capsule()
            .fill(pillFillColor)
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
            // drawingGroup rasterizes the capsule + shadow into a single
            // bitmap, preventing CALayer's implicit shadowPath animation
            // when the HStack's intrinsic width changes between word
            // counts (which produced the residual bottom band even with
            // compositingGroup + animation suppression).
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 0)
            .drawingGroup()
    }

    private var pillFillColor: Color {
        // Reduce Transparency / Increase Contrast force fully opaque palette
        // so the silhouette is legible against any wallpaper. Without this
        // the legacy glass fill stays translucent (0.58–0.92 alpha) even
        // after pillGlassStyle collapses to .off.
        if increaseContrast || reduceTransparency { return palette.bgElev }
        switch bgStyle {
        case .solid:
            return tone == .dark
                ? Color(.sRGB, red: 22/255, green: 24/255, blue: 30/255, opacity: 0.92)
                : Color(.sRGB, red: 252/255, green: 252/255, blue: 254/255, opacity: 0.94)
        case .glass:
            let tint = max(0, min(1, glassOpacity))
            let glassOp = 0.58 + 0.34 * tint
            return tone == .dark
                ? Color(.sRGB, red: 22/255, green: 24/255, blue: 30/255, opacity: glassOp)
                : Color(.sRGB, red: 252/255, green: 252/255, blue: 254/255, opacity: glassOp)
        }
    }
}

/// Helper to apply `.glassEffect()` with optional tint inside a single
/// branch. Extracted because the modifier chain differs by glass style and
/// inline conditionals on `.glassEffect(...)` confuse the type checker.
@available(macOS 26, *)
extension View {
    /// Applies `.glassEffect()` keyed off the user-selected `GlassStyle`.
    /// `.off` is a no-op so callers can branch on availability without an
    /// extra conditional.
    @ViewBuilder
    func glassEffectModifier<S: Shape>(style: GlassStyle,
                                       tint: Color,
                                       in shape: S) -> some View {
        switch style {
        case .off:
            self
        case .clear:
            self.glassEffect(in: shape)
        case .tinted:
            self.glassEffect(.regular.tint(tint), in: shape)
        }
    }

    /// Capsule-shape convenience — matches the pill silhouette.
    @ViewBuilder
    func glassEffectModifier(style: GlassStyle, tint: Color) -> some View {
        glassEffectModifier(style: style, tint: tint, in: Capsule())
    }
}

// MARK: - Track strip

struct TrackStrip: View {
    let track: NowPlaying
    let palette: FL.Palette
    let hues: [Double]

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(hues: hues, size: 40, artworkURL: track.artworkURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            NowBars(color: palette.accent)
        }
    }
}

// MARK: - Album art (procedural)

struct AlbumArtView: View {
    let hues: [Double]
    let size: CGFloat
    var artworkURL: String? = nil

    var body: some View {
        ZStack {
            procedural
            if let s = artworkURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .transition(.opacity.animation(.easeOut(duration: 0.25)))
                    default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }

    @ViewBuilder
    private var procedural: some View {
        // HSB-based gradient: avoids OKLCH gamut clipping that can render
        // certain hues nearly black, and provides a guaranteed-visible base
        // color when RadialGradients don't fully cover the frame.
        let h0 = hues[0] / 360
        let h1 = hues[1] / 360
        let h2 = hues[2] / 360
        let base = Color(hue: h2, saturation: 0.55, brightness: 0.22)
        ZStack {
            base
            RadialGradient(colors: [
                Color(hue: h0, saturation: 0.72, brightness: 0.95),
                Color(hue: h1, saturation: 0.65, brightness: 0.55),
                base.opacity(0)
            ], center: UnitPoint(x: 0.25, y: 0.2), startRadius: 0, endRadius: size)
            RadialGradient(colors: [
                Color(hue: h2, saturation: 0.65, brightness: 0.78).opacity(0.7),
                .clear
            ], center: UnitPoint(x: 0.85, y: 0.85), startRadius: 0, endRadius: size * 0.7)
        }
    }
}

// MARK: - Now-playing bars

struct NowBars: View {
    let color: Color
    var size: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * 3 + Double(i) * 0.7) * 0.5 + 0.5
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: size * (0.3 + 0.7 * phase))
                }
            }
            .frame(height: size)
        }
    }
}

// MARK: - Karaoke fullscreen backdrop

struct KaraokeBackdrop: View {
    let hues: [Double]
    let tone: FL.Tone
    let palette: FL.Palette
    let reduceMotion: Bool

    /// Base luminance flips with tone — dark = deep ambient depth, light =
    /// airy palette-derived backdrop. Both keep the chromatic blooms tinted
    /// by the track hues so identity reads at a glance.
    private var baseLuminance: Double { tone == .dark ? 0.16 : 0.94 }
    private var bloomALuminance: Double { tone == .dark ? 0.55 : 0.78 }
    private var bloomBLuminance: Double { tone == .dark ? 0.50 : 0.72 }
    private var vignetteOpacity: Double { tone == .dark ? 0.45 : 0.18 }
    private var vignetteTopOpacity: Double { tone == .dark ? 0.25 : 0.10 }

    var body: some View {
        if reduceMotion {
            staticBackdrop
        } else {
            TimelineView(.animation) { ctx in
                animatedBackdrop(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private var staticBackdrop: some View {
        ZStack {
            FL.oklch(baseLuminance, 0.02, hues[2])
            Circle()
                .fill(RadialGradient(colors: [FL.oklch(bloomALuminance, 0.18, hues[0]), .clear],
                      center: .center, startRadius: 0, endRadius: 500))
                .frame(width: 900, height: 900)
                .offset(x: -200, y: -200)
            Circle()
                .fill(RadialGradient(colors: [FL.oklch(bloomBLuminance, 0.17, hues[1]), .clear],
                      center: .center, startRadius: 0, endRadius: 500))
                .frame(width: 900, height: 900)
                .offset(x: 200, y: 200)
            vignette
        }
        .compositingGroup()
        .clipped()
    }

    private func animatedBackdrop(t: TimeInterval) -> some View {
        ZStack {
            FL.oklch(baseLuminance, 0.02, hues[2])
            let dx1 = sin(t * 0.35) * 60
            let dy1 = cos(t * 0.30) * 40
            Circle()
                .fill(RadialGradient(colors: [FL.oklch(bloomALuminance, 0.18, hues[0]), .clear],
                      center: .center, startRadius: 0, endRadius: 500))
                .frame(width: 900, height: 900)
                .offset(x: -200 + dx1, y: -200 + dy1)
                .blur(radius: 40)
            let dx2 = cos(t * 0.40) * 70
            let dy2 = sin(t * 0.25) * 50
            Circle()
                .fill(RadialGradient(colors: [FL.oklch(bloomBLuminance, 0.17, hues[1]), .clear],
                      center: .center, startRadius: 0, endRadius: 500))
                .frame(width: 900, height: 900)
                .offset(x: 200 + dx2, y: 200 + dy2)
                .blur(radius: 60)
            vignette
        }
        .compositingGroup()
        .clipped()
    }

    private var vignette: some View {
        // Light tone uses subtle dark edges; dark tone keeps stronger
        // bottom-heavy depth for foreground contrast.
        LinearGradient(stops: [
            .init(color: .black.opacity(vignetteTopOpacity), location: 0),
            .init(color: .clear, location: 0.3),
            .init(color: .clear, location: 0.7),
            .init(color: .black.opacity(vignetteOpacity), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - FlowLayout (wraps words across lines)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW {
                y += rowH + spacing; x = 0; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            totalW = max(totalW, x)
        }
        return CGSize(width: totalW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        // Two-pass to center each row.
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var rowW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if rowW + s.width > maxW && !rows[rows.count - 1].isEmpty {
                rows.append([]); rowW = 0
            }
            rows[rows.count - 1].append((v, s))
            rowW += s.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let totalW = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            var x = bounds.minX + (maxW - totalW) / 2
            let h = row.map { $0.1.height }.max() ?? 0
            for (v, s) in row {
                v.place(at: CGPoint(x: x, y: y + (h - s.height) / 2),
                        proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += h + spacing
        }
    }
}

// MARK: - Active-line index (kept for backwards compat)

extension LyricLine {
    static func activeIndex(in lines: [LyricLine], at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        if position < lines[0].timestamp { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].timestamp <= position { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

// MARK: - Pill capsule frame reporter

/// Reports the visible capsule's frame in the named coordinate space (which
/// is anchored at the SwiftUI host's contentView origin) to the shared
/// `PillHitTarget`. The controller reads this rect to gate
/// `ignoresMouseEvents` so transparent areas around the capsule pass clicks
/// through to the desktop.
struct PillCapsuleFrameReporter: ViewModifier {
    let space: String
    @ObservedObject var hitTarget: PillHitTarget

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PillCapsuleFramePreferenceKey.self,
                    value: geo.frame(in: .named(space))
                )
            }
        )
        .onPreferenceChange(PillCapsuleFramePreferenceKey.self) { rect in
            Task { @MainActor in
                if hitTarget.capsuleRectInContentView != rect {
                    hitTarget.capsuleRectInContentView = rect
                }
            }
        }
    }
}

private struct PillCapsuleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Visual effect bridge

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
