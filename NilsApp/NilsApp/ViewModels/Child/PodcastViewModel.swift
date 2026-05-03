// Child ViewModels Group
import Foundation
import Combine
import os

@MainActor
final class PodcastViewModel: ObservableObject {
    @Published private(set) var episodes: [SpotifyEpisode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private(set) var shows: [CuratedShow] = []
    private var apiService: SpotifyAPIService?
    private var persistenceService: PersistenceService?

    private var authCancellable: AnyCancellable?

    private let logger = Logger(subsystem: "com.nilsapp", category: "PodcastViewModel")

    init() {}

    func configure(
        shows: [CuratedShow],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        self.persistenceService = persistenceService

        if self.apiService !== apiService {
            self.apiService = apiService
            subscribeToAuthorization(apiService)
        }

        guard self.shows != shows else {
            logger.debug("configure() — show list unchanged, skipping.")
            return
        }
        logger.info("configure() — show list changed, resetting episodes.")
        self.shows = shows
        self.episodes = []
    }

    private func subscribeToAuthorization(_ apiService: SpotifyAPIService) {
        authCancellable = apiService.$isAuthorized
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.shows.isEmpty else { return }
                guard self.episodes.isEmpty && !self.isLoading else { return }
                self.logger.info("isAuthorized flipped true — triggering warm-up fetch.")
                self.fetchEpisodes()
            }
    }

    func fetchEpisodes(forceRefresh: Bool = false) {
        guard !isLoading else { return }
        Task { await fetchEpisodesAsync(forceRefresh: forceRefresh) }
    }

    func fetchEpisodesAsync(forceRefresh: Bool = false) async {
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !shows.isEmpty else { return }

        let showIds = shows.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadEpisodes(for: showIds) {
            self.episodes = cached
            logger.info("Episodes served from cache (\(cached.count) items).")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchPodcastEpisodes(showIds: showIds)
            persistenceService.saveEpisodes(fetched, for: showIds)
            self.episodes = fetched
            logger.info("Fetched \(fetched.count) episodes from Spotify.")

        } catch let partial as SpotifyAPIService.PartialEpisodesError {
            if !partial.episodes.isEmpty {
                persistenceService.saveEpisodes(partial.episodes, for: showIds)
                self.episodes = partial.episodes
                logger.warning("Partial fetch: cached \(partial.episodes.count) episodes before showing rate-limit error.")
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
            self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
            logger.error("Failed to fetch episodes: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}
