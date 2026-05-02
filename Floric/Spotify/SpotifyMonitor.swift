import AppKit
import Foundation

private let spotifyBundleId = "com.spotify.client"

private let nowPlayingScriptSource = """
tell application id "com.spotify.client"
    if it is running then
        try
            set _state to player state as text
            set _pos to player position
            set t to current track
            set _id to id of t
            set _name to name of t
            set _artist to artist of t
            set _album to album of t
            set _dur to duration of t
            return _state & linefeed & _id & linefeed & _name & linefeed & _artist & linefeed & _album & linefeed & (_pos as text) & linefeed & (_dur as text)
        on error
            return "ERR_NO_TRACK"
        end try
    else
        return "ERR_NOT_RUNNING"
    end if
end tell
"""

/// Observes the local Spotify desktop app via AppleScript.
/// Polls at ~500 ms while playing, ~2 s while paused, ~5 s when not running.
@MainActor
final class SpotifyMonitor: ObservableObject {
    @Published private(set) var availability: SpotifyAvailability = .notRunning
    @Published private(set) var nowPlaying: NowPlaying?
    /// Anchor used to extrapolate the current playback position between polls.
    /// Updated whenever a fresh poll arrives.
    @Published private(set) var positionAnchor: PositionAnchor?

    private var task: Task<Void, Never>?
    private var script: NSAppleScript?
    private var lastEmitted: NowPlaying?

    private let playingInterval: UInt64 = 500_000_000      // 500 ms
    private let pausedInterval: UInt64 = 2_000_000_000     // 2 s
    private let idleInterval: UInt64 = 5_000_000_000       // 5 s

    /// AsyncStream of change events. Emits initial value plus every distinct update.
    let events: AsyncStream<NowPlaying?>
    private let eventsContinuation: AsyncStream<NowPlaying?>.Continuation

    init() {
        var cont: AsyncStream<NowPlaying?>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.eventsContinuation = cont
        self.script = NSAppleScript(source: nowPlayingScriptSource)
    }

    deinit {
        eventsContinuation.finish()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        eventsContinuation.finish()
    }

    private func loop() async {
        while !Task.isCancelled {
            let snapshot = await poll()
            apply(snapshot)
            let delay: UInt64
            switch (availability, nowPlaying?.state) {
            case (.available, .playing): delay = playingInterval
            case (.available, _): delay = pausedInterval
            default: delay = idleInterval
            }
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    private func apply(_ result: PollResult) {
        switch result {
        case .notInstalled:
            if availability != .notInstalled { availability = .notInstalled }
            if nowPlaying != nil { nowPlaying = nil }
            if positionAnchor != nil { positionAnchor = nil }
            emitIfChanged(nil)
        case .notRunning:
            if availability != .notRunning { availability = .notRunning }
            if nowPlaying != nil { nowPlaying = nil }
            if positionAnchor != nil { positionAnchor = nil }
            emitIfChanged(nil)
        case .running(let np):
            if availability != .available { availability = .available }
            if nowPlaying != np { nowPlaying = np }
            updateAnchor(for: np)
            emitIfChanged(np)
        }
    }

    /// Re-anchors playback position. Called on every poll so UI extrapolation
    /// stays within Spotify's reported truth (±poll-jitter, ~tens of ms).
    private func updateAnchor(for np: NowPlaying) {
        positionAnchor = PositionAnchor(
            position: np.positionSeconds,
            sampledAt: Date(),
            isPlaying: np.state == .playing
        )
    }

    /// Returns the extrapolated playback position at `now`, advancing only
    /// while the player is in the `playing` state.
    func interpolatedPosition(now: Date = Date()) -> Double? {
        guard let anchor = positionAnchor else { return nil }
        guard anchor.isPlaying else { return anchor.position }
        let delta = now.timeIntervalSince(anchor.sampledAt)
        return anchor.position + max(0, delta)
    }

    private func emitIfChanged(_ value: NowPlaying?) {
        if value != lastEmitted {
            lastEmitted = value
            eventsContinuation.yield(value)
        }
    }

    // MARK: - Polling

    private enum PollResult {
        case notInstalled
        case notRunning
        case running(NowPlaying)
    }

    private func poll() async -> PollResult {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleId) == nil {
            return .notInstalled
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleId).isEmpty {
            return .notRunning
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runScript(self.script))
            }
        }
    }

    private static func runScript(_ script: NSAppleScript?) -> PollResult {
        guard let script else { return .notRunning }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return .notRunning }
        guard let raw = descriptor.stringValue else { return .notRunning }
        if raw == "ERR_NOT_RUNNING" { return .notRunning }
        if raw == "ERR_NO_TRACK" { return .notRunning }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 7 else { return .notRunning }
        let posSeconds = Double(parts[5].trimmingCharacters(in: .whitespaces)) ?? 0
        let durRaw = Double(parts[6].trimmingCharacters(in: .whitespaces)) ?? 0
        // Spotify reports `duration` in milliseconds.
        let durSeconds = durRaw > 1_000 ? durRaw / 1_000.0 : durRaw
        let np = NowPlaying(
            trackId: parts[1],
            title: parts[2],
            artist: parts[3],
            album: parts[4],
            durationSeconds: durSeconds,
            positionSeconds: posSeconds,
            state: PlayerState(appleScriptValue: parts[0])
        )
        return .running(np)
    }
}
