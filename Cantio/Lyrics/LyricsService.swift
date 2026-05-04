import Foundation

/// Anything that can produce lyrics for a track. Real impl: `LyricsService`
/// (LRCLIB). Test impl: in-memory stubs.
protocol LyricsProvider {
    func fetch(track: NowPlaying) async -> LyricsState
}

/// Fetches lyrics from LRCLIB (https://lrclib.net), a free public lyrics API
/// that returns LRC-formatted synced lyrics plus a plain-text fallback.
///
/// We pick LRCLIB because:
/// - No API key, no auth, no rate-limited token endpoint.
/// - It serves real LRC text (not a proprietary positional format).
/// - Plain lyrics are returned alongside synced ones, so the fallback rule
///   in this story is satisfied with a single request.
struct LyricsService: LyricsProvider {
    /// Primary lookup endpoint (exact match on track/artist/album/duration).
    /// Overridable for tests.
    var endpoint: URL = URL(string: "https://lrclib.net/api/get")!
    /// Search endpoint (fuzzy match on track + artist). Used as a fallback
    /// when `/api/get` returns plain lyrics only — multiple uploads can
    /// exist for the same song and a different one may carry timestamps.
    var searchEndpoint: URL = URL(string: "https://lrclib.net/api/search")!
    var session: URLSession = .shared

    /// LRCLIB recommends a descriptive User-Agent so they can contact maintainers.
    private let userAgent = "Cantio/0.1 (+https://github.com/sultans-co/cantio)"

    private struct LRCLibResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private struct LRCLibSearchHit: Decodable {
        let syncedLyrics: String?
    }

    /// Looks the track up on LRCLIB. Returns:
    /// - `.synced` when an LRC body is present and parses to >=1 line
    /// - `.plain` when only plain lyrics exist (or LRC parse yields nothing)
    /// - `.notFound` on HTTP 404 or empty body
    /// - `.error(message)` on transport/decoding failures
    func fetch(track: NowPlaying) async -> LyricsState {
        if let lines = await primaryGet(track: track) {
            return .synced(lines)
        }
        // /api/get returned plain-only, timed out, or errored. Many tracks
        // have multiple LRCLIB uploads — try /api/search and pick the first
        // hit with usable synced lyrics before giving up.
        if let lines = await searchForSyncedLines(track: track) {
            return .synced(lines)
        }
        // Plain (un-timestamped) lyrics are surfaced as not-found — there's
        // no useful way to display them in a karaoke pill.
        return .notFound
    }

    /// Hits /api/get and returns synced lines on success. Network failures,
    /// 4xx/5xx, and plain-only bodies all collapse to nil so the caller can
    /// retry via /api/search rather than surfacing a transient error.
    private func primaryGet(track: NowPlaying) async -> [LyricLine]? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.durationSeconds.rounded())))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            return validSyncedLines(decoded.syncedLyrics)
        } catch {
            return nil
        }
    }

    /// Parses an LRC body and rejects placeholder timestamps (all-identical or
    /// span < 1s). Returns nil when the body is unusable.
    private func validSyncedLines(_ lrc: String?) -> [LyricLine]? {
        guard let lrc, !lrc.isEmpty else { return nil }
        let lines = LRCParser.parse(lrc)
        let stamps = lines.map { $0.timestamp }
        guard Set(stamps).count > 1,
              let first = stamps.first, let last = stamps.last,
              last - first > 1 else { return nil }
        return lines
    }

    /// Falls back to /api/search when /api/get can't supply synced lyrics.
    /// Runs every query variant in parallel and returns the first one to
    /// produce a usable synced body — sequential fallback was too slow when
    /// the strictest pass needed a 5-10s timeout to fail.
    ///
    /// Variants tried (looser → broader):
    ///   1. track + artist + album        (most precise)
    ///   2. track + artist                (typical re-uploads)
    ///   3. track                         (broad — last specific filter)
    ///   4. `q=track artist album`        (full-text fallback; surfaces hits
    ///      whose uploader stuffed placeholders into the per-field metadata)
    private func searchForSyncedLines(track: NowPlaying) async -> [LyricLine]? {
        let title = track.title.trimmingCharacters(in: .whitespaces)
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        let album = track.album.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var variants: [[(String, String)]] = []
        if !artist.isEmpty, !album.isEmpty {
            variants.append([("track_name", title), ("artist_name", artist), ("album_name", album)])
        }
        if !artist.isEmpty {
            variants.append([("track_name", title), ("artist_name", artist)])
        }
        variants.append([("track_name", title)])
        let qParts = [title, artist, album].filter { !$0.isEmpty }
        variants.append([("q", qParts.joined(separator: " "))])

        return await withTaskGroup(of: [LyricLine]?.self, returning: [LyricLine]?.self) { group in
            for fields in variants {
                group.addTask { await self.searchPass(fields: fields) }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func searchPass(fields: [(String, String)]) async -> [LyricLine]? {
        guard var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            let hits = try JSONDecoder().decode([LRCLibSearchHit].self, from: data)
            for hit in hits {
                if let lines = validSyncedLines(hit.syncedLyrics) { return lines }
            }
            return nil
        } catch {
            return nil
        }
    }
}
