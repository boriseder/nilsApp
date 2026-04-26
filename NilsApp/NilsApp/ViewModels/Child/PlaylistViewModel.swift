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

    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")

    init() {}

    func configure(
        playlists: [CuratedPlaylist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.apiService = apiService
        self.persistenceService = persistenceService

        // BUG 1 FIX: same pattern as AudiobookGridViewModel — compare before assigning.
        guard self.playlists != playlists else {
            logger.debug("configure() — playlist list unchanged, skipping.")
            return
        }

        logger.info("configure() — playlist list changed, resetting tracks.")
        self.playlists = playlists
        self.tracks = []
    }

    func fetchTracks(forceRefresh: Bool = false) {
        guard !isLoading else { return }
        Task { await fetchTracksAsync(forceRefresh: forceRefresh) }
    }

    func fetchTracksAsync(forceRefresh: Bool = false) async {
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !playlists.isEmpty else { return }

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
        } catch SpotifyAPIService.APIError.rateLimited(let retryAfter) {
            self.errorMessage = retryAfter > 60
                ? "Spotify needs a break. Try again a little later!"
                : "Spotify needs a break. Try again in \(retryAfter) seconds."
            logger.error("Rate limited — retryAfter: \(retryAfter)s")
        } catch {
            self.errorMessage = "Failed to load music: \(error.localizedDescription)"
            logger.error("Failed to fetch tracks: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
}
