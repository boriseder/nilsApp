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
    
    let artist: CuratedArtist
    private let apiService: SpotifyAPIService
    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")
    
    init(artist: CuratedArtist, apiService: SpotifyAPIService) {
        self.artist = artist
        self.apiService = apiService
    }
    
    /// Fetches all albums for the `artist` from the Spotify API.
    func fetchAlbums() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        logger.info("Fetching albums for artist: \(self.artist.name, privacy: .public)")
        
        Task {
            do {
                let fetchedAlbums = try await apiService.fetchAudiobookAlbums(artistId: artist.id)
                self.albums = fetchedAlbums
                self.logger.info("Successfully fetched \(fetchedAlbums.count) albums for \(self.artist.name, privacy: .public)")
            } catch {
                self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
                self.logger.error("Failed to fetch albums for artist \(self.artist.id, privacy: .public): \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}