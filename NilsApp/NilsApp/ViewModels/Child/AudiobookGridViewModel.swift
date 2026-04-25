import Foundation
import Combine
import os

@MainActor
final class AudiobookGridViewModel: ObservableObject {
    @Published private(set) var albums: [SpotifyAlbum] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    // Wird nach init() via configure() gesetzt
    private(set) var artists: [CuratedArtist] = []
    private var apiService: SpotifyAPIService?
    private var persistenceService: PersistenceService?
    private var isConfigured = false

    private let logger = Logger(subsystem: "com.nilsapp", category: "AudiobookGridViewModel")

    /// Leerer init für @StateObject in HomeView
    init() {}

    /// Wird von HomeView in .onAppear aufgerufen, wenn EnvironmentObjects verfügbar sind.
    func configure(
        artists: [CuratedArtist],
        apiService: SpotifyAPIService,
        persistenceService: PersistenceService
    ) {
        // Nur neu konfigurieren wenn sich die Artists geändert haben
        guard !isConfigured || self.artists != artists else { return }
        self.artists = artists
        self.apiService = apiService
        self.persistenceService = persistenceService
        self.isConfigured = true
        // Cache invalidieren wenn sich die Artist-Liste ändert
        if self.artists != artists {
            self.albums = []
        }
    }

    func fetchAlbums(forceRefresh: Bool = false) {
        guard !isLoading else { return }
        Task { await fetchAlbumsAsync(forceRefresh: forceRefresh) }
    }

    func fetchAlbumsAsync(forceRefresh: Bool = false) async {
        guard !isLoading, let apiService, let persistenceService else { return }
        guard !artists.isEmpty else { return }

        let artistIds = artists.map { $0.id }

        if !forceRefresh, let cached = persistenceService.loadAlbums(for: artistIds) {
            self.albums = cached
            logger.info("Using cached albums — no API call needed.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await apiService.fetchAudiobookAlbums(artistIds: artistIds)
            persistenceService.saveAlbums(fetched, for: artistIds)
            self.albums = fetched
            logger.info("Successfully fetched \(fetched.count) total albums.")
        } catch {
            self.errorMessage = "Failed to load stories: \(error.localizedDescription)"
            logger.error("Failed to fetch audiobook albums: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
}
