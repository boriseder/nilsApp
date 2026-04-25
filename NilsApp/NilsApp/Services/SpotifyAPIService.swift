// Services Group
import Foundation
import Combine
import os
import CryptoKit

/// A native service to handle Spotify API calls.
/// Handles OAuth PKCE authentication, automatic token refresh, and fetching metadata with pagination.
@MainActor
final class SpotifyAPIService: ObservableObject {
    
    /// Indicates if the app currently has a valid or refreshable authorization token.
    @Published private(set) var isAuthorized: Bool = false
    
    /// Becomes true if the automatic token refresh fails completely and manual parental login is required.
    @Published private(set) var requiresReauthentication: Bool = false
    
    private let logger = Logger(subsystem: "com.nilsapp", category: "SpotifyAPIService")
    
    // PKCE Flow required state variables
    private var codeVerifier: String = ""
    private var oauthState: String = ""
    
    // Tokens Object
    struct AuthState: Codable {
        var accessToken: String
        var refreshToken: String
        var expirationDate: Date
    }
    private var authState: AuthState?
    
    init() {
        setupAPI()
    }
    
    private func setupAPI() {
        logger.debug("SpotifyAPIService initialized.")
        loadFromKeychain()

        // FIX 8: isAuthorized must reflect the outcome of the token refresh, not just
        // whether an authState exists in the keychain before the refresh completes.
        // We set it conservatively to false here and update it inside the Task so the
        // UI never shows a false-positive authorized state while the refresh is in flight.
        if authState != nil {
            // We have a stored token — optimistically allow API calls while refreshing,
            // but only if the stored token is not yet expired.
            self.isAuthorized = authState?.expirationDate ?? .distantPast > Date()

            Task {
                do {
                    try await forceTokenRefresh()
                    self.isAuthorized = true
                    logger.info("Token refreshed on startup.")
                } catch {
                    // forceTokenRefresh already sets isAuthorized = false and
                    // requiresReauthentication = true on failure.
                    logger.warning("Startup token refresh failed: \(error.localizedDescription)")
                }
            }
        } else {
            self.isAuthorized = false
        }
    }
    
    // MARK: - Authentication
    
