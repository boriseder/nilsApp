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

    /// Called from HomeView.onAppear and whenever curatedContent changes.
    /// Safe to call repeatedly — only resets state if the artist list actually changed.
    func configure(
        artists: [CuratedArtist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        // Always refresh service references (they are stable singletons).
        self.apiService = apiService
        self.persistenceService = persistenceService

        // BUG 1 FIX: The old guard used an `isConfigured` boolean flag that was set
        // to `true` after the first call, making every subsequent call a no-op.
        //
        // The consequences:
        //   a) self.artists was never updated when the parent added/removed a series,
        //      so the wrong artist IDs were used as the cache key forever.
        //   b) The cache-invalidation branch `if self.artists != artists { albums = [] }`
        //      was unreachable because it ran AFTER `self.artists = artists`, making
        //      the comparison always false.
        //
        // Fix: compare the INCOMING artists against the CURRENT self.artists BEFORE
        // assigning. Skip only when they are truly equal. No external flag needed.
        guard self.artists != artists else {
            logger.debug("configure() — artist list unchanged, skipping.")
            return
        }

        logger.info("configure() — artist list changed (\(artists.count) artists), resetting.")
        self.artists = artists
        // Clear stale albums immediately so the UI shows the loading state for the
        // new artist set rather than stale data from the previous one.
        self.albums = []
    }

    // MARK: - Fetch

    func fetchAlbums(forceRefresh: Bool = false) {
        // isLoading guard prevents the duplicate-call race described in BUG 2.
        // HomeView.onAppear and AudiobookGridView.onAppear both call this method
        // in the same run-loop pass on first launch; only the first call proceeds.
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

        // Cache check — returns nil if: file missing, ids changed, or age > 24 h.
        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            self.albums = cached
            logger.info("Albums served from cache (\(cached.count) items). No API call made.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchAudiobookAlbums(artistIds: artistIds)
            // Full success — cache everything.
            persistenceService.saveAlbums(fetched, for: artistIds)
            self.albums = fetched
            logger.info("Fetched and cached \(fetched.count) albums from Spotify.")

        } catch let partial as SpotifyAPIService.PartialResultError {
            // BUG 3 FIX: Spotify returned a very long Retry-After (e.g. 85,000 s).
            //
            // The old code threw and discarded all fetched albums, leaving the cache
            // empty. On the next launch the app made the same requests, got blocked
            // again, and discarded again — a permanent rate-limit loop.
            //
            // Now: save whatever albums were collected BEFORE surfacing the error.
            // The next launch gets a cache hit and never touches the API until the
            // 24-hour TTL expires, by which time the rate limit will have lifted.
            if !partial.albums.isEmpty {
                persistenceService.saveAlbums(partial.albums, for: artistIds)
                self.albums = partial.albums
                logger.warning("Partial fetch: saved \(partial.albums.count) albums to cache before showing rate-limit error.")
            }

            let wait = partial.retryAfter
            self.errorMessage = wait > 60
                ? "Spotify needs a break. Saved what we found — try again later!"
                : "Spotify needs a break. Try again in \(wait) seconds."

        } catch SpotifyAPIService.APIError.rateLimited(let retryAfter) {
            // Generic rate limit (no partial results available).
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
