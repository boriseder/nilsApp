//
//  AdminViewModel.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import Foundation
import Combine
import os
import SwiftUI // For @AppStorage
import UIKit // Required for UIApplication

/// ViewModel for the Admin area, handling PIN validation, content search, and curation.
@MainActor
final class AdminViewModel: ObservableObject {
    // MARK: - PIN Management
    @Published var isUnlocked: Bool = false
    @Published var pinError: Bool = false
    
    // Using AppStorage for simplicity in this scaffold. In a highly sensitive app,
    // you might use the Keychain, but for a kid's walled garden, this is sufficient.
    @AppStorage("admin_pin") private var savedPIN: String = ""
    
    var isPINSetup: Bool {
        !savedPIN.isEmpty
    }
    
    // MARK: - Content Curation
    @Published var audiobookSearchQuery: String = ""
    @Published var musicSearchQuery: String = ""
    @Published var podcastSearchQuery: String = ""
    
    @Published private(set) var audiobookSearchResults: [CuratedArtist] = []
    @Published private(set) var musicSearchResults: [CuratedPlaylist] = []
    @Published private(set) var podcastSearchResults: [CuratedShow] = []
    
    @Published private(set) var curatedAudiobookSeries: [CuratedArtist] = []
    @Published private(set) var curatedMusicPlaylists: [CuratedPlaylist] = []
    @Published private(set) var curatedPodcastShows: [CuratedShow] = []
    
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var searchErrorMessage: String?
    
    private let persistenceService: PersistenceService
    let spotifyAPIService: SpotifyAPIService // Made internal for AdminView to access isAuthorized
    private let logger = Logger(subsystem: "com.nilsapp", category: "AdminViewModel")
    private var cancellables = Set<AnyCancellable>()
    
    init(persistenceService: PersistenceService, spotifyAPIService: SpotifyAPIService) {
        self.persistenceService = persistenceService
        self.spotifyAPIService = spotifyAPIService
        
        // Load initial curated content
        self.curatedAudiobookSeries = persistenceService.curatedContent.audiobookSeries
        self.curatedMusicPlaylists = persistenceService.curatedContent.musicPlaylists
        self.curatedPodcastShows = persistenceService.curatedContent.podcastShows
        
        // Observe changes in curated content from persistence service
        persistenceService.$curatedContent
            .sink { [weak self] content in
                self?.curatedAudiobookSeries = content.audiobookSeries
                self?.curatedMusicPlaylists = content.musicPlaylists
                self?.curatedPodcastShows = content.podcastShows
            }
            .store(in: &cancellables)
    }
    
    // MARK: - PIN Actions
    
    func setupPIN(_ pin: String) {
        guard pin.count >= 4 else {
            pinError = true
            logger.warning("Attempted to set PIN less than 4 digits.")
            return
        }
        savedPIN = pin
        isUnlocked = true
        pinError = false
        logger.info("Admin PIN set successfully.")
    }
    
    func verifyPIN(_ pin: String) {
        if pin == savedPIN {
            isUnlocked = true
            pinError = false
            logger.info("Admin PIN verified successfully.")
        } else {
            pinError = true
            logger.warning("Incorrect PIN entered.")
        }
    }
    
    func lock() {
        isUnlocked = false
        pinError = false
        audiobookSearchQuery = ""
        musicSearchQuery = ""
        podcastSearchQuery = ""
        audiobookSearchResults = []
        musicSearchResults = []
        podcastSearchResults = []
        logger.info("Admin area locked.")
    }
    
    // MARK: - Spotify Authentication
    
    func loginToSpotify() {
        if let authURL = spotifyAPIService.getAuthorizationURL() {
            UIApplication.shared.open(authURL)
        }
    }
    
    /// Clears all search results and queries.
    func clearSearch() {
        audiobookSearchQuery = ""
        musicSearchQuery = ""
        podcastSearchQuery = ""
        audiobookSearchResults = []
        musicSearchResults = []
        podcastSearchResults = []
    }
    
    /// Performs a search based on the provided query and category.
    func performSearch(query: String, category: SearchCategory) {
        guard !query.isEmpty else {
            audiobookSearchResults = []
            musicSearchResults = []
            podcastSearchResults = []
            return
        }
        isSearching = true
        searchErrorMessage = nil
        Task {
            do {
                switch category {
                case .audiobooks:
                    audiobookSearchResults = try await spotifyAPIService.searchAudiobookSeries(query: query)
                case .music:
                    musicSearchResults = try await spotifyAPIService.searchMusicPlaylists(query: query)
                case .podcasts:
                    podcastSearchResults = try await spotifyAPIService.searchPodcastShows(query: query)
                }
            } catch {
                searchErrorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Search for \(category.rawValue) failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }
    
    // MARK: - Individual Search Actions (can be deprecated if performSearch is used everywhere)
    // MARK: - Search Actions
    
    func searchAudiobooks() {
        guard !audiobookSearchQuery.isEmpty else {
            audiobookSearchResults = []
            return
        }
        isSearching = true
        searchErrorMessage = nil
        Task {
            do {
                audiobookSearchResults = try await spotifyAPIService.searchAudiobookSeries(query: audiobookSearchQuery)
            } catch {
                searchErrorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Audiobook search failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }
    
    func searchMusicPlaylists() {
        guard !musicSearchQuery.isEmpty else {
            musicSearchResults = []
            return
        }
        isSearching = true
        searchErrorMessage = nil
        Task {
            do {
                musicSearchResults = try await spotifyAPIService.searchMusicPlaylists(query: musicSearchQuery)
            } catch {
                searchErrorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Music playlist search failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }
    
    func searchPodcastShows() {
        guard !podcastSearchQuery.isEmpty else {
            podcastSearchResults = []
            return
        }
        isSearching = true
        searchErrorMessage = nil
        Task {
            do {
                podcastSearchResults = try await spotifyAPIService.searchPodcastShows(query: podcastSearchQuery)
            } catch {
                searchErrorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Podcast show search failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }
    
    // MARK: - Curation Actions
    
    func addAudiobookSeries(_ artist: CuratedArtist) {
        if !curatedAudiobookSeries.contains(where: { $0.id == artist.id }) {
            curatedAudiobookSeries.append(artist)
            saveCuratedContent()
            persistenceService.clearAlbumsCache() // Cache invalidieren
        }
    }
    
    func removeAudiobookSeries(at offsets: IndexSet) {
        curatedAudiobookSeries.remove(atOffsets: offsets)
        saveCuratedContent()
    }
    
    func addMusicPlaylist(_ playlist: CuratedPlaylist) {
        if !curatedMusicPlaylists.contains(where: { $0.id == playlist.id }) {
            curatedMusicPlaylists.append(playlist)
            saveCuratedContent()
        }
    }
    
    func removeMusicPlaylist(at offsets: IndexSet) {
        curatedMusicPlaylists.remove(atOffsets: offsets)
        saveCuratedContent()
    }
    
    func addPodcastShow(_ show: CuratedShow) {
        if !curatedPodcastShows.contains(where: { $0.id == show.id }) {
            curatedPodcastShows.append(show)
            saveCuratedContent()
        }
    }
    
    func removePodcastShow(at offsets: IndexSet) {
        curatedPodcastShows.remove(atOffsets: offsets)
        saveCuratedContent()
    }
    
    private func saveCuratedContent() {
        let newContent = CuratedContent(
            audiobookSeries: curatedAudiobookSeries,
            musicPlaylists: curatedMusicPlaylists,
            podcastShows: curatedPodcastShows
        )
        persistenceService.save(newContent)
        logger.info("Curated content saved.")
    }
}
