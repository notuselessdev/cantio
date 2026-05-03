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
    /// Endpoint host. Overridable for tests.
    var endpoint: URL = URL(string: "https://lrclib.net/api/get")!
    var session: URLSession = .shared

    /// LRCLIB recommends a descriptive User-Agent so they can contact maintainers.
    private let userAgent = "Floric/0.1 (+https://github.com/sultans-co/floric)"

    private struct LRCLibResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    /// Looks the track up on LRCLIB. Returns:
    /// - `.synced` when an LRC body is present and parses to >=1 line
    /// - `.plain` when only plain lyrics exist (or LRC parse yields nothing)
    /// - `.notFound` on HTTP 404 or empty body
    /// - `.error(message)` on transport/decoding failures
    func fetch(track: NowPlaying) async -> LyricsState {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return .error("invalid endpoint")
        }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.durationSeconds.rounded())))
        ]
        guard let url = components.url else { return .error("invalid query") }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .error("no response") }
            if http.statusCode == 404 { return .notFound }
            guard (200..<300).contains(http.statusCode) else {
                return .error("HTTP \(http.statusCode)")
            }
            let decoded = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            if let lrc = decoded.syncedLyrics, !lrc.isEmpty {
                let lines = LRCParser.parse(lrc)
                if !lines.isEmpty { return .synced(lines) }
            }
            if let plain = decoded.plainLyrics, !plain.isEmpty {
                return .plain(plain)
            }
            return .notFound
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
