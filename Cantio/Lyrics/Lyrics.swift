import Foundation

/// Single time-stamped lyric line. Timestamp is seconds from track start.
struct LyricLine: Equatable, Codable {
    let timestamp: Double
    let text: String
}

/// Result of a lyrics lookup for a track.
enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case notFound
    case error(String)
}
