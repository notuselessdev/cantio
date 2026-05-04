import Foundation

/// Parses LRC-formatted text into a sorted array of `LyricLine`.
///
/// Supports:
/// - `[mm:ss]` and `[mm:ss.xx]` / `[mm:ss.xxx]` timestamps
/// - Multiple timestamps on a single line (e.g. repeated chorus)
/// - Bracketed metadata tags like `[ar:Artist]` are skipped
enum LRCParser {
    static func parse(_ source: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for rawLine in source.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            let (stamps, text) = extractTimestamps(from: line)
            guard !stamps.isEmpty else { continue }
            // LRCLIB encodes bilingual lyrics as `original^translation`.
            // Drop the translation half so the floating window doesn't show
            // both languages stacked on the same line.
            let primary = text.split(separator: "^", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map { String($0).trimmingCharacters(in: .whitespaces) }
                ?? text
            for ts in stamps {
                out.append(LyricLine(timestamp: ts, text: primary))
            }
        }
        out.sort { $0.timestamp < $1.timestamp }
        return out
    }

    /// Pulls leading `[mm:ss(.fraction)]` blocks off `line`. Returns the
    /// timestamps in seconds plus the remaining trimmed text. Lines whose only
    /// brackets contain non-numeric metadata (e.g. `[ar:...]`) yield empty stamps.
    private static func extractTimestamps(from line: String) -> ([Double], String) {
        var stamps: [Double] = []
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "[" {
            guard let close = line[idx...].firstIndex(of: "]") else { break }
            let inner = String(line[line.index(after: idx)..<close])
            if let secs = parseTimestamp(inner) {
                stamps.append(secs)
                idx = line.index(after: close)
            } else {
                // Non-timestamp tag: skip it entirely, it's metadata.
                idx = line.index(after: close)
            }
        }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return (stamps, text)
    }

    /// Parses `mm:ss` or `mm:ss.fraction` into seconds. Returns nil otherwise.
    private static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return Double(minutes) * 60 + seconds
    }
}