    /// Generates the URL for the parent to log in via a web view.
    func getAuthorizationURL() -> URL? {
        logger.info("Generating OAuth URL for Admin login.")
        
        self.codeVerifier = generateCodeVerifier()
        self.oauthState = generateCodeVerifier()
        
        guard let verifierData = codeVerifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: verifierData)
        let codeChallenge = base64URLEncode(Data(hash))
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Constants.spotifyClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "\(Constants.spotifyRedirectURI)"),
            URLQueryItem(name: "state", value: self.oauthState),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read playlist-read-private playlist-read-collaborative user-read-private user-read-email app-remote-control"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]
        
        return components.url
    }
    
    /// Handles the redirect URL after the parent successfully logs in.
    func handleRedirectURL(_ url: URL) async throws {
        logger.info("Handling OAuth redirect URL.")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              state == self.oauthState else {
            throw APIError.notAuthorized
        }
        
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let redirectURIEncoded = "\(Constants.spotifyRedirectURI)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "client_id=\(Constants.spotifyClientId)&grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURIEncoded)&code_verifier=\(self.codeVerifier)"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data: data, response: response)
            self.isAuthorized = true
            self.requiresReauthentication = false
            logger.info("Successfully handled OAuth redirect and obtained tokens.")
        } catch {
            self.isAuthorized = false
            self.requiresReauthentication = true
            logger.error("Failed to handle OAuth redirect: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Token Management
    
    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }
    
    private func handleTokenResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.notAuthorized
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        let expiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - 60))
        let newRefresh = tokenResponse.refresh_token ?? self.authState?.refreshToken ?? ""
        guard !newRefresh.isEmpty else { throw APIError.notAuthorized }
        
        self.authState = AuthState(accessToken: tokenResponse.access_token, refreshToken: newRefresh, expirationDate: expiration)
        saveToKeychain()
    }
    
    /// Returns a valid access token. Automatically refreshes if expired.
    func getValidToken() async throws -> String {
        guard let state = authState else { throw APIError.notAuthorized }
        if state.expirationDate > Date() { return state.accessToken }
        return try await forceTokenRefresh()
    }
    
    @discardableResult
    func forceTokenRefresh() async throws -> String {
        guard let state = authState else { throw APIError.notAuthorized }
        
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "client_id=\(Constants.spotifyClientId)&grant_type=refresh_token&refresh_token=\(state.refreshToken)"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data: data, response: response)
            self.isAuthorized = true
            self.requiresReauthentication = false
            return self.authState!.accessToken
        } catch {
            self.isAuthorized = false
            self.requiresReauthentication = true
            deleteFromKeychain()
            throw APIError.notAuthorized
        }
    }
    
    // MARK: - Keychain Persistence
    
    private let keychainKey = "com.nilsapp.spotifyAuth"
    
    private func saveToKeychain() {
        do {
            let data = try JSONEncoder().encode(self.authState)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: keychainKey
            ]
            
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            
            if status == errSecItemNotFound {
                var newItem = query
                newItem[kSecValueData as String] = data
                SecItemAdd(newItem as CFDictionary, nil)
            }
        } catch {
            logger.error("Failed to encode authorization manager for Keychain: \(error.localizedDescription)")
        }
    }
    
    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            do {
                let state = try JSONDecoder().decode(AuthState.self, from: data)
                self.authState = state
                self.logger.info("Successfully loaded Spotify authorization from Keychain.")
            } catch {
                self.logger.error("Failed to decode authorization manager from Keychain: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Data Fetching (Audiobooks)
    
    func fetchAudiobookAlbums(artistIds: [String]) async throws -> [SpotifyAlbum] {
        guard isAuthorized else { throw APIError.notAuthorized }

        var allAlbums: [SpotifyAlbum] = []

        for artistId in artistIds {
            let cleanArtistId = artistId.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Fetching audiobook albums for artist: \(cleanArtistId)")

            var nextURL: String? = "https://api.spotify.com/v1/artists/\(cleanArtistId)/albums?include_groups=album"

            while let currentURLString = nextURL {
                guard let url = URL(string: currentURLString) else { break }
                logger.debug("Requesting audiobook albums: \(url.absoluteString)")

                let token = try await getValidToken()
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                var (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    let newToken = try await forceTokenRefresh()
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let retry = try await URLSession.shared.data(for: request)
                    data = retry.0
                    response = retry.1
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if retryAfter > 30 {
                        logger.error("Spotify Rate Limit dauerhaft (\(retryAfter)s). Zeige Fehlermeldung.")
                        throw APIError.rateLimited(retryAfter: retryAfter)
                    }
                    logger.warning("Spotify Rate Limit (429) hit. Waiting \(retryAfter) seconds.")
                    try await Task.sleep(for: .seconds(retryAfter))
                    continue
                }

                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    logger.error("HTTP Error \(httpResponse.statusCode): \(errorString)")
                    throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
                }

                struct LooseAlbumResponse: Decodable { let items: [LooseAlbum?]?; let next: String? }
                struct LooseAlbum: Decodable { let id: String?; let name: String?; let images: [LooseImage?]?; let uri: String? }
                struct LooseImage: Decodable { let url: String? }

                do {
                    let decoded = try JSONDecoder().decode(LooseAlbumResponse.self, from: data)
                    let items = decoded.items ?? []
                    logger.debug("Decoded \(items.count) audiobook items from JSON")

                    let pageAlbums = items.compactMap { album -> SpotifyAlbum? in
                        guard let album = album, let id = album.id, let name = album.name, let uri = album.uri else { return nil }
                        let imageURL = album.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                        return SpotifyAlbum(id: id, name: name, imageURL: imageURL, uri: uri)
                    }
                    allAlbums.append(contentsOf: pageAlbums)
                    nextURL = decoded.next
                } catch {
                    logger.error("Decoding error for audiobook albums: \(error.localizedDescription)")
                    throw error
                }
            }
        }

        logger.info("Successfully fetched \(allAlbums.count) albums for artists.")
        return allAlbums
    }
    
    // MARK: - Data Fetching (Music)
    
    func fetchPlaylistTracks(playlistIds: [String]) async throws -> [SpotifyTrack] {
        guard isAuthorized else { throw APIError.notAuthorized }

        var allTracks: [SpotifyTrack] = []

        for playlistId in playlistIds {
            let cleanPlaylistId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Fetching tracks for playlist: \(cleanPlaylistId, privacy: .public)")

            var offset = 0
            let limit = 100

            while true {
                let token = try await getValidToken()
                
                var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(cleanPlaylistId)/items")!
                components.queryItems = [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)")
                ]
                guard let url = components.url else { break }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                var (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    let newToken = try await forceTokenRefresh()
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let retry = try await URLSession.shared.data(for: request)
                    data = retry.0
                    response = retry.1
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if retryAfter > 30 {
                        throw APIError.rateLimited(retryAfter: retryAfter)
                    }
                    try await Task.sleep(for: .seconds(retryAfter))
                    continue
                }

                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    if httpResponse.statusCode == 403 {
                        logger.warning("HTTP 403 Forbidden for playlist \(cleanPlaylistId). Skipping.")
                        break
                    }
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
                }

                struct LoosePlaylistTrackResponse: Decodable { let items: [LoosePlaylistItem?]?; let next: String? }
                struct LoosePlaylistItem: Decodable {
                    let track: LooseTrack?
                    let item: LooseTrack?
                }
                struct LooseTrack: Decodable {
                    let id: String?
                    let name: String?
                    let artists: [LooseArtist?]?
                    let album: LooseAlbum?
                    let uri: String?
                    let duration_ms: Int?
                    let explicit: Bool?
                }
                struct LooseArtist: Decodable { let name: String? }
                struct LooseAlbum: Decodable { let images: [LooseImage?]? }
                struct LooseImage: Decodable { let url: String? }

                do {
                    let decoded = try JSONDecoder().decode(LoosePlaylistTrackResponse.self, from: data)
                    guard let items = decoded.items else { break }

                    let pageTracks = items.compactMap { listItem -> SpotifyTrack? in
                        guard let track = listItem?.track ?? listItem?.item,
                              track.explicit != true,
                              let id = track.id,
                              let name = track.name,
                              let uri = track.uri else { return nil }
                        let artistName = track.artists?.compactMap { $0 }.first?.name ?? "Unknown Artist"
                        let imageURL = track.album?.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                        return SpotifyTrack(
                            id: id,
                            name: name,
                            artistName: artistName,
                            imageURL: imageURL,
                            uri: uri,
                            duration: TimeInterval(track.duration_ms ?? 0) / 1000.0
                        )
                    }
                    allTracks.append(contentsOf: pageTracks)

                    if decoded.next == nil || items.isEmpty { break }
                    offset += limit
                } catch {
                    logger.error("Decoding error for playlist tracks: \(error.localizedDescription)")
                    throw error
                }
            }
        }

        logger.info("Successfully fetched \(allTracks.count) tracks for playlists.")
        return allTracks
    }
    
    // MARK: - Data Fetching (Podcasts)
    
    /// Fetches up to 3 non-explicit episodes per show, sorted newest first.
    func fetchPodcastEpisodes(showIds: [String]) async throws -> [SpotifyEpisode] {
        guard isAuthorized else { throw APIError.notAuthorized }

        var allEpisodes: [SpotifyEpisode] = []

        for showId in showIds {
            let cleanShowId = showId.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Fetching episodes for show: \(cleanShowId, privacy: .public)")

            var showEpisodes: [SpotifyEpisode] = []
            var offset = 0
            let limit = 10

            while true {
                let token = try await getValidToken()
                
                var components = URLComponents(string: "https://api.spotify.com/v1/shows/\(cleanShowId)/episodes")!
                components.queryItems = [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)"),
                    URLQueryItem(name: "market", value: "AT")
                ]
                guard let url = components.url else { break }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                var (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    let newToken = try await forceTokenRefresh()
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let retry = try await URLSession.shared.data(for: request)
                    data = retry.0
                    response = retry.1
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if retryAfter > 30 {
                        throw APIError.rateLimited(retryAfter: retryAfter)
                    }
                    try await Task.sleep(for: .seconds(retryAfter))
                    continue
                }

                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
                }

                struct LooseEpisodeResponse: Decodable { let items: [LooseEpisode?]?; let next: String? }
                struct LooseEpisode: Decodable {
                    let id: String?
                    let name: String?
                    let description: String?
                    let images: [LooseImage?]?
                    let uri: String?
                    let duration_ms: Int?
                    let release_date: String?
                    let explicit: Bool?
                }
                struct LooseImage: Decodable { let url: String? }

                do {
                    let decoded = try JSONDecoder().decode(LooseEpisodeResponse.self, from: data)
                    guard let items = decoded.items else { break }

                    let pageEpisodes = items.compactMap { episode -> SpotifyEpisode? in
                        guard let ep = episode, ep.explicit != true,
                              let id = ep.id, let name = ep.name, let uri = ep.uri else { return nil }
                        let imageURL = ep.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                        return SpotifyEpisode(
                            id: id,
                            name: name,
                            description: ep.description ?? "",
                            imageURL: imageURL,
                            uri: uri,
                            duration: TimeInterval(ep.duration_ms ?? 0) / 1000.0,
                            releaseDate: ep.release_date?.convertedToDate()
                        )
                    }

                    showEpisodes.append(contentsOf: pageEpisodes)

                    // FIX 9: Only stop paging when we have enough non-explicit episodes
                    // OR there are no more pages OR the page came back empty.
                    // Do NOT stop just because items.isEmpty — check next instead,
                    // so we keep fetching through pages of all-explicit content.
                    if showEpisodes.count >= 3 || decoded.next == nil || items.isEmpty {
                        break
                    }
                    offset += limit
                } catch {
                    logger.error("Decoding error for podcast episodes: \(error.localizedDescription)")
                    throw error
                }
            }

            allEpisodes.append(contentsOf: showEpisodes.prefix(3))
        }

        logger.info("Successfully fetched \(allEpisodes.count) episodes for shows.")
        return allEpisodes
    }
    
    // MARK: - Search
    
    func searchAudiobookSeries(query: String) async throws -> [CuratedArtist] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        let token = try await getValidToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "artist")
        ]
        guard let url = components.url else { throw APIError.notAuthorized }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        var (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            let newToken = try await forceTokenRefresh()
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let retry = try await URLSession.shared.data(for: request)
            data = retry.0
            response = retry.1
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 400 { return [] }
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
        }
        
        struct SearchResponse: Decodable { let artists: ArtistsPage? }
        struct ArtistsPage: Decodable { let items: [LooseArtist]? }
        struct LooseArtist: Decodable { let id: String?; let name: String?; let images: [LooseImage]? }
        struct LooseImage: Decodable { let url: String?; let width: Int? }
        
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.artists?.items ?? []).compactMap { artist in
            guard let id = artist.id, let name = artist.name else { return nil }
            let imageURL = artist.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) }
            return CuratedArtist(id: id, name: name, imageURL: imageURL)
        }
    }
    
    func searchMusicPlaylists(query: String) async throws -> [CuratedPlaylist] {
        logger.info("Fetching parent's music playlists to filter by: '\(query)'")
        
        var allPlaylists: [CuratedPlaylist] = []
        var offset = 0
        let limit = 50
        
        while true {
            let token = try await getValidToken()
            
            var components = URLComponents(string: "https://api.spotify.com/v1/me/playlists")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            guard let url = components.url else { break }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            var (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                let newToken = try await forceTokenRefresh()
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let retry = try await URLSession.shared.data(for: request)
                data = retry.0
                response = retry.1
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                if retryAfter > 10 {
                    throw APIError.rateLimited(retryAfter: retryAfter)
                }
                try await Task.sleep(for: .seconds(retryAfter))
                continue
            }
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
            }
            
            struct LoosePlaylistsResponse: Decodable { let items: [LoosePlaylist?]?; let next: String? }
            struct LoosePlaylist: Decodable { let id: String?; let name: String?; let images: [LooseImage?]? }
            struct LooseImage: Decodable { let url: String? }
            
            do {
                let looseResponse = try JSONDecoder().decode(LoosePlaylistsResponse.self, from: data)
                let items = looseResponse.items ?? []
                
                let pagePlaylists = items.compactMap { playlist -> CuratedPlaylist? in
                    guard let playlist = playlist, let id = playlist.id, let name = playlist.name else { return nil }
                    let imageURL = playlist.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                    return CuratedPlaylist(id: id, name: name, imageURL: imageURL)
                }
                
                allPlaylists.append(contentsOf: pagePlaylists)
                
                if looseResponse.next == nil || items.isEmpty || items.count < limit { break }
                offset += limit
            } catch {
                throw error
            }
        }
        
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allPlaylists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        
        return allPlaylists
    }
    
    func searchPodcastShows(query: String) async throws -> [CuratedShow] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        let token = try await getValidToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "show")
        ]
        guard let url = components.url else { throw APIError.notAuthorized }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        var (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            let newToken = try await forceTokenRefresh()
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let retry = try await URLSession.shared.data(for: request)
            data = retry.0
            response = retry.1
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 400 { return [] }
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorString)
        }
        
        struct SearchResponse: Decodable { let shows: ShowsPage? }
        struct ShowsPage: Decodable { let items: [LooseShow]? }
        struct LooseShow: Decodable { let id: String?; let name: String?; let images: [LooseImage]? }
        struct LooseImage: Decodable { let url: String?; let width: Int? }
        
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.shows?.items ?? []).compactMap { show in
            guard let id = show.id, let name = show.name else { return nil }
            let imageURL = show.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) }
            return CuratedShow(id: id, name: name, imageURL: imageURL)
        }
    }
    
    // MARK: - Crypto Helpers
    
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }
    
    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Errors
    
    enum APIError: Error, LocalizedError {
        case notAuthorized
        case httpError(statusCode: Int, message: String)
        case rateLimited(retryAfter: Int)
        case noNetwork
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "The app is not authorized. A grown-up needs to log in."
            case .httpError(let statusCode, let message): return "Spotify API Error (\(statusCode)): \(message)"
            case .rateLimited(let retryAfter):
                if retryAfter > 60 {
                    return "Spotify needs a break. Please try again a little later!"
                } else {
                    return "Spotify needs a break. Please try again in \(retryAfter) seconds."
                }
            case .noNetwork:
                return "Oh no! The internet is hiding. Please ask a grown-up to check the Wi-Fi."
            }
        }
    }
}

// MARK: - Date Parsing Helper

extension String {
    func convertedToDate() -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: self) { return date }
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: self) { return date }
        formatter.dateFormat = "yyyy"
        return formatter.date(from: self)
    }
}
