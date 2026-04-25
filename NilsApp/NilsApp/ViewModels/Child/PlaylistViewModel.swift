//
//  PlaylistViewModel.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import Foundation
import Combine
import os

/// ViewModel for a music playlist, responsible for fetching and managing
/// the list of tracks for a specific curated playlist.
@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published private(set) var tracks: [SpotifyTrack] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    let playlists: [CuratedPlaylist]
    private let apiService: SpotifyAPIService
    private let persistenceService: PersistenceService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")

    init(playlists: [CuratedPlaylist], apiService: SpotifyAPIService, persistenceService: PersistenceService) {
        self.playlists = playlists
        self.apiService = apiService
        self.persistenceService = persistenceService
    }

    /// Fetches all tracks — uses disk cache unless forceRefresh is true.
    func fetchTracks(forceRefresh: Bool = false) {
        guard !isLoading else { return }

        let playlistIds = playlists.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadTracks(for: playlistIds) {
            self.tracks = cached
            logger.info("Using cached tracks — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Fetching tracks for \(self.playlists.count) playlists from API.")

        Task {
            do {
                let fetched = try await apiService.fetchPlaylistTracks(playlistIds: playlistIds)
                persistenceService.saveTracks(fetched, for: playlistIds)
                self.tracks = fetched
                self.logger.info("Successfully fetched \(fetched.count) total tracks.")
            } catch {
                self.errorMessage = "Failed to load music: \(error.localizedDescription)"
                self.logger.error("Failed to fetch playlist tracks: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}
