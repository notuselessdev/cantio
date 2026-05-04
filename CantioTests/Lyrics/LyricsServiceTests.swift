import XCTest
@testable import Cantio

final class LyricsServiceTests: XCTestCase {
    private var endpoint: URL!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        endpoint = URL(string: "https://test.invalid/api/get")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self] + (cfg.protocolClasses ?? [])
        session = URLSession(configuration: cfg)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        session.invalidateAndCancel()
        session = nil
        endpoint = nil
        super.tearDown()
    }

    private func makeTrack() -> NowPlaying {
        NowPlaying(
            trackId: "spotify:track:abc",
            title: "Title",
            artist: "Artist",
            album: "Album",
            durationSeconds: 213.6,
            positionSeconds: 0,
            state: .playing,
            artworkURL: nil
        )
    }

    private func okResponse(body: String) -> (HTTPURLResponse, Data) {
        let resp = HTTPURLResponse(url: endpoint, statusCode: 200,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        return (resp, Data(body.utf8))
    }

    private func statusResponse(_ code: Int) -> (HTTPURLResponse, Data) {
        let resp = HTTPURLResponse(url: endpoint, statusCode: code,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        return (resp, Data())
    }

    func test_fetch_synced_returnsSyncedState() async {
        URLProtocolStub.requestHandler = { [self] _ in
            okResponse(body: #"{"syncedLyrics":"[00:01.00]hi\n[00:03.50]world","plainLyrics":null}"#)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        guard case .synced(let lines) = state else {
            return XCTFail("expected .synced, got \(state)")
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first?.text, "hi")
    }

    func test_fetch_plainOnly_returnsNotFound() async {
        // Un-timestamped lyrics aren't useful for a karaoke pill; treat
        // them the same as a hard miss.
        URLProtocolStub.requestHandler = { [self] _ in
            okResponse(body: #"{"syncedLyrics":null,"plainLyrics":"hello"}"#)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_syncedEmptyParse_returnsNotFound() async {
        URLProtocolStub.requestHandler = { [self] _ in
            okResponse(body: #"{"syncedLyrics":"   ","plainLyrics":"fallback"}"#)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_bothEmpty_returnsNotFound() async {
        URLProtocolStub.requestHandler = { [self] _ in
            okResponse(body: #"{"syncedLyrics":null,"plainLyrics":null}"#)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_404_returnsNotFound() async {
        URLProtocolStub.requestHandler = { [self] _ in statusResponse(404) }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_500_collapsesToNotFound() async {
        // /api/get and the search fallback both return 500 → no synced
        // lyrics anywhere → .notFound. We don't surface a transient
        // server error in the karaoke UI; the user can hit "Reload lyrics".
        URLProtocolStub.requestHandler = { [self] _ in statusResponse(500) }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_transportError_collapsesToNotFound() async {
        URLProtocolStub.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        let state = await service.fetch(track: makeTrack())

        XCTAssertEqual(state, .notFound)
    }

    func test_fetch_request_includesUserAgentAndQueryItems() async {
        // Capture the /api/get request specifically. A successful synced
        // response keeps the search fallback from firing, so the captured
        // request is unambiguously the primary GET.
        let captured = CapturedRequest()
        URLProtocolStub.requestHandler = { [self] request in
            captured.request = request
            return okResponse(body: #"{"syncedLyrics":"[00:01.00]hi\n[00:03.50]bye","plainLyrics":null}"#)
        }
        let service = LyricsService(endpoint: endpoint, session: session)

        _ = await service.fetch(track: makeTrack())

        let request = try? XCTUnwrap(captured.request)
        XCTAssertNotNil(request?.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertFalse(request?.value(forHTTPHeaderField: "User-Agent")?.isEmpty ?? true)

        let url = request?.url
        let comps = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["track_name"], "Title")
        XCTAssertEqual(dict["artist_name"], "Artist")
        XCTAssertEqual(dict["album_name"], "Album")
        XCTAssertEqual(dict["duration"], "214")
    }
}

// MARK: - Helpers

private final class CapturedRequest {
    var request: URLRequest?
}

final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolStub.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
