import Foundation

/// Owns the lyrics state for the currently playing track.
///
/// Subscribes to the monitor's track-change events. For each new track id it
/// checks the on-disk cache first; on miss it calls `LyricsService.fetch`,
/// then writes the result back to cache so subsequent plays are instant.
@MainActor
final class LyricsStore: ObservableObject {
    @Published private(set) var state: LyricsState = .idle
    @Published private(set) var trackId: String?

    private let service: LyricsService
    private let cache: LyricsCache
    private var fetchTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?

    init(service: LyricsService = LyricsService(), cache: LyricsCache = LyricsCache()) {
        self.service = service
        self.cache = cache
    }

    /// Starts listening to the monitor's event stream. Idempotent.
    func bind(to monitor: SpotifyMonitor) {
        guard listenTask == nil else { return }
        let stream = monitor.events
        listenTask = Task { [weak self] in
            for await np in stream {
                await self?.handle(np)
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    private func handle(_ np: NowPlaying?) async {
        guard let np else {
            trackId = nil
            state = .idle
            fetchTask?.cancel()
            return
        }
        // Same track -> nothing to do; position-only updates shouldn't refetch.
        if np.trackId == trackId { return }
        trackId = np.trackId
        fetchTask?.cancel()

        if let entry = cache.load(trackId: np.trackId) {
            state = LyricsCache.state(from: entry)
            return
        }

        state = .loading
        let captured = np
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.fetch(track: captured)
            if Task.isCancelled { return }
            // Late guard: another track may have started while we were fetching.
            if self.trackId != captured.trackId { return }
            self.state = result
            if let entry = LyricsCache.entry(from: result) {
                self.cache.save(entry, trackId: captured.trackId)
            }
        }
    }
}
