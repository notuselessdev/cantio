import Foundation

/// Persists fetched lyrics to disk keyed by Spotify track id, so a re-fetch
/// is never required for a track we've already looked up (including misses).
struct LyricsCache {
    /// Codable on-disk shape. Either `synced` is non-empty, `plain` is non-nil,
    /// or both are absent (meaning: lookup was performed and nothing exists).
    struct Entry: Codable, Equatable {
        var synced: [LyricLine]?
        var plain: String?
    }

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = caches
            .appendingPathComponent("co.sultans.floric", isDirectory: true)
            .appendingPathComponent("lyrics", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
        case .plain(let text): return Entry(synced: nil, plain: text)
        case .notFound: return Entry(synced: nil, plain: nil)
        case .idle, .loading, .error: return nil
        }
    }

    /// Maps a cached entry into a state for display.
    static func state(from entry: Entry) -> LyricsState {
        if let synced = entry.synced, !synced.isEmpty { return .synced(synced) }
        if let plain = entry.plain, !plain.isEmpty { return .plain(plain) }
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
