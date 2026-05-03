import XCTest
@testable import Floric

@MainActor
final class PlaybackControlTests: XCTestCase {

    private func makeNowPlaying(state: PlayerState, position: Double = 30) -> NowPlaying {
        NowPlaying(
            trackId: "spotify:track:test",
            title: "Test", artist: "Artist", album: "Album",
            durationSeconds: 200,
            positionSeconds: position,
            state: state,
            artworkURL: nil
        )
    }

    func test_playPause_whenAvailableAndPlaying_optimisticallyFlipsToPaused() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .available,
                                    nowPlaying: makeNowPlaying(state: .playing))

        monitor.playPause()

        XCTAssertEqual(monitor.nowPlaying?.state, .paused)
    }

    func test_playPause_whenAvailableAndPaused_optimisticallyFlipsToPlaying() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .available,
                                    nowPlaying: makeNowPlaying(state: .paused))

        monitor.playPause()

        XCTAssertEqual(monitor.nowPlaying?.state, .playing)
    }

    func test_playPause_whenNotAvailable_callsErrorWithNotAvailable() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .notRunning, nowPlaying: nil)

        var captured: Error?
        monitor.playPause { err in captured = err }

        XCTAssertEqual(captured as? PlaybackCommandError, .notAvailable)
        XCTAssertNil(monitor.nowPlaying)
    }

    func test_previousTrack_whenNotAvailable_emitsError() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .permissionDenied, nowPlaying: nil)

        var captured: Error?
        monitor.previousTrack { err in captured = err }

        XCTAssertEqual(captured as? PlaybackCommandError, .notAvailable)
    }

    func test_nextTrack_whenNotAvailable_emitsError() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .notInstalled, nowPlaying: nil)

        var captured: Error?
        monitor.nextTrack { err in captured = err }

        XCTAssertEqual(captured as? PlaybackCommandError, .notAvailable)
    }

    func test_seek_whenAvailable_optimisticallyUpdatesPosition() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .available,
                                    nowPlaying: makeNowPlaying(state: .playing,
                                                               position: 12))

        monitor.seek(to: 75)

        XCTAssertEqual(monitor.nowPlaying?.positionSeconds ?? 0, 75, accuracy: 0.01)
    }

    func test_seek_whenAvailableAndNegative_clampsToZero() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .available,
                                    nowPlaying: makeNowPlaying(state: .playing,
                                                               position: 12))

        monitor.seek(to: -5)

        XCTAssertEqual(monitor.nowPlaying?.positionSeconds ?? 99, 0, accuracy: 0.01)
    }

    func test_seek_whenNotAvailable_doesNotMutatePosition() {
        let monitor = SpotifyMonitor()
        monitor._setStateForTesting(availability: .notRunning,
                                    nowPlaying: makeNowPlaying(state: .playing,
                                                               position: 12))

        var captured: Error?
        monitor.seek(to: 100) { err in captured = err }

        XCTAssertEqual(captured as? PlaybackCommandError, .notAvailable)
        XCTAssertEqual(monitor.nowPlaying?.positionSeconds ?? 0, 12, accuracy: 0.01)
    }
}

// MARK: - MockPlaybackSource transport routing

@MainActor
final class MockPlaybackSourceTransportTests: XCTestCase {
    func test_mockPlaybackSource_recordsControlCalls() {
        let mock = MockPlaybackSource()

        mock.playPause(onError: { _ in })
        mock.previousTrack(onError: { _ in })
        mock.nextTrack(onError: { _ in })
        mock.seek(to: 42.5, onError: { _ in })

        XCTAssertEqual(mock.playPauseCalls, 1)
        XCTAssertEqual(mock.previousCalls, 1)
        XCTAssertEqual(mock.nextCalls, 1)
        XCTAssertEqual(mock.seekTargets, [42.5])
    }

    func test_mockPlaybackSource_propagatesInjectedErrorOnce() {
        let mock = MockPlaybackSource()
        mock.nextErrorToInject = PlaybackCommandError.notAvailable

        var first: Error?
        var second: Error?
        mock.playPause { err in first = err }
        mock.playPause { err in second = err }

        XCTAssertEqual(first as? PlaybackCommandError, .notAvailable)
        XCTAssertNil(second)
    }
}
