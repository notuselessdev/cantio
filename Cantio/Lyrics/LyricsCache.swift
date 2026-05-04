import Foundation

/// Persists fetched lyrics to disk keyed by Spotify track id, so a re-fetch
/// is never required for a track we've already looked up (including misses).
struct LyricsCache {
    /// Shared instance for UI surfaces that need cache stats/clear.
    static let shared = LyricsCache()

    /// Human-readable summary "<n> songs · <size>" for the Settings pane.
    func summary() -> String {
        let urls = (try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let count = urls.count
        let bytes = urls.reduce(0) { acc, url in
            let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return acc + sz
        }
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useKB, .useMB]
        fmt.countStyle = .file
        return "\(count) songs · \(fmt.string(fromByteCount: Int64(bytes)))"
    }

    /// Removes every cached lyric entry.
    func clear() {
        let urls = (try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)) ?? []
        for u in urls { try? fileManager.removeItem(at: u) }
    }

    /// Codable on-disk shape. `synced` is non-empty for matches; nil means a
    /// negative-cache entry (lookup ran and produced nothing usable).
    /// `plain` is decoded for backward compatibility with old cache files but
    /// never written and never surfaced — un-timestamped lyrics map to
    /// `.notFound` at render time.
    struct Entry: Codable, Equatable {
        var synced: [LyricLine]?
        var plain: String?
    }

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = caches
                .appendingPathComponent("com.mayronalves.cantio", isDirectory: true)
                .appendingPathComponent("lyrics", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func load(trackId: String) -> Entry? {
        let url = fileURL(for: trackId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    func save(_ entry: Entry, trackId: String) {
        let url = fileURL(for: trackId)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Maps a state back into a cache entry. `.loading` / `.idle` / `.error`
    /// are not persisted — we only cache real lookup results.
    static func entry(from state: LyricsState) -> Entry? {
        switch state {
        case .synced(let lines): return Entry(synced: lines, plain: nil)
        case .notFound: return Entry(synced: nil, plain: nil)
        case .idle, .loading, .error: return nil
        }
    }

    /// Maps a cached entry into a state for display. Legacy entries with only
    /// `plain` text (no synced lines) collapse to `.notFound`.
    static func state(from entry: Entry) -> LyricsState {
        if let synced = entry.synced, !synced.isEmpty { return .synced(synced) }
        return .notFound
    }

    private func fileURL(for trackId: String) -> URL {
        directory.appendingPathComponent(sanitize(trackId)).appendingPathExtension("json")
    }

    private func sanitize(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
