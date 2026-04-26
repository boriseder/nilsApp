// Admin ViewModels Group
import Foundation
import Combine
import os
import SwiftUI
import UIKit

/// ViewModel for the Admin area, handling PIN validation, content search, and curation.
@MainActor
final class AdminViewModel: ObservableObject {

    // MARK: - PIN Management

    @Published var isUnlocked: Bool = false
    @Published var pinError: Bool = false

    @AppStorage("admin_pin") private var savedPIN: String = ""

    var isPINSetup: Bool { !savedPIN.isEmpty }

    // MARK: - Search Queries
    //
    // The view binds directly to these. The Combine pipelines in init() observe
    // each query and fire the corresponding search after a 400 ms quiet period,
    // so every keystroke does not trigger a network request.

    @Published var audiobookSearchQuery: String = ""
    @Published var musicSearchQuery: String = ""
    @Published var podcastSearchQuery: String = ""

    // MARK: - Search Results / State

    @Published private(set) var audiobookSearchResults: [CuratedArtist] = []
    @Published private(set) var musicSearchResults: [CuratedPlaylist] = []
    @Published private(set) var podcastSearchResults: [CuratedShow] = []

    @Published private(set) var isSearching: Bool = false
    @Published private(set) var searchErrorMessage: String?

    // MARK: - Curated Content

    @Published private(set) var curatedAudiobookSeries: [CuratedArtist] = []
    @Published private(set) var curatedMusicPlaylists: [CuratedPlaylist] = []
    @Published private(set) var curatedPodcastShows: [CuratedShow] = []

    // MARK: - Dependencies

    private let persistenceService: PersistenceService
    let spotifyAPIService: SpotifyAPIService
    private let logger = Logger(subsystem: "com.nilsapp", category: "AdminViewModel")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(persistenceService: PersistenceService, spotifyAPIService: SpotifyAPIService) {
        self.persistenceService = persistenceService
        self.spotifyAPIService = spotifyAPIService

        // Seed curated lists from persisted content.
        self.curatedAudiobookSeries = persistenceService.curatedContent.audiobookSeries
        self.curatedMusicPlaylists  = persistenceService.curatedContent.musicPlaylists
        self.curatedPodcastShows    = persistenceService.curatedContent.podcastShows

        // Keep curated lists in sync when persistence changes externally.
        persistenceService.$curatedContent
            .sink { [weak self] content in
                self?.curatedAudiobookSeries = content.audiobookSeries
                self?.curatedMusicPlaylists  = content.musicPlaylists
                self?.curatedPodcastShows    = content.podcastShows
            }
            .store(in: &cancellables)

        // MARK: Debounced search pipelines
        //
        // Each pipeline:
        //   1. Removes consecutive duplicates so typing the same character twice
        //      does not fire a redundant request.
        //   2. Waits 400 ms after the last keystroke before proceeding.
        //      This is the debounce window — adjust if needed.
        //   3. Receives on the main actor (safe for @Published mutation).
        //   4. Clears results immediately when the query is emptied, without
        //      waiting for the debounce window, so the UI feels responsive.

        $audiobookSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.audiobookSearchResults = []
                } else {
                    self.executeSearch(query: query, category: .audiobooks)
                }
            }
            .store(in: &cancellables)

        $musicSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.musicSearchResults = []
                } else {
                    self.executeSearch(query: query, category: .music)
                }
            }
            .store(in: &cancellables)

        $podcastSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.podcastSearchResults = []
                } else {
                    self.executeSearch(query: query, category: .podcasts)
                }
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
        clearSearch()
        logger.info("Admin area locked.")
    }

    // MARK: - Spotify Authentication

    func loginToSpotify() {
        if let authURL = spotifyAPIService.getAuthorizationURL() {
            UIApplication.shared.open(authURL)
        }
    }

    // MARK: - Search

    /// Clears all query strings and result sets.
    func clearSearch() {
        audiobookSearchQuery = ""
        musicSearchQuery = ""
        podcastSearchQuery = ""
        audiobookSearchResults = []
        musicSearchResults = []
        podcastSearchResults = []
    }

    /// Public entry point kept for compatibility with AdminSearchView's onSubmit handler.
    /// Bypasses the debounce and fires immediately (useful for explicit keyboard submit).
    func performSearch(query: String, category: SearchCategory) {
        executeSearch(query: query, category: category)
    }

    // MARK: - Private Search Execution
    //
    // A single method handles all three categories. Both the debounce pipelines
    // above and the legacy performSearch() call through here, so there is one
    // place to add error handling, logging, or rate-limit guards.

    private func executeSearch(query: String, category: SearchCategory) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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

    // MARK: - Curation Actions

    func addAudiobookSeries(_ artist: CuratedArtist) {
        guard !curatedAudiobookSeries.contains(where: { $0.id == artist.id }) else { return }
        curatedAudiobookSeries.append(artist)
        saveCuratedContent()
        persistenceService.clearAlbumsCache()
    }

    func removeAudiobookSeries(at offsets: IndexSet) {
        curatedAudiobookSeries.remove(atOffsets: offsets)
        saveCuratedContent()
    }

    func addMusicPlaylist(_ playlist: CuratedPlaylist) {
        guard !curatedMusicPlaylists.contains(where: { $0.id == playlist.id }) else { return }
        curatedMusicPlaylists.append(playlist)
        saveCuratedContent()
    }

    func removeMusicPlaylist(at offsets: IndexSet) {
        curatedMusicPlaylists.remove(atOffsets: offsets)
        saveCuratedContent()
    }

    func addPodcastShow(_ show: CuratedShow) {
        guard !curatedPodcastShows.contains(where: { $0.id == show.id }) else { return }
        curatedPodcastShows.append(show)
        saveCuratedContent()
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
