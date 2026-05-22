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
    /// Absolute date before which we must not hit the Spotify API (rate-limit backoff).
    private var rateLimitedUntil: Date?

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

        // If already authorized, kick off a fetch immediately.
        // subscribeToAuthorization only fires on the isAuthorized transition,
        // so it won't fire again if auth was already true when configure() is called.
        if apiService.isAuthorized {
            fetchAlbums()
        }
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

        // Respect rate-limit backoff — never hammer Spotify while banned.
        if let until = rateLimitedUntil, Date() < until {
            let remaining = Int(until.timeIntervalSinceNow)
            logger.warning("Rate-limit backoff active — \(remaining)s remaining. Skipping fetch.")
            // Show cached data if available, otherwise keep existing error message.
            if albums.isEmpty, let cached = persistenceService.loadAlbums(for: artists.map(\.id)) {
                self.albums = cached.filter { Set(artists.map(\.id)).contains($0.artistId) }
            }
            return
        }

        let artistIds = artists.map { $0.id }

        // ── Cache check ────────────────────────────────────────────────────────────
        // On a normal (non-forced) launch, serve the cache immediately if it's valid.
        // The delta fetch below will run on forceRefresh or when cache has expired.
        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            // Guard against stale cache entries that predate the artistId field.
            let artistIdSet = Set(artistIds)
            let filtered = cached.filter { artistIdSet.contains($0.artistId) }
            self.albums = filtered
            logger.info("Albums served from cache (\(filtered.count) items). No API call made.")
            return
        }

        isLoading = true
        errorMessage = nil

        // ── Delta fetch ────────────────────────────────────────────────────────────
        // Pass the known per-artist totals and the existing cached albums so the API
        // service can skip artists whose total hasn't changed and only append new pages.
        // Filter existingAlbums to only the requested artists so the merge in the API
        // service never bleeds albums from other artists into this view's result.
        let artistIdSet     = Set(artistIds)
        let knownTotals     = persistenceService.albumTotalCounts()
        let existingAlbums  = persistenceService.loadAllCachedAlbums()
            .filter { artistIdSet.contains($0.artistId) }
        do {
            let result = try await apiService.fetchAudiobookAlbums(
                artistIds:      artistIds,
                knownTotals:    knownTotals,
                existingAlbums: existingAlbums
            )
            // Filter result to only this view's artists before saving and displaying.
            let filtered = result.albums.filter { artistIdSet.contains($0.artistId) }
            persistenceService.saveAlbums(filtered, for: artistIds, totalCounts: result.totalCounts)
            self.albums = filtered
            logger.info("Delta fetch complete — \(filtered.count) albums total.")

        } catch let partial as SpotifyAPIService.PartialAlbumsError {
            if !partial.albums.isEmpty {
                // Save what we got with whatever totals we already knew.
                // On next launch the delta will pick up where we left off.
                let filtered = partial.albums.filter { artistIdSet.contains($0.artistId) }
                persistenceService.saveAlbums(filtered, for: artistIds, totalCounts: knownTotals)
                self.albums = filtered
                logger.warning("Partial fetch: saved \(filtered.count) albums before rate-limit.")
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
            self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
            logger.error("Failed to fetch albums: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}
