import Foundation

enum PlayerState: String, Equatable {
    case playing
    case paused
    case stopped
    case unknown

    init(appleScriptValue raw: String) {
        switch raw.lowercased() {
        case "playing": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: self = .unknown
        }
    }
}

struct NowPlaying: Equatable {
    var trackId: String
    var title: String
    var artist: String
    var album: String
    var durationSeconds: Double
    var positionSeconds: Double
    var state: PlayerState
}

enum SpotifyAvailability: Equatable {
    case available
    case notRunning
    case notInstalled
    /// macOS denied AppleEvents Automation permission for Spotify. The user
    /// must grant access in System Settings → Privacy & Security → Automation.
    case permissionDenied
}

/// Snapshot of the player position at a known wall-clock instant. Used to
/// extrapolate the current position between polls so synced lyrics can stay
/// within ±200 ms of Spotify without polling at high frequency.
struct PositionAnchor: Equatable {
    var position: Double
    var sampledAt: Date
    var isPlaying: Bool
}
