//
//  PodcastViewModel.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import Foundation
import Combine
import os

/// ViewModel for podcast shows, responsible for fetching and managing
/// the list of episodes for specific curated shows.
@MainActor
final class PodcastViewModel: ObservableObject {
    @Published private(set) var episodes: [SpotifyEpisode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    let shows: [CuratedShow]
    private let apiService: SpotifyAPIService
    private let persistenceService: PersistenceService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PodcastViewModel")

    init(shows: [CuratedShow], apiService: SpotifyAPIService, persistenceService: PersistenceService) {
        self.shows = shows
        self.apiService = apiService
        self.persistenceService = persistenceService
    }

    /// Fetches all episodes — uses disk cache unless forceRefresh is true.
    func fetchEpisodes(forceRefresh: Bool = false) {
        guard !isLoading else { return }

        let showIds = shows.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadEpisodes(for: showIds) {
            self.episodes = cached
            logger.info("Using cached episodes — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Fetching episodes for \(self.shows.count) shows from API.")

        Task {
            do {
                let fetched = try await apiService.fetchPodcastEpisodes(showIds: showIds)
                persistenceService.saveEpisodes(fetched, for: showIds)
                self.episodes = fetched
                self.logger.info("Successfully fetched \(fetched.count) total episodes.")
            } catch {
                self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
                self.logger.error("Failed to fetch podcast episodes: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}
