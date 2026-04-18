//
//  PodcastViewModel.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import Foundation
import Combine
import os

/// ViewModel for a podcast show, responsible for fetching and managing
/// the list of episodes for a specific curated show.
@MainActor
final class PodcastViewModel: ObservableObject {
    @Published private(set) var episodes: [SpotifyEpisode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    let show: CuratedShow
    private let apiService: SpotifyAPIService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PodcastViewModel")
    
    init(show: CuratedShow, apiService: SpotifyAPIService) {
        self.show = show
        self.apiService = apiService
    }
    
    /// Fetches all episodes for the `show` from the Spotify API.
    func fetchEpisodes() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching episodes for show: \(self.show.name, privacy: .public)")
        
        Task {
            do {
                let fetchedEpisodes = try await apiService.fetchPodcastEpisodes(showId: show.id)
                self.episodes = fetchedEpisodes
                self.logger.info("Successfully fetched \(fetchedEpisodes.count) episodes for \(self.show.name, privacy: .public)")
            } catch {
                self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
                self.logger.error("Failed to fetch episodes for show \(self.show.id, privacy: .public): \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}