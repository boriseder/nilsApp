// Services Group
import Foundation
import Combine
import os
import CryptoKit

/// A native service to handle Spotify API calls.
@MainActor
final class SpotifyAPIService: ObservableObject {

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var requiresReauthentication: Bool = false

    private let logger = Logger(subsystem: "com.nilsapp", category: "SpotifyAPIService")
    private var codeVerifier: String = ""
    private var oauthState: String = ""
    private var refreshTask: Task<String, Error>?

    struct AuthState: Codable {
        var accessToken: String; var refreshToken: String; var expirationDate: Date
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
        self.codeVerifier = generateCodeVerifier()
        self.oauthState   = generateCodeVerifier()
        guard let verifierData = codeVerifier.data(using: .ascii) else { return nil }
        let codeChallenge = base64URLEncode(Data(SHA256.hash(data: verifierData)))
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code  = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              state == self.oauthState else { throw APIError.notAuthorized }
        var request = URLRequest(url: URL(string: Constants.spotifyTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let enc = "\(Constants.spotifyRedirectURI)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        request.httpBody = "client_id=\(Constants.spotifyClientId)&grant_type=authorization_code&code=\(code)&redirect_uri=\(enc)&code_verifier=\(self.codeVerifier)".data(using: .utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data: data, response: response)
            self.isAuthorized = true; self.requiresReauthentication = false
        } catch {
            self.isAuthorized = false; self.requiresReauthentication = true; throw error
        }
    }

    // MARK: - Token Management

    struct TokenResponse: Decodable {
        let access_token: String; let refresh_token: String?; let expires_in: Int
    }

