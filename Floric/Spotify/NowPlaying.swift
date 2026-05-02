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
}
