import SwiftUI

/// Content rendered inside the floating lyrics window.
struct LyricsContentView: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            content
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 280, minHeight: 60)
    }

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
            ScrollView { Text(text).font(.body).multilineTextAlignment(.center) }
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
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .id(activeIndex ?? -1)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: activeIndex)
    }

    @ViewBuilder
    private func multiLine(lines: [LyricLine], activeIndex: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 8) {
                    // Top spacer pushes the first line toward the centre on initial
                    // render so it can scroll up smoothly.
                    Color.clear.frame(height: 24).id("__top__")
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        lineView(line: line, isActive: idx == activeIndex)
                            .id(idx)
                    }
                    Color.clear.frame(height: 24).id("__bot__")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 160)
            .onChange(of: activeIndex) { _, new in
                guard let target = new else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    proxy.scrollTo(target, anchor: .center)
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
                weight: isActive ? .semibold : .regular,
                design: .rounded
            ))
            .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.7))
            .scaleEffect(isActive ? 1.0 : 0.96)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isActive)
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

/// `NSVisualEffectView` bridge for translucent window background.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
