// Child ViewModels Group
import Foundation
import Combine
import os

@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published private(set) var tracks: [SpotifyTrack] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private(set) var playlists: [CuratedPlaylist] = []
    private var apiService: SpotifyAPIService?
    private var persistenceService: PersistenceService?

    private var authCancellable: AnyCancellable?

    // FIX #2: Mirror AudiobookGridViewModel — hold a Task handle so we can cancel
    // an in-flight fetch before starting a new one, preventing parallel requests.
    private var fetchTask: Task<Void, Never>?
    /// Absolute date before which we must not hit the Spotify API (rate-limit backoff).
    private var rateLimitedUntil: Date?

    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")

    init() {}

    func configure(
        playlists: [CuratedPlaylist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.persistenceService = persistenceService

        if self.apiService !== apiService {
            self.apiService = apiService
            subscribeToAuthorization(apiService)
        }

        guard self.playlists != playlists else {
            logger.debug("configure() — playlist list unchanged, skipping.")
            return
        }
        logger.info("configure() — playlist list changed, resetting tracks.")
        self.playlists = playlists
        self.tracks = []
    }

    private func subscribeToAuthorization(_ apiService: SpotifyAPIService) {
        authCancellable = apiService.$isAuthorized
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.playlists.isEmpty else { return }
                guard self.tracks.isEmpty && !self.isLoading else { return }
                self.logger.info("isAuthorized flipped true — triggering warm-up fetch.")
                self.fetchTracks()
            }
    }

    func fetchTracks(forceRefresh: Bool = false) {
        // FIX #2: Cancel any in-flight task before launching a new one.
        fetchTask?.cancel()
        fetchTask = Task { await fetchTracksAsync(forceRefresh: forceRefresh) }
    }

    func fetchTracksAsync(forceRefresh: Bool = false) async {
        // FIX #2: Check cancellation before doing any work.
        guard !Task.isCancelled else { return }
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !playlists.isEmpty else { return }

        if let until = rateLimitedUntil, Date() < until {
            let remaining = Int(until.timeIntervalSinceNow)
            logger.warning("Rate-limit backoff active — \(remaining)s remaining. Skipping fetch.")
            return
        }

        let playlistIds = playlists.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadTracks(for: playlistIds) {
            self.tracks = cached
            logger.info("Tracks served from cache (\(cached.count) items).")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchPlaylistTracks(playlistIds: playlistIds)
            persistenceService.saveTracks(fetched, for: playlistIds)
            self.tracks = fetched
            logger.info("Fetched \(fetched.count) tracks from Spotify.")

        } catch let partial as SpotifyAPIService.PartialTracksError {
            if !partial.tracks.isEmpty {
                persistenceService.saveTracks(partial.tracks, for: playlistIds)
                self.tracks = partial.tracks
                logger.warning("Partial fetch: cached \(partial.tracks.count) tracks before showing rate-limit error.")
            }
            rateLimitedUntil = Date().addingTimeInterval(TimeInterval(partial.retryAfter))
            self.errorMessage = partial.retryAfter > 60
                ? "Spotify needs a break. Saved what we found — try again later!"
                : "Spotify needs a break. Try again in \(partial.retryAfter) seconds."

        } catch SpotifyAPIService.APIError.rateLimited(let retryAfter) {
            rateLimitedUntil = Date().addingTimeInterval(TimeInterval(retryAfter))
            self.errorMessage = retryAfter > 60
                ? "Spotify needs a break. Try again later!"
                : "Spotify needs a break. Try again in \(retryAfter) seconds."
            logger.error("Rate limited — retryAfter: \(retryAfter)s")

        } catch {
            self.errorMessage = "Failed to load music: \(error.localizedDescription)"
            logger.error("Failed to fetch tracks: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}
