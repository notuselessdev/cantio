import XCTest
@testable import Floric

final class LyricsCacheTests: XCTestCase {
    private var tempDir: URL!
    private var cache: LyricsCache!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("floric-cache-tests-\(UUID().uuidString)",
                                    isDirectory: true)
        cache = LyricsCache(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_save_thenLoad_roundTripsSyncedEntry() {
        let entry = LyricsCache.Entry(
            synced: [LyricLine(timestamp: 1, text: "a"),
                     LyricLine(timestamp: 2, text: "b")],
            plain: nil
        )

        cache.save(entry, trackId: "id-1")
        let loaded = cache.load(trackId: "id-1")

        XCTAssertEqual(loaded, entry)
    }

    func test_save_thenLoad_roundTripsPlainEntry() {
        let entry = LyricsCache.Entry(synced: nil, plain: "lorem ipsum")

        cache.save(entry, trackId: "id-2")
        let loaded = cache.load(trackId: "id-2")

        XCTAssertEqual(loaded, entry)
    }

    func test_load_unknownTrack_returnsNil() {
        XCTAssertNil(cache.load(trackId: "missing"))
    }

    func test_save_overwritesExistingEntry() {
        let first = LyricsCache.Entry(synced: nil, plain: "first")
        let second = LyricsCache.Entry(synced: nil, plain: "second")

        cache.save(first, trackId: "id-3")
        cache.save(second, trackId: "id-3")

        XCTAssertEqual(cache.load(trackId: "id-3"), second)
    }

    func test_save_keysWithSlashOrColon_sanitizeAndRoundTrip() {
        let id = "weird/track:colon"
        let entry = LyricsCache.Entry(synced: nil, plain: "x")

        cache.save(entry, trackId: id)

        XCTAssertEqual(cache.load(trackId: id), entry)
    }

    func test_clear_removesAllEntries() {
        cache.save(.init(synced: nil, plain: "a"), trackId: "id-a")
        cache.save(.init(synced: nil, plain: "b"), trackId: "id-b")

        cache.clear()

        XCTAssertNil(cache.load(trackId: "id-a"))
        XCTAssertNil(cache.load(trackId: "id-b"))
    }

    func test_summary_emptyCache_returnsZero() {
        let s = cache.summary()

        XCTAssertTrue(s.hasPrefix("0 songs"))
    }

    func test_summary_afterSave_reportsCount() {
        cache.save(.init(synced: nil, plain: "x"), trackId: "id-x")

        let s = cache.summary()

        XCTAssertTrue(s.hasPrefix("1 songs"))
    }

    func test_entryFromState_synced_returnsSyncedEntry() {
        let lines = [LyricLine(timestamp: 0, text: "a")]

        let e = LyricsCache.entry(from: .synced(lines))

        XCTAssertEqual(e, LyricsCache.Entry(synced: lines, plain: nil))
    }

    func test_entryFromState_plain_returnsPlainEntry() {
        let e = LyricsCache.entry(from: .plain("hi"))

        XCTAssertEqual(e, LyricsCache.Entry(synced: nil, plain: "hi"))
    }

    func test_entryFromState_notFound_returnsEmptyEntry() {
        let e = LyricsCache.entry(from: .notFound)

        XCTAssertEqual(e, LyricsCache.Entry(synced: nil, plain: nil))
    }

    func test_entryFromState_idleLoadingError_returnsNil() {
        XCTAssertNil(LyricsCache.entry(from: .idle))
        XCTAssertNil(LyricsCache.entry(from: .loading))
        XCTAssertNil(LyricsCache.entry(from: .error("x")))
    }

    func test_stateFromEntry_emptySynced_returnsNotFound() {
        let e = LyricsCache.Entry(synced: [], plain: nil)

        XCTAssertEqual(LyricsCache.state(from: e), .notFound)
    }

    func test_stateFromEntry_nonEmptySynced_returnsSynced() {
        let lines = [LyricLine(timestamp: 0, text: "a")]
        let e = LyricsCache.Entry(synced: lines, plain: nil)

        XCTAssertEqual(LyricsCache.state(from: e), .synced(lines))
    }

    func test_stateFromEntry_plainOnly_returnsPlain() {
        let e = LyricsCache.Entry(synced: nil, plain: "hi")

        XCTAssertEqual(LyricsCache.state(from: e), .plain("hi"))
    }

    func test_stateFromEntry_allEmpty_returnsNotFound() {
        let e = LyricsCache.Entry(synced: nil, plain: nil)

        XCTAssertEqual(LyricsCache.state(from: e), .notFound)
    }
}
