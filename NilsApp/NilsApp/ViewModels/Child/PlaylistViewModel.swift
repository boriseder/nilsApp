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
    
    let playlist: CuratedPlaylist
    private let apiService: SpotifyAPIService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PlaylistViewModel")
    
    init(playlist: CuratedPlaylist, apiService: SpotifyAPIService) {
        self.playlist = playlist
        self.apiService = apiService
    }
    
    /// Fetches all tracks for the `playlist` from the Spotify API.
    func fetchTracks() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching tracks for playlist: \(self.playlist.name, privacy: .public)")
        
        Task {
            do {
                let fetchedTracks = try await apiService.fetchPlaylistTracks(playlistId: playlist.id)
                self.tracks = fetchedTracks
                self.logger.info("Successfully fetched \(fetchedTracks.count) tracks for \(self.playlist.name, privacy: .public)")
            } catch {
                self.errorMessage = "Failed to load music: \(error.localizedDescription)"
                self.logger.error("Failed to fetch tracks for playlist \(self.playlist.id, privacy: .public): \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}