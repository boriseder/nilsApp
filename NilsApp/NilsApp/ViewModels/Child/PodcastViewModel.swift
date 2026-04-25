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
    private var isConfigured = false

    private let logger = Logger(subsystem: "com.nilsapp", category: "PodcastViewModel")

    init() {}

    func configure(
        shows: [CuratedShow],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        guard !isConfigured || self.shows != shows else { return }
        self.shows = shows
        self.apiService = apiService
        self.persistenceService = persistenceService
        self.isConfigured = true
        if self.shows != shows {
            self.episodes = []
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
            logger.info("Using cached episodes — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchPodcastEpisodes(showIds: showIds)
            persistenceService.saveEpisodes(fetched, for: showIds)
            self.episodes = fetched
            logger.info("Successfully fetched \(fetched.count) total episodes.")
        } catch {
            self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
            logger.error("Failed to fetch podcast episodes: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
}
