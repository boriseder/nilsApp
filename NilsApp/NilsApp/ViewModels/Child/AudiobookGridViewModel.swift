//
//  AudiobookGridViewModel.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import Foundation
import Combine
import os

/// ViewModel for the AudiobookGridView, responsible for fetching and managing
/// the list of albums for a specific curated artist.
@MainActor
final class AudiobookGridViewModel: ObservableObject {
    @Published private(set) var albums: [SpotifyAlbum] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    let artists: [CuratedArtist]
    private let apiService: SpotifyAPIService
    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")
    
    init(artists: [CuratedArtist], apiService: SpotifyAPIService) {
        self.artists = artists
        self.apiService = apiService
    }
    
    /// Fetches all albums for the `artist` from the Spotify API.
    func fetchAlbums() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching albums for \(self.artists.count) artists.")
        
        Task {
            do {
                // Extract all IDs from the array of artists
                let artistIds = artists.map { $0.id }
                let fetchedAlbums = try await apiService.fetchAudiobookAlbums(artistIds: artistIds)
                self.albums = fetchedAlbums
                self.logger.info("Successfully fetched \(fetchedAlbums.count) total albums.")
            } catch {
                self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
                self.logger.error("Failed to fetch audiobook albums: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}