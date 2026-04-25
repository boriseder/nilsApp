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
    private var isConfigured = false

    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")

    init() {}

    func configure(
        playlists: [CuratedPlaylist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        guard !isConfigured || self.playlists != playlists else { return }
        self.playlists = playlists
        self.apiService = apiService
        self.persistenceService = persistenceService
        self.isConfigured = true
        if self.playlists != playlists {
            self.tracks = []
        }
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
            logger.info("Using cached tracks — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchPlaylistTracks(playlistIds: playlistIds)
            persistenceService.saveTracks(fetched, for: playlistIds)
            self.tracks = fetched
            logger.info("Successfully fetched \(fetched.count) total tracks.")
        } catch {
            self.errorMessage = "Failed to load music: \(error.localizedDescription)"
            logger.error("Failed to fetch playlist tracks: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
}
