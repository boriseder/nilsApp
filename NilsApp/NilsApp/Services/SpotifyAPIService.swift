// Services Group
import Foundation
import Combine
import os

// TODO: Import the package once added via Swift Package Manager
import SpotifyWebAPI

/// A service wrapper for the `Peter-Schorn/SpotifyAPI` package.
/// Handles OAuth authentication, automatic token refresh, and fetching metadata (albums, tracks, episodes) with pagination.
@MainActor
final class SpotifyAPIService: ObservableObject {
    
    /// Indicates if the app currently has a valid or refreshable authorization token.
    @Published private(set) var isAuthorized: Bool = false
    
    /// Becomes true if the automatic token refresh fails completely and manual parental login is required.
    /// The UI must observe this to show an "Ask a grown-up" error state in the child's view.
    @Published private(set) var requiresReauthentication: Bool = false
    
    private let logger = Logger(subsystem: "com.nilsapp", category: "SpotifyAPIService")
    private var cancellables: Set<AnyCancellable> = []
    
    /// The Spotify API client instance. We use AuthorizationCodeFlowPKCEManager for iOS apps without a backend server.
    private var api = SpotifyAPI(authorizationManager: AuthorizationCodeFlowPKCEManager(clientId: Constants.spotifyClientId))
    
    init() {
        setupAPI()
    }
    
    private func setupAPI() {
        logger.debug("SpotifyAPIService initialized.")
        
        // Set up the authorization manager to automatically save and load tokens from Keychain.
        // This is crucial for persisting the user's login across app launches.
        api.authorizationManager.setup()
        
        // Observe the authorization manager's changes to update `isAuthorized` and persist data.
        api.authorizationManager.$didChange
            .sink { [weak self] in
                guard let self = self else { return }
                // Update `isAuthorized` based on whether we have a valid access token.
                self.isAuthorized = self.api.authorizationManager.accessToken != nil
                // Persist the authorization information to Keychain.
                // The `AuthorizationCodeFlowPKCEManager` handles this automatically with `setup()`.
                // We just need to ensure our `isAuthorized` state reflects it.
                self.logger.debug("Authorization manager did change. Is authorized: \(self.isAuthorized)")
            }
            .store(in: &cancellables)
        
        // Observe when the authorization manager deauthorizes, indicating a need for reauthentication.
        api.authorizationManager.$didDeauthorize
            .sink { [weak self] in
                guard let self = self else { return }
                self.requiresReauthentication = true
                self.isAuthorized = false
                self.logger.warning("Authorization manager did deauthorize. Reauthentication required.")
            }
            .store(in: &cancellables)
        
        // Initial check for authorization status
        self.isAuthorized = api.authorizationManager.accessToken != nil
    }
    
    // MARK: - Authentication
    
    /// Generates the URL for the parent to log in via a web view.
    /// *STRICT RULE*: This must ONLY be used in the Admin area. Never in the child's UI.
    ///
    /// Required scopes:
    /// - `user-read-playback-state`, `user-modify-playback-state`, `user-read-currently-playing`: For playback control.
    /// - `user-library-read`: To read parent's saved content for curation.
    /// - `playlist-read-private`, `playlist-read-collaborative`: To read parent's playlists for curation.
    /// - `user-read-private`, `user-read-email`: For basic user info.
    /// - `app-remote-control`: Essential for the Spotify App Remote SDK.
    func getAuthorizationURL() -> URL? {
        logger.info("Generating OAuth URL for Admin login.")
        let scopes: Set<Scope> = [
            .userReadPlaybackState, .userModifyPlaybackState, .userReadCurrentlyPlaying,
            .userLibraryRead, .playlistReadPrivate, .playlistReadCollaborative,
            .userReadPrivate, .userReadEmail, .appRemoteControl
        ]
        return api.authorizationManager.makeAuthorizationURL(
            redirectURI: Constants.spotifyRedirectURI,
            showDialog: true, // Always show dialog to ensure user selects correct account
            scopes: scopes
        )
    }
    
