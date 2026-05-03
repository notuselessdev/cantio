import XCTest
@testable import Floric

final class SpotifyParserTests: XCTestCase {
    func test_parse_errNotRunningSentinel_returnsNotRunning() {
        let result = parseSpotifyScriptOutput("ERR_NOT_RUNNING")

        XCTAssertEqual(result, .notRunning)
    }

    func test_parse_errNoTrackSentinel_returnsNotRunning() {
        let result = parseSpotifyScriptOutput("ERR_NO_TRACK")

        XCTAssertEqual(result, .notRunning)
    }

    func test_parse_emptyString_returnsNotRunning() {
        let result = parseSpotifyScriptOutput("")

        XCTAssertEqual(result, .notRunning)
    }

    func test_parse_truncatedOutputBelowSevenFields_returnsNotRunning() {
        let raw = ["playing", "spotify:track:abc", "Title", "Artist"].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        XCTAssertEqual(result, .notRunning)
    }

    func test_parse_validSevenFieldOutput_populatesNowPlayingWithoutArtwork() {
        let raw = [
            "playing",
            "spotify:track:abc123",
            "Bohemian Rhapsody",
            "Queen",
            "A Night at the Opera",
            "42.5",
            "354000",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        let expected = NowPlaying(
            trackId: "spotify:track:abc123",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354.0,
            positionSeconds: 42.5,
            state: .playing,
            artworkURL: nil
        )
        XCTAssertEqual(result, .running(expected))
    }

    func test_parse_validEightFieldOutputWithArtwork_setsArtworkURL() {
        let raw = [
            "playing",
            "spotify:track:abc",
            "Title",
            "Artist",
            "Album",
            "10",
            "200000",
            "https://i.scdn.co/image/abc.jpg",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running, got \(result)")
        }
        XCTAssertEqual(np.artworkURL, "https://i.scdn.co/image/abc.jpg")
    }

    func test_parse_eightFieldOutputWithEmptyArtwork_artworkURLIsNil() {
        let raw = [
            "playing",
            "spotify:track:abc",
            "Title",
            "Artist",
            "Album",
            "10",
            "200000",
            "",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running, got \(result)")
        }
        XCTAssertNil(np.artworkURL)
    }

    func test_parse_durationInMilliseconds_dividedByThousand() {
        let raw = [
            "playing", "id", "t", "a", "al", "0", "200000",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.durationSeconds, 200.0, accuracy: 0.0001)
    }

    func test_parse_durationAlreadyInSeconds_keptAsIs() {
        let raw = [
            "playing", "id", "t", "a", "al", "0", "200",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.durationSeconds, 200.0, accuracy: 0.0001)
    }

    func test_parse_statePlaying_mapsToPlaying() {
        let raw = ["playing", "id", "t", "a", "al", "0", "100"].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.state, .playing)
    }

    func test_parse_statePaused_mapsToPaused() {
        let raw = ["paused", "id", "t", "a", "al", "0", "100"].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.state, .paused)
    }

    func test_parse_stateStopped_mapsToStopped() {
        let raw = ["stopped", "id", "t", "a", "al", "0", "100"].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.state, .stopped)
    }

    func test_parse_unknownStateString_mapsToUnknown() {
        let raw = ["weirdstate", "id", "t", "a", "al", "0", "100"].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.state, .unknown)
    }

    func test_parse_positionWithSurroundingWhitespace_parsesAsNumber() {
        let raw = [
            "playing", "id", "t", "a", "al", "  42.5  ", "  200000  ",
        ].joined(separator: "\n")

        let result = parseSpotifyScriptOutput(raw)

        guard case .running(let np) = result else {
            return XCTFail("expected .running")
        }
        XCTAssertEqual(np.positionSeconds, 42.5, accuracy: 0.0001)
        XCTAssertEqual(np.durationSeconds, 200.0, accuracy: 0.0001)
    }
}
