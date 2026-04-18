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
    private let logger = Logger(subsystem: "com.nilsapp", category: "PodcastViewModel")
    
    init(shows: [CuratedShow], apiService: SpotifyAPIService) {
        self.shows = shows
        self.apiService = apiService
    }
    
    /// Fetches all episodes for the `shows` from the Spotify API.
    func fetchEpisodes() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching episodes for \(self.shows.count) shows.")
        
        Task {
            do {
                let showIds = shows.map { $0.id }
                let fetchedEpisodes = try await apiService.fetchPodcastEpisodes(showIds: showIds)
                self.episodes = fetchedEpisodes
                self.logger.info("Successfully fetched \(fetchedEpisodes.count) total episodes.")
            } catch {
                self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
                self.logger.error("Failed to fetch podcast episodes: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}