import SwiftUI

/// Content rendered inside the floating lyrics window.
struct LyricsContentView: View {
    @ObservedObject var monitor: SpotifyMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        ZStack {
            // Slight background so the window has a draggable surface and
            // remains visible against light or dark wallpapers. Translucent
            // material works well over any background.
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
            syncedView(lines: lines)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func syncedView(lines: [LyricLine]) -> some View {
        let position = monitor.nowPlaying?.positionSeconds ?? 0
        let activeIndex = LyricLine.activeIndex(in: lines, at: position)
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
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.2), value: activeIndex)
    }

    @ViewBuilder
    private func multiLine(lines: [LyricLine], activeIndex: Int?) -> some View {
        VStack(alignment: .center, spacing: 6) {
            ForEach(contextRange(activeIndex: activeIndex, total: lines.count), id: \.self) { idx in
                let isActive = idx == activeIndex
                Text(lines[idx].text.isEmpty ? "♪" : lines[idx].text)
                    .font(.system(
                        size: isActive ? 20 : 14,
                        weight: isActive ? .semibold : .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeIndex)
    }

    private func contextRange(activeIndex: Int?, total: Int) -> [Int] {
        guard total > 0 else { return [] }
        let center = activeIndex ?? 0
        let lower = max(0, center - 1)
        let upper = min(total - 1, center + 1)
        return Array(lower...upper)
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
