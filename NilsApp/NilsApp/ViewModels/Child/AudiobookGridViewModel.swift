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

    // Holds the isAuthorized subscription so it lives as long as the ViewModel.
    // Stored here (not in a Set) so configure() can replace it cleanly when
    // called again with a new apiService reference.
    private var authCancellable: AnyCancellable?

    // FIX #2: Statt nur isLoading zu prüfen (was bei sehr schnellen Re-Renders
    // noch false sein kann), halten wir den laufenden Task als Handle.
    // cancel() vor dem neuen Start stellt sicher, dass nie zwei Tasks parallel laufen.
    private var fetchTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")

    init() {}

    func configure(
        artists: [CuratedArtist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.persistenceService = persistenceService

        // Re-subscribe whenever the apiService reference changes (rare, but correct).
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

    /// Observes `isAuthorized` and fires a fetch the moment the token becomes
    /// valid, but only when:
    ///   • there are artists to fetch for (ViewModel is configured), and
    ///   • we have no data yet (avoids redundant network calls when the user
    ///     navigates back to a screen that already has albums loaded).
    private func subscribeToAuthorization(_ apiService: SpotifyAPIService) {
        authCancellable = apiService.$isAuthorized
            .filter { $0 }                          // only the true transition
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.artists.isEmpty else { return }
                guard self.albums.isEmpty && !self.isLoading else { return }
                self.logger.info("isAuthorized flipped true — triggering warm-up fetch.")
                self.fetchAlbums()
            }
    }

    func fetchAlbums(forceRefresh: Bool = false) {
        // FIX #2: Laufenden Task canceln bevor ein neuer startet — verhindert parallele
        // Fetches auch wenn isLoading noch false ist (z.B. bei schnellem View-Re-Render).
        fetchTask?.cancel()
        fetchTask = Task { await fetchAlbumsAsync(forceRefresh: forceRefresh) }
    }

    func fetchAlbumsAsync(forceRefresh: Bool = false) async {
        // FIX #2: Frühzeitig abbrechen wenn der Task bereits gecancelt wurde,
        // bevor er überhaupt zur API-Abfrage kommt.
        guard !Task.isCancelled else { return }
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
