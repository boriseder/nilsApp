// Services Group
import Foundation
import Combine
import os
import CryptoKit

/// A native service to handle Spotify API calls.
/// Handles OAuth PKCE authentication, automatic token refresh, and fetching metadata with pagination.
@MainActor
final class SpotifyAPIService: ObservableObject {

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var requiresReauthentication: Bool = false

    private let logger = Logger(subsystem: "com.nilsapp", category: "SpotifyAPIService")
    private var codeVerifier: String = ""
    private var oauthState: String = ""

    struct AuthState: Codable {
        var accessToken: String
        var refreshToken: String
        var expirationDate: Date
    }
    private var authState: AuthState?

    init() { setupAPI() }

    private func setupAPI() {
        logger.debug("SpotifyAPIService initialized.")
        loadFromKeychain()
        if authState != nil {
            self.isAuthorized = authState?.expirationDate ?? .distantPast > Date()
            Task {
                do {
                    try await forceTokenRefresh()
                    self.isAuthorized = true
                    logger.info("Token refreshed on startup.")
                } catch {
                    logger.warning("Startup token refresh failed: \(error.localizedDescription)")
                }
            }
        } else {
            self.isAuthorized = false
        }
    }

    // MARK: - Authentication

    func getAuthorizationURL() -> URL? {
        logger.info("Generating OAuth URL for Admin login.")
        self.codeVerifier = generateCodeVerifier()
        self.oauthState   = generateCodeVerifier()
        guard let verifierData = codeVerifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: verifierData)
        let codeChallenge = base64URLEncode(Data(hash))
        var components = URLComponents(string: Constants.spotifyAuthorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: Constants.spotifyClientId),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: "\(Constants.spotifyRedirectURI)"),
            URLQueryItem(name: "state",                 value: self.oauthState),
            URLQueryItem(name: "scope",                 value: "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read playlist-read-private playlist-read-collaborative user-read-private user-read-email app-remote-control"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge",        value: codeChallenge)
        ]
        return components.url
    }

    func handleRedirectURL(_ url: URL) async throws {
        logger.info("Handling OAuth redirect URL.")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code  = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              state == self.oauthState else { throw APIError.notAuthorized }
        var request = URLRequest(url: URL(string: Constants.spotifyTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let redirectURIEncoded = "\(Constants.spotifyRedirectURI)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        request.httpBody = "client_id=\(Constants.spotifyClientId)&grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURIEncoded)&code_verifier=\(self.codeVerifier)".data(using: .utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data: data, response: response)
            self.isAuthorized = true; self.requiresReauthentication = false
            logger.info("OAuth redirect handled successfully.")
        } catch {
            self.isAuthorized = false; self.requiresReauthentication = true
            logger.error("OAuth redirect failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Token Management

    struct TokenResponse: Decodable {
        let access_token: String; let refresh_token: String?; let expires_in: Int
    }

    private func handleTokenResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw APIError.notAuthorized }
        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiration = Date().addingTimeInterval(TimeInterval(tr.expires_in - 60))
        let newRefresh = tr.refresh_token ?? self.authState?.refreshToken ?? ""
        guard !newRefresh.isEmpty else { throw APIError.notAuthorized }
        self.authState = AuthState(accessToken: tr.access_token, refreshToken: newRefresh, expirationDate: expiration)
        saveToKeychain()
    }

    func getValidToken() async throws -> String {
        guard let state = authState else { throw APIError.notAuthorized }
        if state.expirationDate > Date() { return state.accessToken }
        return try await forceTokenRefresh()
    }

    @discardableResult
    func forceTokenRefresh() async throws -> String {
        guard let state = authState else { throw APIError.notAuthorized }
        var request = URLRequest(url: URL(string: Constants.spotifyTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(Constants.spotifyClientId)&grant_type=refresh_token&refresh_token=\(state.refreshToken)".data(using: .utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data: data, response: response)
            self.isAuthorized = true; self.requiresReauthentication = false
            return self.authState!.accessToken
        } catch {
            self.isAuthorized = false; self.requiresReauthentication = true
            deleteFromKeychain(); throw APIError.notAuthorized
        }
    }

    // MARK: - Keychain

    private let keychainKey = "com.nilsapp.spotifyAuth"

    private func saveToKeychain() {
        guard let data = try? JSONEncoder().encode(self.authState) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keychainKey]
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var newItem = query; newItem[kSecValueData as String] = data; SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func loadFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keychainKey, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var ref: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let data = ref as? Data {
            self.authState = try? JSONDecoder().decode(AuthState.self, from: data)
            logger.info("Loaded Spotify auth from Keychain.")
        }
    }

    private func deleteFromKeychain() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keychainKey] as CFDictionary)
    }

    // MARK: - PartialResultError
    //
    // BUG 3 FIX: When Spotify returns a very long Retry-After (e.g. 85,000 seconds),
    // the old code threw and discarded every album fetched so far. On the next launch
    // the cache was empty, the app made the same requests, got rate-limited again, and
    // discarded again — an infinite loop.
    //
    // Fix: when a long rate-limit is hit, we stop fetching further pages but keep all
    // albums already collected. We then throw PartialResultError which carries those
    // albums out to the ViewModel. The ViewModel catches this specific error, saves
    // the partial albums to the cache BEFORE surfacing the error message to the UI.
    // On the next launch the cache is warm and no API call is made at all.

    struct PartialResultError: Error {
        let albums: [SpotifyAlbum]
        let retryAfter: Int
    }

    // MARK: - Data Fetching (Audiobooks)

    func fetchAudiobookAlbums(artistIds: [String]) async throws -> [SpotifyAlbum] {
        guard isAuthorized else { throw APIError.notAuthorized }
        var allAlbums: [SpotifyAlbum] = []
        var longRateLimitRetryAfter: Int? = nil

        for artistId in artistIds {
            // If we already hit a long rate limit, don't even attempt more artists.
            if longRateLimitRetryAfter != nil { break }

            let cleanId = artistId.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Fetching albums for artist: \(cleanId)")
            var nextURL: String? = "\(Constants.spotifyArtistsBase)/\(cleanId)/albums?include_groups=album"

            pageLoop: while let currentURLString = nextURL {
                guard let url = URL(string: currentURLString) else { break }
                let token = try await getValidToken()
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    let newToken = try await forceTokenRefresh()
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }

                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if wait <= 30 {
                        // Short wait — sleep and retry this page.
                        logger.warning("Rate limited — waiting \(wait)s.")
                        try await Task.sleep(for: .seconds(wait))
                        continue pageLoop
                    } else {
                        // Long rate limit — record it and stop fetching.
                        // Do NOT throw yet: we want to save partial results first.
                        logger.error("Long rate limit (\(wait)s) for artist \(cleanId). Stopping fetch.")
                        longRateLimitRetryAfter = wait
                        break pageLoop
                    }
                }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw APIError.httpError(statusCode: http.statusCode,
                                             message: String(data: data, encoding: .utf8) ?? "Unknown Error")
                }

                struct R: Decodable { let items: [A?]?; let next: String? }
                struct A: Decodable { let id: String?; let name: String?; let images: [I?]?; let uri: String? }
                struct I: Decodable { let url: String? }

                let decoded = try JSONDecoder().decode(R.self, from: data)
                let page = (decoded.items ?? []).compactMap { a -> SpotifyAlbum? in
                    guard let a, let id = a.id, let name = a.name, let uri = a.uri else { return nil }
                    let imageURL = a.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                    return SpotifyAlbum(id: id, name: name, imageURL: imageURL, uri: uri)
                }
                allAlbums.append(contentsOf: page)
                nextURL = decoded.next
            }
        }

        logger.info("Fetched \(allAlbums.count) albums total.")

        // If we hit a long rate limit, throw PartialResultError carrying whatever
        // albums were collected. The ViewModel catches this and saves them to cache
        // before displaying the error — so the next launch gets a cache hit.
        if let wait = longRateLimitRetryAfter {
            throw PartialResultError(albums: allAlbums, retryAfter: wait)
        }

        return allAlbums
    }

    // MARK: - Data Fetching (Music)

    func fetchPlaylistTracks(playlistIds: [String]) async throws -> [SpotifyTrack] {
        guard isAuthorized else { throw APIError.notAuthorized }
        var allTracks: [SpotifyTrack] = []
        for playlistId in playlistIds {
            let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
            var offset = 0; let limit = 100
            while true {
                let token = try await getValidToken()
                var components = URLComponents(string: "\(Constants.spotifyPlaylistsBase)/\(cleanId)/items")!
                components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)"), URLQueryItem(name: "offset", value: "\(offset)")]
                guard let url = components.url else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    let t = try await forceTokenRefresh(); request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if wait > 30 { throw APIError.rateLimited(retryAfter: wait) }
                    try await Task.sleep(for: .seconds(wait)); continue
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if http.statusCode == 403 { logger.warning("403 for playlist \(cleanId). Skipping."); break }
                    throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
                }
                struct R: Decodable { let items: [PI?]?; let next: String? }
                struct PI: Decodable { let track: T?; let item: T? }
                struct T: Decodable { let id: String?; let name: String?; let artists: [Ar?]?; let album: Al?; let uri: String?; let duration_ms: Int?; let explicit: Bool? }
                struct Ar: Decodable { let name: String? }
                struct Al: Decodable { let images: [Im?]? }
                struct Im: Decodable { let url: String? }
                let decoded = try JSONDecoder().decode(R.self, from: data)
                guard let items = decoded.items else { break }
                allTracks.append(contentsOf: items.compactMap { li -> SpotifyTrack? in
                    guard let t = li?.track ?? li?.item, t.explicit != true,
                          let id = t.id, let name = t.name, let uri = t.uri else { return nil }
                    let artist = t.artists?.compactMap { $0 }.first?.name ?? "Unknown Artist"
                    let imageURL = t.album?.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                    return SpotifyTrack(id: id, name: name, artistName: artist, imageURL: imageURL, uri: uri, duration: TimeInterval(t.duration_ms ?? 0) / 1000.0)
                })
                if decoded.next == nil || items.isEmpty { break }
                offset += limit
            }
        }
        logger.info("Fetched \(allTracks.count) tracks total.")
        return allTracks
    }

    // MARK: - Data Fetching (Podcasts)

    func fetchPodcastEpisodes(showIds: [String]) async throws -> [SpotifyEpisode] {
        guard isAuthorized else { throw APIError.notAuthorized }
        var allEpisodes: [SpotifyEpisode] = []
        for showId in showIds {
            let cleanId = showId.trimmingCharacters(in: .whitespacesAndNewlines)
            var showEpisodes: [SpotifyEpisode] = []; var offset = 0; let limit = 10
            while true {
                let token = try await getValidToken()
                var components = URLComponents(string: "\(Constants.spotifyShowsBase)/\(cleanId)/episodes")!
                components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)"), URLQueryItem(name: "offset", value: "\(offset)"), URLQueryItem(name: "market", value: Constants.defaultMarket)]
                guard let url = components.url else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    let t = try await forceTokenRefresh(); request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    if wait > 30 { throw APIError.rateLimited(retryAfter: wait) }
                    try await Task.sleep(for: .seconds(wait)); continue
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
                }
                struct R: Decodable { let items: [E?]?; let next: String? }
                struct E: Decodable { let id: String?; let name: String?; let description: String?; let images: [Im?]?; let uri: String?; let duration_ms: Int?; let release_date: String?; let explicit: Bool? }
                struct Im: Decodable { let url: String? }
                let decoded = try JSONDecoder().decode(R.self, from: data)
                guard let items = decoded.items else { break }
                showEpisodes.append(contentsOf: items.compactMap { ep -> SpotifyEpisode? in
                    guard let e = ep, e.explicit != true, let id = e.id, let name = e.name, let uri = e.uri else { return nil }
                    let imageURL = e.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) }
                    return SpotifyEpisode(id: id, name: name, description: e.description ?? "", imageURL: imageURL, uri: uri, duration: TimeInterval(e.duration_ms ?? 0) / 1000.0, releaseDate: e.release_date?.convertedToDate())
                })
                if showEpisodes.count >= 3 || decoded.next == nil || items.isEmpty { break }
                offset += limit
            }
            allEpisodes.append(contentsOf: showEpisodes.prefix(3))
        }
        logger.info("Fetched \(allEpisodes.count) episodes total.")
        return allEpisodes
    }

    // MARK: - Search

    func searchAudiobookSeries(query: String) async throws -> [CuratedArtist] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let token = try await getValidToken()
        var components = URLComponents(string: Constants.spotifySearch)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "artist")]
        guard let url = components.url else { throw APIError.notAuthorized }
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let t = try await forceTokenRefresh(); request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 400 { return [] }
            throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        struct R: Decodable { let artists: AP? }; struct AP: Decodable { let items: [A]? }
        struct A: Decodable { let id: String?; let name: String?; let images: [Im]? }; struct Im: Decodable { let url: String?; let width: Int? }
        return ((try JSONDecoder().decode(R.self, from: data)).artists?.items ?? []).compactMap { a in
            guard let id = a.id, let name = a.name else { return nil }
            let imageURL = a.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) }
            return CuratedArtist(id: id, name: name, imageURL: imageURL)
        }
    }

    func searchMusicPlaylists(query: String) async throws -> [CuratedPlaylist] {
        var allPlaylists: [CuratedPlaylist] = []; var offset = 0; let limit = 50
        while true {
            let token = try await getValidToken()
            var components = URLComponents(string: Constants.spotifyMyPlaylists)!
            components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)"), URLQueryItem(name: "offset", value: "\(offset)")]
            guard let url = components.url else { break }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                let t = try await forceTokenRefresh(); request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                (data, response) = try await URLSession.shared.data(for: request)
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                if wait > 10 { throw APIError.rateLimited(retryAfter: wait) }
                try await Task.sleep(for: .seconds(wait)); continue
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
            }
            struct R: Decodable { let items: [P?]?; let next: String? }; struct P: Decodable { let id: String?; let name: String?; let images: [Im?]? }; struct Im: Decodable { let url: String? }
            let decoded = try JSONDecoder().decode(R.self, from: data); let items = decoded.items ?? []
            allPlaylists.append(contentsOf: items.compactMap { p -> CuratedPlaylist? in
                guard let p, let id = p.id, let name = p.name else { return nil }
                return CuratedPlaylist(id: id, name: name, imageURL: p.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) })
            })
            if decoded.next == nil || items.isEmpty || items.count < limit { break }
            offset += limit
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allPlaylists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return allPlaylists
    }

    func searchPodcastShows(query: String) async throws -> [CuratedShow] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let token = try await getValidToken()
        var components = URLComponents(string: Constants.spotifySearch)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "show")]
        guard let url = components.url else { throw APIError.notAuthorized }
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let t = try await forceTokenRefresh(); request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 400 { return [] }
            throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        struct R: Decodable { let shows: SP? }; struct SP: Decodable { let items: [S]? }
        struct S: Decodable { let id: String?; let name: String?; let images: [Im]? }; struct Im: Decodable { let url: String?; let width: Int? }
        return ((try JSONDecoder().decode(R.self, from: data)).shows?.items ?? []).compactMap { s in
            guard let id = s.id, let name = s.name else { return nil }
            let imageURL = s.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) }
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
        data.base64EncodedString()
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
            case .httpError(let c, let m): return "Spotify API Error (\(c)): \(m)"
            case .rateLimited(let w): return w > 60
                ? "Spotify needs a break. Try again a little later!"
                : "Spotify needs a break. Try again in \(w) seconds."
            case .noNetwork: return "Oh no! The internet is hiding. Please ask a grown-up to check the Wi-Fi."
            }
        }
    }
}

extension String {
    func convertedToDate() -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; if let d = f.date(from: self) { return d }
        f.dateFormat = "yyyy-MM";    if let d = f.date(from: self) { return d }
        f.dateFormat = "yyyy";       return f.date(from: self)
    }
}
