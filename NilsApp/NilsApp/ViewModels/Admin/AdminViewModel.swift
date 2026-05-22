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
    
    // OPTIMIZATION: Hold a reference to the active search task to prevent race conditions
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(persistenceService: PersistenceService, spotifyAPIService: SpotifyAPIService) {
        self.persistenceService = persistenceService
        self.spotifyAPIService = spotifyAPIService

        self.curatedAudiobookSeries = persistenceService.curatedContent.audiobookSeries
        self.curatedMusicPlaylists  = persistenceService.curatedContent.musicPlaylists
        self.curatedPodcastShows    = persistenceService.curatedContent.podcastShows

        persistenceService.$curatedContent
            .sink { [weak self] content in
                self?.curatedAudiobookSeries = content.audiobookSeries
                self?.curatedMusicPlaylists  = content.musicPlaylists
                self?.curatedPodcastShows    = content.podcastShows
            }
            .store(in: &cancellables)

        // Debounced search pipelines — fire after 400ms of quiet per category.
        $audiobookSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (self.audiobookSearchResults = [])
                    : self.executeSearch(query: query, category: .audiobooks)
            }
            .store(in: &cancellables)

        $musicSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (self.musicSearchResults = [])
                    : self.executeSearch(query: query, category: .music)
            }
            .store(in: &cancellables)

        $podcastSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (self.podcastSearchResults = [])
                    : self.executeSearch(query: query, category: .podcasts)
            }
            .store(in: &cancellables)
    }

    // MARK: - PIN Actions

    func setupPIN(_ pin: String) {
        guard pin.count >= 4 else { pinError = true; return }
        savedPIN = pin; isUnlocked = true; pinError = false
        logger.info("Admin PIN set.")
    }

    func verifyPIN(_ pin: String) {
        if pin == savedPIN { isUnlocked = true; pinError = false }
        else { pinError = true; logger.warning("Incorrect PIN.") }
    }

    func lock() {
        isUnlocked = false; pinError = false; clearSearch()
        logger.info("Admin area locked.")
    }

    // MARK: - Spotify Authentication

    func loginToSpotify() {
        if let authURL = spotifyAPIService.getAuthorizationURL() {
            UIApplication.shared.open(authURL)
        }
    }

    // MARK: - Search

    func clearSearch() {
        searchTask?.cancel()
        audiobookSearchQuery = ""; musicSearchQuery = ""; podcastSearchQuery = ""
        audiobookSearchResults = []; musicSearchResults = []; podcastSearchResults = []
    }

    func performSearch(query: String, category: SearchCategory) {
        executeSearch(query: query, category: category)
    }

    private func executeSearch(query: String, category: SearchCategory) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true; searchErrorMessage = nil
        
        searchTask?.cancel() // Cancel the previous inflight search
        
        searchTask = Task {
            do {
                switch category {
                case .audiobooks: audiobookSearchResults = try await spotifyAPIService.searchAudiobookSeries(query: query)
                case .music:      musicSearchResults     = try await spotifyAPIService.searchMusicPlaylists(query: query)
                case .podcasts:   podcastSearchResults   = try await spotifyAPIService.searchPodcastShows(query: query)
                }
            } catch {
                guard !Task.isCancelled else { return } // Ignore error if we deliberately cancelled it
                searchErrorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Search for \(category.rawValue) failed: \(error.localizedDescription)")
            }
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    // MARK: - Curation Actions

    func addAudiobookSeries(_ artist: CuratedArtist) {
        guard !curatedAudiobookSeries.contains(where: { $0.id == artist.id }) else { return }
        curatedAudiobookSeries.append(artist)
        saveCuratedContent()

        // RATE LIMIT FIX — do NOT call persistenceService.clearAlbumsCache() here.
        //
        // The old code called it unconditionally, nuking the cache for all artists
        // whenever the parent added even one new series. On the next view, the app
        // fetched every artist's full album catalog from scratch — potentially dozens
        // or hundreds of API requests for large catalogs like TKKG, which triggered
        // the 85,000-second rate limit.
        //
        // Why no explicit invalidation is needed:
        //   - The PersistenceService cache is keyed on the sorted array of all
        //     artist IDs currently in curatedContent.
        //   - When the artist list changes (add or remove), the key changes.
        //   - AudiobookGridViewModel.configure() detects the list change, resets
        //     self.albums = [], and fetchAlbums() then calls loadAlbums(for: newIds)
        //     which returns nil (cache miss) because the key no longer matches.
        //   - A fresh API fetch runs automatically for only the new set of artists.
        //   - Previously-fetched data is NOT re-fetched because the ViewModel fetches
        //     all artists in one call; there is no per-artist cache to preserve.
        //
        // The net effect is identical correctness with zero unnecessary cache busting.
        logger.info("Added audiobook series '\(artist.name)'. Cache self-invalidates on next fetch.")
    }

    func removeAudiobookSeries(at offsets: IndexSet) {
        curatedAudiobookSeries.remove(atOffsets: offsets)
        saveCuratedContent()
        // Same rationale: the artist ID key changes → cache miss → fresh fetch.
        // No clearAlbumsCache() needed.
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
        persistenceService.save(CuratedContent(
            audiobookSeries: curatedAudiobookSeries,
            musicPlaylists:  curatedMusicPlaylists,
            podcastShows:    curatedPodcastShows
        ))
        logger.info("Curated content saved.")
    }
}
