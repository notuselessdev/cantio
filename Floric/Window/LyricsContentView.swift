import SwiftUI
import AppKit

/// Content rendered inside the floating lyrics window.
///
/// Visual design follows Apple-style polish:
/// - SF Pro typography with proper optical sizing (`.system(size:)` ≥ 20pt
///   automatically promotes to SF Pro Display) and explicit tracking per
///   Apple's typography table (tighter for display, looser for body).
/// - Three appearance modes: Glass (`.ultraThinMaterial` vibrancy), Solid
///   Dark, Solid Light. Glass auto-degrades to solid when the system has
///   Reduce Transparency on.
/// - Hairline (0.5pt @1x) border, continuous corner radius, soft drop shadow.
/// - Spring animations are flattened to fades when Reduce Motion is on.
struct LyricsContentView: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            background
            content
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 280, minHeight: 64)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        // Drop shadow is provided by the host `NSWindow` (`hasShadow = true`),
        // which traces the actual rounded silhouette since the window
        // background is clear. Adding a SwiftUI `.shadow` here would double
        // up with the AppKit shadow and produce a smeared halo.
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Appearance

    /// Force a color scheme for the solid modes so SF Symbol / system colors
    /// inside the window resolve correctly even if the host app is in the
    /// other mode. Glass follows the system.
    private var preferredScheme: ColorScheme? {
        switch effectiveAppearance {
        case .glass: return nil
        case .solidDark: return .dark
        case .solidLight: return .light
        }
    }

    /// When Reduce Transparency is on, glass falls back to a solid mode that
    /// matches the system appearance.
    private var effectiveAppearance: AppearanceMode {
        if prefs.appearanceMode == .glass && reduceTransparency {
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .solidDark
                : .solidLight
        }
        return prefs.appearanceMode
    }

    @ViewBuilder
    private var background: some View {
        switch effectiveAppearance {
        case .glass:
            VisualEffectBackground()
        case .solidDark:
            Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 0.92))
        case .solidLight:
            Color(nsColor: NSColor(calibratedWhite: 0.98, alpha: 0.92))
        }
    }

    private var borderColor: Color {
        switch effectiveAppearance {
        case .glass: return Color.white.opacity(0.14)
        case .solidDark: return Color.white.opacity(0.10)
        case .solidLight: return Color.black.opacity(0.10)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .idle:
            placeholder("—")
        case .loading:
            placeholder("Loading lyrics…")
        case .notFound:
            placeholder("No lyrics found")
        case .error(let msg):
            placeholder(msg)
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .tracking(0.1)
                    .multilineTextAlignment(.center)
            }
        case .synced(let lines):
            // Drives a redraw at ~30 Hz so the active line stays within
            // ±200 ms of Spotify between polls (we extrapolate locally).
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let position = monitor.interpolatedPosition(now: context.date)
                    ?? monitor.nowPlaying?.positionSeconds
                    ?? 0
                let activeIndex = LyricLine.activeIndex(in: lines, at: position)
                syncedView(lines: lines, activeIndex: activeIndex)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .tracking(0.1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func syncedView(lines: [LyricLine], activeIndex: Int?) -> some View {
        switch prefs.displayMode {
        case .singleLine:
            singleLine(lines: lines, activeIndex: activeIndex)
        case .multiLine:
            multiLine(lines: lines, activeIndex: activeIndex)
        }
    }

    @ViewBuilder
    private func singleLine(lines: [LyricLine], activeIndex: Int?) -> some View {
        let text = activeIndex.map { lines[$0].text } ?? "♪"
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 22, weight: .semibold))
            .tracking(-0.26)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .id(activeIndex ?? -1)
            .transition(reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            .animation(activeAnimation, value: activeIndex)
    }

    @ViewBuilder
    private func multiLine(lines: [LyricLine], activeIndex: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 8) {
                    Color.clear.frame(height: 24).id("__top__")
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        lineView(line: line, isActive: idx == activeIndex)
                            .id(idx)
                    }
                    Color.clear.frame(height: 24).id("__bot__")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 180)
            .onChange(of: activeIndex) { _, new in
                guard let target = new else { return }
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .center)
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let target = activeIndex {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(
                size: isActive ? 22 : 14,
                weight: isActive ? .semibold : .regular
            ))
            .tracking(isActive ? -0.26 : 0.1)
            .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.7))
            .scaleEffect(isActive ? 1.0 : 0.96)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(activeAnimation, value: isActive)
    }

    private var activeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.25, dampingFraction: 0.85)
    }
}

extension LyricLine {
    /// Returns index of the line whose timestamp ≤ position < next.timestamp,
    /// or `nil` if `position` precedes the first line.
    static func activeIndex(in lines: [LyricLine], at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        if position < lines[0].timestamp { return nil }
        var lo = 0
        var hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].timestamp <= position {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }
}

/// `NSVisualEffectView` bridge for translucent, vibrant window background.
///
/// Uses `.hudWindow` material which is the closest AppKit equivalent to
/// SwiftUI's `.ultraThinMaterial` for floating HUD-style surfaces and
/// preserves vibrancy through behind-window blending.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
