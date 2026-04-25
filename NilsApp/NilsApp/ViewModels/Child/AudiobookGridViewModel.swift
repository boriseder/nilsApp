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
    private let persistenceService: PersistenceService
    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")

    init(artists: [CuratedArtist], apiService: SpotifyAPIService, persistenceService: PersistenceService) {
        self.artists = artists
        self.apiService = apiService
        self.persistenceService = persistenceService
    }

    /// Fetches all albums for the artists — uses disk cache unless forceRefresh is true.
    func fetchAlbums(forceRefresh: Bool = false) {
        guard !isLoading else { return }

        let artistIds = artists.map { $0.id }

        // Cache prüfen — außer bei explizitem Pull-to-Refresh
        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            self.albums = cached
            logger.info("Using cached albums — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Fetching albums for \(self.artists.count) artists from API.")

        Task {
            do {
                let fetched = try await apiService.fetchAudiobookAlbums(artistIds: artistIds)
                persistenceService.saveAlbums(fetched, for: artistIds)
                self.albums = fetched
                self.logger.info("Successfully fetched \(fetched.count) total albums.")
            } catch {
                self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
                self.logger.error("Failed to fetch audiobook albums: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }
}