    private func handleTokenResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.notAuthorized
        }
        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newRefresh = tr.refresh_token ?? self.authState?.refreshToken ?? ""
        guard !newRefresh.isEmpty else { throw APIError.notAuthorized }
        self.authState = AuthState(
            accessToken:    tr.access_token,
            refreshToken:   newRefresh,
            expirationDate: Date().addingTimeInterval(TimeInterval(tr.expires_in - 60))
        )
        saveToKeychain()
    }

    func getValidToken() async throws -> String {
        guard let state = authState else { throw APIError.notAuthorized }
        if state.expirationDate > Date() { return state.accessToken }
        return try await forceTokenRefresh()
    }

    @discardableResult
    func forceTokenRefresh() async throws -> String {
        if let existing = refreshTask { return try await existing.value }
        let task = Task<String, Error> {
            defer { self.refreshTask = nil }
            guard let state = self.authState else { throw APIError.notAuthorized }
            var request = URLRequest(url: URL(string: Constants.spotifyTokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "client_id=\(Constants.spotifyClientId)&grant_type=refresh_token&refresh_token=\(state.refreshToken)".data(using: .utf8)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try self.handleTokenResponse(data: data, response: response)
                self.isAuthorized = true; self.requiresReauthentication = false
                return self.authState!.accessToken
            } catch {
                self.isAuthorized = false; self.requiresReauthentication = true
                self.deleteFromKeychain(); throw APIError.notAuthorized
            }
        }
        self.refreshTask = task
        return try await task.value
    }

    // MARK: - Keychain

    private let keychainKey = "com.nilsapp.spotifyAuth"

    private func saveToKeychain() {
        guard let data = try? JSONEncoder().encode(self.authState) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: keychainKey]
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var n = q; n[kSecValueData as String] = data; SecItemAdd(n as CFDictionary, nil)
        }
    }

    private func loadFromKeychain() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: keychainKey,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var ref: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
           let data = ref as? Data {
            self.authState = try? JSONDecoder().decode(AuthState.self, from: data)
            logger.info("Loaded Spotify auth from Keychain.")
        }
    }

    private func deleteFromKeychain() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: keychainKey] as CFDictionary)
    }

    // MARK: - Partial Result Error Types

    struct PartialAlbumsError:   Error { let albums:   [SpotifyAlbum];   let retryAfter: Int }
    struct PartialTracksError:   Error { let tracks:   [SpotifyTrack];   let retryAfter: Int }
    struct PartialEpisodesError: Error { let episodes: [SpotifyEpisode]; let retryAfter: Int }

    // MARK: - Data Fetching (Audiobooks) — Delta-aware
    //
    // Delta fetch strategy:
    //
    //   1. For each artist, fire a cheap probe request (limit=1) to get Spotify's
    //      current `total` album count.
    //   2. Compare against `knownTotals[artistId]` passed in from the cache.
    //      • Equal  → skip — nothing new, reuse existing cached albums for this artist.
    //      • Higher → fetch only the new pages starting at offset=knownTotal.
    //      • Lower  → artist deleted albums (rare); full re-fetch for this artist only.
    //      • Missing (cold) → full fetch from offset 0.
    //   3. Merge new albums into the existing set and return the combined result
    //      along with updated totals so the caller can persist them.
    //
    // On a typical warm launch with no new releases this costs exactly 1 probe
    // request per artist — e.g. 10 artists = 10 small requests instead of 40+.

    struct AlbumFetchResult {
        let albums: [SpotifyAlbum]
        let totalCounts: [String: Int]  // updated per-artist totals to persist
    }

    func fetchAudiobookAlbums(
        artistIds: [String],
        knownTotals: [String: Int] = [:],
        existingAlbums: [SpotifyAlbum] = []
    ) async throws -> AlbumFetchResult {
        guard isAuthorized else { throw APIError.notAuthorized }

        // Start with whatever the caller already has cached so we can append deltas.
        // Key by album ID to deduplicate gracefully.
        var albumMap: [String: SpotifyAlbum] = Dictionary(
            uniqueKeysWithValues: existingAlbums.map { ($0.id, $0) }
        )
        var updatedTotals: [String: Int] = knownTotals
        var longWait: Int? = nil

        for (index, artistId) in artistIds.enumerated() {
            if longWait != nil { break }

            if index > 0 {
                try await Task.sleep(for: .milliseconds(200))
            }

            let cleanId = artistId.trimmingCharacters(in: .whitespacesAndNewlines)

            // ── Step 1: Probe ──────────────────────────────────────────────────────
            // Fetch limit=1 just to read the `total` field cheaply.
            let probeURLString = "\(Constants.spotifyArtistsBase)/\(cleanId)/albums?include_groups=album&limit=1"
            guard let probeURL = URL(string: probeURLString) else { continue }
            var probeReq = URLRequest(url: probeURL)
            probeReq.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
            var (probeData, probeResponse) = try await URLSession.shared.data(for: probeReq)

            if let http = probeResponse as? HTTPURLResponse, http.statusCode == 401 {
                probeReq.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
                (probeData, probeResponse) = try await URLSession.shared.data(for: probeReq)
            }
            if let http = probeResponse as? HTTPURLResponse, http.statusCode == 429 {
                let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                logger.error("Rate limited (\(wait)s) on probe for artist \(cleanId).")
                if wait <= 30 { try await Task.sleep(for: .seconds(wait)) }
                else { longWait = wait; break }
                // Retry the probe after sleeping — restart this artist's iteration.
                (probeData, probeResponse) = try await URLSession.shared.data(for: probeReq)
            }
            guard let probeHTTP = probeResponse as? HTTPURLResponse,
                  (200...299).contains(probeHTTP.statusCode) else { continue }

            struct ProbeResponse: Decodable { let total: Int }
            guard let probe = try? JSONDecoder().decode(ProbeResponse.self, from: probeData) else { continue }
            let spotifyTotal = probe.total

            // ── Step 2: Delta decision ─────────────────────────────────────────────
            let knownTotal = knownTotals[cleanId]

            if let known = knownTotal, known == spotifyTotal {
                // Nothing changed — skip this artist entirely.
                logger.info("Artist \(cleanId): total unchanged (\(spotifyTotal)). Skipping fetch.")
                continue
            }

            if let known = knownTotal, spotifyTotal < known {
                // Artist removed albums — rare, but do a full re-fetch to stay correct.
                // Remove old albums for this artist from the map first.
                logger.info("Artist \(cleanId): total decreased (\(known) → \(spotifyTotal)). Full re-fetch.")
                // We don't have a direct artistId on SpotifyAlbum, so we'll just re-fetch
                // all pages and let deduplication handle it.
            }

            // Fetch only the pages we don't have yet.
            // Cold: startOffset = 0. Delta: startOffset = knownTotal.
            // If total decreased we also start at 0 (full re-fetch branch above).
            let startOffset = (knownTotal != nil && spotifyTotal > knownTotal!) ? knownTotal! : 0
            logger.info("Artist \(cleanId): fetching from offset \(startOffset) (Spotify total: \(spotifyTotal)).")

            // ── Step 3: Fetch new pages ────────────────────────────────────────────
            var offset = startOffset
            let limit  = 50

            pageLoop: while offset < spotifyTotal {
                let urlString = "\(Constants.spotifyArtistsBase)/\(cleanId)/albums?include_groups=album&limit=\(limit)&offset=\(offset)"
                guard let url = URL(string: urlString) else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    logger.error("Rate limited (\(wait)s) fetching albums for artist \(cleanId).")
                    if wait <= 30 { try await Task.sleep(for: .seconds(wait)); continue pageLoop }
                    longWait = wait; break pageLoop
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw APIError.httpError(statusCode: http.statusCode,
                                             message: String(data: data, encoding: .utf8) ?? "")
                }

                struct R: Decodable { let items: [A?]?; let next: String? }
                struct A: Decodable { let id: String?; let name: String?; let images: [I?]?; let uri: String? }
                struct I: Decodable { let url: String? }

                let decoded = try JSONDecoder().decode(R.self, from: data)
                let page = (decoded.items ?? []).compactMap { a -> SpotifyAlbum? in
                    guard let a, let id = a.id, let name = a.name, let uri = a.uri else { return nil }
                    return SpotifyAlbum(id: id, name: name,
                                        imageURL: a.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) },
                                        uri: uri)
                }
                page.forEach { albumMap[$0.id] = $0 }

                if decoded.next == nil || page.isEmpty { break }
                offset += limit
            }

            // Update the stored total for this artist regardless of partial/full fetch.
            updatedTotals[cleanId] = spotifyTotal
        }

        let allAlbums = Array(albumMap.values)

        if let wait = longWait {
            throw PartialAlbumsError(albums: allAlbums, retryAfter: wait)
        }

        logger.info("fetchAudiobookAlbums complete — \(allAlbums.count) albums total, totals: \(updatedTotals).")
        return AlbumFetchResult(albums: allAlbums, totalCounts: updatedTotals)
    }

    // MARK: - Data Fetching (Music)

    func fetchPlaylistTracks(playlistIds: [String]) async throws -> [SpotifyTrack] {
        guard isAuthorized else { throw APIError.notAuthorized }
        var allTracks: [SpotifyTrack] = []
        var longWait: Int? = nil

        for (index, playlistId) in playlistIds.enumerated() {
            if longWait != nil { break }
            if index > 0 { try await Task.sleep(for: .milliseconds(200)) }

            let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
            var offset = 0; let limit = 100

            pageLoop: while true {
                var components = URLComponents(string: "\(Constants.spotifyPlaylistsBase)/\(cleanId)/items")!
                components.queryItems = [
                    URLQueryItem(name: "limit",  value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)")
                ]
                guard let url = components.url else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    logger.error("Rate limited (\(wait)s) for playlist \(cleanId).")
                    if wait <= 30 { try await Task.sleep(for: .seconds(wait)); continue pageLoop }
                    longWait = wait; break pageLoop
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if http.statusCode == 403 { logger.warning("403 for playlist \(cleanId). Skipping."); break }
                    throw APIError.httpError(statusCode: http.statusCode,
                                             message: String(data: data, encoding: .utf8) ?? "")
                }

                struct R:  Decodable { let items: [PI?]?; let next: String? }
                struct PI: Decodable { let track: T?; let item: T? }
                struct T:  Decodable { let id: String?; let name: String?; let artists: [Ar?]?;
                                       let album: Al?; let uri: String?; let duration_ms: Int?; let explicit: Bool? }
                struct Ar: Decodable { let name: String? }
                struct Al: Decodable { let images: [Im?]? }
                struct Im: Decodable { let url: String? }

                let decoded = try JSONDecoder().decode(R.self, from: data)
                guard let items = decoded.items else { break }
                allTracks.append(contentsOf: items.compactMap { li -> SpotifyTrack? in
                    guard let t = li?.track ?? li?.item, t.explicit != true,
                          let id = t.id, let name = t.name, let uri = t.uri else { return nil }
                    return SpotifyTrack(id: id, name: name,
                                        artistName: t.artists?.compactMap { $0 }.first?.name ?? "Unknown Artist",
                                        imageURL: t.album?.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) },
                                        uri: uri,
                                        duration: TimeInterval(t.duration_ms ?? 0) / 1000.0)
                })
                if decoded.next == nil || items.isEmpty { break }
                offset += limit
            }
        }

        if let wait = longWait { throw PartialTracksError(tracks: allTracks, retryAfter: wait) }
        logger.info("Fetched \(allTracks.count) tracks for \(playlistIds.count) playlists.")
        return allTracks
    }

    // MARK: - Data Fetching (Podcasts)

    func fetchPodcastEpisodes(showIds: [String]) async throws -> [SpotifyEpisode] {
        guard isAuthorized else { throw APIError.notAuthorized }
        var allEpisodes: [SpotifyEpisode] = []
        var longWait: Int? = nil

        for (index, showId) in showIds.enumerated() {
            if longWait != nil { break }
            if index > 0 { try await Task.sleep(for: .milliseconds(200)) }

            let cleanId = showId.trimmingCharacters(in: .whitespacesAndNewlines)
            var showEpisodes: [SpotifyEpisode] = []
            var offset = 0
            let limit  = 10   // fetch 50 at a time; filter explicit client-side

            pageLoop: while true {
                var components = URLComponents(string: "\(Constants.spotifyShowsBase)/\(cleanId)/episodes")!
                components.queryItems = [
                    URLQueryItem(name: "limit",  value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)"),
                    URLQueryItem(name: "market", value: Constants.defaultMarket)
                ]
                guard let url = components.url else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
                var (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                    logger.error("Rate limited (\(wait)s) for show \(cleanId).")
                    if wait <= 30 { try await Task.sleep(for: .seconds(wait)); continue pageLoop }
                    longWait = wait; break pageLoop
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw APIError.httpError(statusCode: http.statusCode,
                                             message: String(data: data, encoding: .utf8) ?? "")
                }

                struct R:  Decodable { let items: [E?]?; let next: String? }
                struct E:  Decodable { let id: String?; let name: String?; let description: String?;
                                       let images: [Im?]?; let uri: String?; let duration_ms: Int?;
                                       let release_date: String?; let explicit: Bool? }
                struct Im: Decodable { let url: String? }

                let decoded = try JSONDecoder().decode(R.self, from: data)
                guard let items = decoded.items else { break }

                showEpisodes.append(contentsOf: items.compactMap { ep -> SpotifyEpisode? in
                    guard let e = ep, e.explicit != true,
                          let id = e.id, let name = e.name, let uri = e.uri else { return nil }
                    return SpotifyEpisode(id: id, name: name, description: e.description ?? "",
                                          imageURL: e.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) },
                                          uri: uri,
                                          duration: TimeInterval(e.duration_ms ?? 0) / 1000.0,
                                          releaseDate: e.release_date?.convertedToDate())
                })

                if showEpisodes.count >= 3 || decoded.next == nil || items.isEmpty { break }
                offset += limit
            }

            allEpisodes.append(contentsOf: showEpisodes.prefix(3))
        }

        if let wait = longWait { throw PartialEpisodesError(episodes: allEpisodes, retryAfter: wait) }
        logger.info("Fetched \(allEpisodes.count) episodes for \(showIds.count) shows.")
        return allEpisodes
    }

    // MARK: - Search

    func searchAudiobookSeries(query: String) async throws -> [CuratedArtist] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: Constants.spotifySearch)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "artist")]
        guard let url = components.url else { throw APIError.notAuthorized }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
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
            return CuratedArtist(id: id, name: name, imageURL: a.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) })
        }
    }

    func searchMusicPlaylists(query: String) async throws -> [CuratedPlaylist] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return try await fetchAllUserPlaylists() }
        var components = URLComponents(string: Constants.spotifySearch)!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "type", value: "playlist"), URLQueryItem(name: "limit", value: "20")]
        guard let url = components.url else { throw APIError.notAuthorized }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try parsePlaylistSearch(data: data, response: response)
    }

    private func fetchAllUserPlaylists() async throws -> [CuratedPlaylist] {
        var all: [CuratedPlaylist] = []; var offset = 0; let limit = 50
        while true {
            var components = URLComponents(string: Constants.spotifyMyPlaylists)!
            components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)"), URLQueryItem(name: "offset", value: "\(offset)")]
            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
            var (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
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
            all.append(contentsOf: items.compactMap { p -> CuratedPlaylist? in
                guard let p, let id = p.id, let name = p.name else { return nil }
                return CuratedPlaylist(id: id, name: name, imageURL: p.images?.compactMap { $0 }.first?.url.flatMap { URL(string: $0) })
            })
            if decoded.next == nil || items.isEmpty || items.count < limit { break }
            offset += limit
        }
        return all
    }

    private func parsePlaylistSearch(data: Data, response: URLResponse) throws -> [CuratedPlaylist] {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Search failed")
        }
        struct R: Decodable { let playlists: P? }; struct P: Decodable { let items: [I]? }
        struct I: Decodable { let id: String?; let name: String?; let images: [Im]? }; struct Im: Decodable { let url: String? }
        return ((try JSONDecoder().decode(R.self, from: data)).playlists?.items ?? []).compactMap { item in
            guard let id = item.id, let name = item.name else { return nil }
            return CuratedPlaylist(id: id, name: name, imageURL: item.images?.first?.url.flatMap { URL(string: $0) })
        }
    }

    func searchPodcastShows(query: String) async throws -> [CuratedShow] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: Constants.spotifySearch)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "show")]
        guard let url = components.url else { throw APIError.notAuthorized }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await getValidToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            request.setValue("Bearer \(try await forceTokenRefresh())", forHTTPHeaderField: "Authorization")
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
            return CuratedShow(id: id, name: name, imageURL: s.images?.max(by: { $0.width ?? 0 < $1.width ?? 0 })?.url.flatMap { URL(string: $0) })
        }
    }

    // MARK: - Crypto Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
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
            case .notAuthorized:           return "The app is not authorized. A grown-up needs to log in."
            case .httpError(let c, let m): return "Spotify API Error (\(c)): \(m)"
            case .rateLimited(let w):      return w > 60 ? "Spotify needs a break. Try again later!" : "Spotify needs a break. Try again in \(w) seconds."
            case .noNetwork:               return "Oh no! The internet is hiding. Please ask a grown-up to check the Wi-Fi."
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
