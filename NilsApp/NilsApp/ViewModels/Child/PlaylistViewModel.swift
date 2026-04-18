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
    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")
    
    init(playlists: [CuratedPlaylist], apiService: SpotifyAPIService) {
        self.playlists = playlists
        self.apiService = apiService
    }
    
    /// Fetches all tracks for the `playlist` from the Spotify API.
    func fetchTracks() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching tracks for \(self.playlists.count) playlists.")
        
        Task {
            do {
                let playlistIds = playlists.map { $0.id }
                let fetchedTracks = try await apiService.fetchPlaylistTracks(playlistIds: playlistIds)
                self.tracks = fetchedTracks
                self.logger.info("Successfully fetched \(fetchedTracks.count) total tracks.")
            } catch {
                self.errorMessage = "Failed to load music: \(error.localizedDescription)"
                self.logger.error("Failed to fetch playlist tracks: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}