    /// Handles the redirect URL after the parent successfully logs in.
    func handleRedirectURL(_ url: URL) async throws {
        logger.info("Handling OAuth redirect URL.")
        do {
            // Request access and refresh tokens using the redirect URL.
            try await api.authorizationManager.requestAccessAndRefreshTokens(redirectURIWithQuery: url)
            self.isAuthorized = true
            self.requiresReauthentication = false
            logger.info("Successfully handled OAuth redirect and obtained tokens.")
        } catch {
            self.isAuthorized = false
            self.requiresReauthentication = true
            logger.error("Failed to handle OAuth redirect: \(error.localizedDescription)")
            throw error // Re-throw the error for the UI to handle
        }
    }
    
    // MARK: - Data Fetching (Audiobooks)
    
    /// Fetches all albums (stories) for a given audiobook artist.
    /// Implements pagination to ensure all 100+ albums are retrieved.
    func fetchAudiobookAlbums(artistId: String) async throws -> [SpotifyAlbum] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Fetching audiobook albums for artist: \(artistId)")

        var allAlbums: [SpotifyAlbum] = []
        var offset = 0
        let limit = 50 // Max limit for Spotify API for this endpoint

        while true {
            // Fetch a page of albums for the given artist.
            // We specify `albumType: [.album]` to ensure we only get full albums,
            // which are typically used for audiobooks, and filter out singles/compilations.
            let page = try await api.artistAlbums(
                artistId,
                albumType: [.album], // Filter for actual albums
                limit: limit,
                offset: offset,
                market: "US" // A market is required for this endpoint. Can be made dynamic later.
            )

            for album in page.items {
                // Find the largest image available for the album to ensure good quality on iPad.
                let imageURL = album.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url
                
                allAlbums.append(SpotifyAlbum(
                    id: album.id!, // Spotify Album ID is guaranteed to be present
                    name: album.name,
                    imageURL: imageURL,
                    uri: album.uri // Spotify Album URI is guaranteed to be present
                ))
            }
            // If there are no more pages, `page.next` will be nil, and we break the loop.
            guard page.next != nil else { break }
            offset += limit
        }
        logger.info("Successfully fetched \(allAlbums.count) albums for artist: \(artistId, privacy: .public)")
        return allAlbums
    }
    
    // MARK: - Data Fetching (Music)
    
    /// Fetches all tracks for a specific curated playlist.
    func fetchPlaylistTracks(playlistId: String) async throws -> [SpotifyTrack] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Fetching tracks for playlist: \(playlistId)")
        
        // TODO: Call api.playlistItems(playlistId, limit: 100)
        // TODO: Handle pagination to fetch all tracks.
        return []
    }
    
    // MARK: - Data Fetching (Podcasts)
    
    /// Fetches all episodes for a specific podcast show, sorted newest first.
    func fetchPodcastEpisodes(showId: String) async throws -> [SpotifyEpisode] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Fetching episodes for show: \(showId)")
        
        // TODO: Call api.showEpisodes(showId, limit: 50)
        // TODO: Handle pagination.
        return []
    }
    
    // MARK: - Search (Placeholders)
    
    /// Searches Spotify for artists (Audiobook Series) matching the query.
    func searchAudiobookSeries(query: String) async throws -> [CuratedArtist] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Searching audiobook series for: \(query)")
        
        // TODO: Call api.search(query: query, categories: [.artist])
        return []
    }
    
    /// Searches Spotify for playlists matching the query.
    func searchMusicPlaylists(query: String) async throws -> [CuratedPlaylist] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Searching music playlists for: \(query)")
        
        // TODO: Call api.search(query: query, categories: [.playlist])
        return []
    }
    
    /// Searches Spotify for podcast shows matching the query.
    func searchPodcastShows(query: String) async throws -> [CuratedShow] {
        guard isAuthorized else { throw APIError.notAuthorized }
        logger.info("Searching podcast shows for: \(query)")
        
        // TODO: Call api.search(query: query, categories: [.show])
        return []
    }
    
    // MARK: - Errors
    
    enum APIError: Error, LocalizedError {
        case notAuthorized
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "The app is not authorized. A grown-up needs to log in."
            }
        }
    }
}