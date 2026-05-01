// Child ViewModels Group
import Foundation
import Combine
import os

@MainActor
final class AudiobookGridViewModel: ObservableObject {
    @Published private(set) var albums: [SpotifyAlbum] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private(set) var artists: [CuratedArtist] = []
    private var apiService: SpotifyAPIService?
    private var persistenceService: PersistenceService?

    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")

    init() {}

    func configure(
        artists: [CuratedArtist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.apiService = apiService
        self.persistenceService = persistenceService

        // BUG 1 FIX: compare BEFORE assigning — no isConfigured flag needed.
        guard self.artists != artists else {
            logger.debug("configure() — artist list unchanged, skipping.")
            return
        }
        logger.info("configure() — artist list changed (\(artists.count) artists), resetting.")
        self.artists = artists
        self.albums = []
    }

    func fetchAlbums(forceRefresh: Bool = false) {
        // BUG 2 mitigation: isLoading guard blocks the second concurrent call
        // from HomeView.onAppear + AudiobookGridView.onAppear firing together.
        guard !isLoading else {
            logger.debug("fetchAlbums() — already loading, skipping duplicate call.")
            return
        }
        Task { await fetchAlbumsAsync(forceRefresh: forceRefresh) }
    }

    func fetchAlbumsAsync(forceRefresh: Bool = false) async {
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !artists.isEmpty else { return }

        let artistIds = artists.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            self.albums = cached
            logger.info("Albums served from cache (\(cached.count) items). No API call made.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchAudiobookAlbums(artistIds: artistIds)
            persistenceService.saveAlbums(fetched, for: artistIds)
            self.albums = fetched
            logger.info("Fetched and cached \(fetched.count) albums from Spotify.")

        } catch let partial as SpotifyAPIService.PartialAlbumsError {
            // BUG 3 FIX: Save whatever was collected before surfacing the error.
            // This breaks the infinite rate-limit loop: the next launch gets a
            // cache hit and makes zero API calls until the 24h TTL expires.
            if !partial.albums.isEmpty {
                persistenceService.saveAlbums(partial.albums, for: artistIds)
                self.albums = partial.albums
                logger.warning("Partial fetch: cached \(partial.albums.count) albums before showing rate-limit error.")
            }
            self.errorMessage = partial.retryAfter > 60
                ? "Spotify needs a break. Saved what we found — try again later!"
                : "Spotify needs a break. Try again in \(partial.retryAfter) seconds."

        } catch SpotifyAPIService.APIError.rateLimited(let retryAfter) {
            self.errorMessage = retryAfter > 60
                ? "Spotify needs a break. Try again later!"
                : "Spotify needs a break. Try again in \(retryAfter) seconds."
            logger.error("Rate limited — retryAfter: \(retryAfter)s")

        } catch {
            self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
            logger.error("Failed to fetch albums: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}
