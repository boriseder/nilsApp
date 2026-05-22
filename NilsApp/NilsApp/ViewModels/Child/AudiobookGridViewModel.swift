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

    private var authCancellable: AnyCancellable?
    private var fetchTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")

    init() {}

    func configure(
        artists: [CuratedArtist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.persistenceService = persistenceService

        if self.apiService !== apiService {
            self.apiService = apiService
            subscribeToAuthorization(apiService)
        }

        guard self.artists != artists else {
            logger.debug("configure() — artist list unchanged, skipping.")
            return
        }
        logger.info("configure() — artist list changed (\(artists.count) artists), resetting.")
        self.artists = artists
        self.albums = []
    }

    private func subscribeToAuthorization(_ apiService: SpotifyAPIService) {
        authCancellable = apiService.$isAuthorized
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.artists.isEmpty else { return }
                guard self.albums.isEmpty && !self.isLoading else { return }
                self.logger.info("isAuthorized flipped true — triggering warm-up fetch.")
                self.fetchAlbums()
            }
    }

    func fetchAlbums(forceRefresh: Bool = false) {
        fetchTask?.cancel()
        fetchTask = Task { await fetchAlbumsAsync(forceRefresh: forceRefresh) }
    }

    func fetchAlbumsAsync(forceRefresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !artists.isEmpty else { return }

        let artistIds = artists.map { $0.id }

        // ── Cache check ────────────────────────────────────────────────────────────
        // On a normal (non-forced) launch, serve the cache immediately if it's valid.
        // The delta fetch below will run on forceRefresh or when cache has expired.
        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            self.albums = cached
            logger.info("Albums served from cache (\(cached.count) items). No API call made.")
            return
        }

        isLoading = true
        errorMessage = nil

        // ── Delta fetch ────────────────────────────────────────────────────────────
        // Pass the known per-artist totals and the existing cached albums so the API
        // service can skip artists whose total hasn't changed and only append new pages.
        let knownTotals     = persistenceService.albumTotalCounts()
        let existingAlbums  = persistenceService.loadAllCachedAlbums()
        do {
            let result = try await apiService.fetchAudiobookAlbums(
                artistIds:      artistIds,
                knownTotals:    knownTotals,
                existingAlbums: existingAlbums
            )
            persistenceService.saveAlbums(result.albums, for: artistIds, totalCounts: result.totalCounts)
            self.albums = result.albums
            logger.info("Delta fetch complete — \(result.albums.count) albums total.")

        } catch let partial as SpotifyAPIService.PartialAlbumsError {
            if !partial.albums.isEmpty {
                // Save what we got with whatever totals we already knew.
                // On next launch the delta will pick up where we left off.
                persistenceService.saveAlbums(partial.albums, for: artistIds, totalCounts: knownTotals)
                self.albums = partial.albums
                logger.warning("Partial fetch: saved \(partial.albums.count) albums before rate-limit.")
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
