// Services Group
import Foundation
import Combine
import os

/// Service responsible for saving and loading the parent's curated content
/// to and from the device's local filesystem.
@MainActor
final class PersistenceService: ObservableObject {

    @Published private(set) var curatedContent: CuratedContent

    // Cached API data — kept as published so views can react to them.
    @Published private(set) var cachedAlbums: [SpotifyAlbum] = []
    @Published private(set) var cachedTracks: [SpotifyTrack] = []
    @Published private(set) var cachedEpisodes: [SpotifyEpisode] = []

    private let fileName = "curated_content.json"

    // Albums change rarely (weekly at best) — 7 days avoids redundant fetches.
    // Tracks and episodes change more often — keep at 24h.
    private let albumCacheAge:   TimeInterval = 60 * 60 * 24 * 7  // 7 days
    private let defaultCacheAge: TimeInterval = 60 * 60 * 24      // 24 h

    private let logger = Logger(subsystem: "com.nilsapp", category: "PersistenceService")

    // MARK: - Generic Cache Envelope
    //
    // `totalCounts` maps each content ID (artistId / playlistId / showId) to the
    // total item count that Spotify reported at the time of the last fetch.
    // The delta-fetch logic uses this to detect new content without re-fetching
    // existing pages: if Spotify's current total == our cached total, skip the fetch.

    private struct Cache<T: Codable>: Codable {
        let ids: [String]
        let items: [T]
        let fetchedAt: Date
        let totalCounts: [String: Int]   // contentId → Spotify total at last fetch
    }

    // MARK: - Codable Mirrors

    private struct CodableAlbum: Codable {
        let id, name, uri, artistId: String
        let imageURL: URL?
        init(_ m: SpotifyAlbum) { id = m.id; name = m.name; uri = m.uri; imageURL = m.imageURL; artistId = m.artistId }
        var model: SpotifyAlbum { SpotifyAlbum(id: id, name: name, imageURL: imageURL, uri: uri, artistId: artistId) }
    }

    private struct CodableTrack: Codable {
        let id, name, artistName, uri: String
        let imageURL: URL?
        let duration: TimeInterval
        init(_ m: SpotifyTrack) { id = m.id; name = m.name; artistName = m.artistName; uri = m.uri; imageURL = m.imageURL; duration = m.duration }
        var model: SpotifyTrack { SpotifyTrack(id: id, name: name, artistName: artistName, imageURL: imageURL, uri: uri, duration: duration) }
    }

    private struct CodableEpisode: Codable {
        let id, name, description, uri: String
        let imageURL: URL?
        let duration: TimeInterval
        let releaseDate: Date?
        init(_ m: SpotifyEpisode) { id = m.id; name = m.name; description = m.description; uri = m.uri; imageURL = m.imageURL; duration = m.duration; releaseDate = m.releaseDate }
        var model: SpotifyEpisode { SpotifyEpisode(id: id, name: name, description: description, imageURL: imageURL, uri: uri, duration: duration, releaseDate: releaseDate) }
    }

    // MARK: - Cache file names

    private enum CacheFile {
        static let albums   = "cache_albums.json"
        static let tracks   = "cache_tracks.json"
        static let episodes = "cache_episodes.json"
    }

    // In-memory cache to avoid repeated disk reads + JSON decodes within a single session.
    private var albumCacheInMemory:   Cache<CodableAlbum>?
    private var trackCacheInMemory:   Cache<CodableTrack>?
    private var episodeCacheInMemory: Cache<CodableEpisode>?

    // MARK: - Init

    init() {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        func readCache<T: Decodable>(_ file: String) -> Cache<T>? {
            guard let data = try? Data(contentsOf: docDir.appendingPathComponent(file)) else { return nil }
            return try? JSONDecoder().decode(Cache<T>.self, from: data)
        }

        let loaded: CuratedContent
        if let data = try? Data(contentsOf: docDir.appendingPathComponent("curated_content.json")),
           let decoded = try? JSONDecoder().decode(CuratedContent.self, from: data) {
            loaded = decoded
        } else {
            loaded = .empty
        }
        self.curatedContent = loaded

        let artistIds   = loaded.audiobookSeries.map(\.id)
        let playlistIds = loaded.musicPlaylists.map(\.id)
        let showIds     = loaded.podcastShows.map(\.id)

        // Albums use the 7-day TTL on startup pre-population too.
        if !artistIds.isEmpty,
           let cache: Cache<CodableAlbum> = readCache(CacheFile.albums),
           cache.ids.sorted() == artistIds.sorted(),
           Date().timeIntervalSince(cache.fetchedAt) < 60 * 60 * 24 * 7 {
            self.cachedAlbums = cache.items.map(\.model)
        }

        if !playlistIds.isEmpty,
           let cache: Cache<CodableTrack> = readCache(CacheFile.tracks),
           cache.ids.sorted() == playlistIds.sorted(),
           Date().timeIntervalSince(cache.fetchedAt) < 60 * 60 * 24 {
            self.cachedTracks = cache.items.map(\.model)
        }

        if !showIds.isEmpty,
           let cache: Cache<CodableEpisode> = readCache(CacheFile.episodes),
           cache.ids.sorted() == showIds.sorted(),
           Date().timeIntervalSince(cache.fetchedAt) < 60 * 60 * 24 {
            self.cachedEpisodes = cache.items.map(\.model)
        }
    }

    // MARK: - Curated Content

    func save(_ content: CuratedContent) {
        // Optimistically update the published state immediately so the UI reacts
        self.curatedContent = content
        
        // Background the heavy JSON encoding and disk write so it doesn't block the Main Thread
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(content)
                // Use a local copy of fileURL logic to avoid accessing MainActor state
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("curated_content.json")
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                
                Task { @MainActor in
                    self.logger.info("Successfully saved curated content to disk.")
                }
            } catch {
                Task { @MainActor in
                    self.logger.error("Failed to save curated content: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Albums Cache
    //
    // Albums use delta-aware cache logic:
    //   • loadAlbums(for:) returns cached albums if the ID set matches AND cache is < 7 days old.
    //   • albumTotalCounts() returns the per-artist totals stored at last fetch,
    //     so the API layer can probe Spotify's current total and skip artists that haven't changed.
    //   • loadAllCachedAlbums() returns whatever the cache currently holds so the API
    //     can append deltas without losing previously fetched data.

    func loadAlbums(for artistIds: [String]) -> [SpotifyAlbum]? {
        guard let cache: Cache<CodableAlbum> = loadCache(from: CacheFile.albums),
              isValid(cache, maxAge: albumCacheAge),
              artistIds.allSatisfy({ cache.ids.contains($0) }) else { return nil }
        let requested = Set(artistIds)
        let filtered = cache.items.filter { requested.contains($0.artistId) }.map(\.model)
        logger.info("Albums cache hit — \(filtered.count) albums for \(artistIds.count) artist(s).")
        return filtered
    }

    /// Returns the per-artist total counts stored at the last successful fetch,
    /// regardless of whether the current artist list has changed.
    func albumTotalCounts() -> [String: Int] {
        guard let cache: Cache<CodableAlbum> = loadCache(from: CacheFile.albums) else { return [:] }
        return cache.totalCounts
    }
    
    /// Returns all previously cached albums so the API service can merge them
    /// with new delta data, even if the artist list just changed.
    func loadAllCachedAlbums() -> [SpotifyAlbum] {
        guard let cache: Cache<CodableAlbum> = loadCache(from: CacheFile.albums) else { return [] }
        return cache.items.map(\.model)
    }

    func saveAlbums(_ albums: [SpotifyAlbum], for artistIds: [String], totalCounts: [String: Int]) {
        // saveCache updates the in-memory copy synchronously before dispatching the disk
        // write to a background task — so cachedAlbums and in-memory are always consistent
        // even if the app is killed before the disk write completes.
        let cache = Cache(ids: artistIds, items: albums.map(CodableAlbum.init),
                          fetchedAt: Date(), totalCounts: totalCounts)
        saveCache(cache, to: CacheFile.albums)
        cachedAlbums = albums
        logger.info("Albums cache saved — \(albums.count) albums, totals: \(totalCounts).")
    }

    func clearAlbumsCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.albums))
        albumCacheInMemory = nil
        cachedAlbums = []
        logger.info("Albums cache cleared.")
    }

    // MARK: - Tracks Cache

    func loadTracks(for playlistIds: [String]) -> [SpotifyTrack]? {
        guard let cache: Cache<CodableTrack> = loadCache(from: CacheFile.tracks),
              cache.ids.sorted() == playlistIds.sorted(),
              isValid(cache, maxAge: defaultCacheAge) else { return nil }
        logger.info("Tracks cache hit — \(cache.items.count) tracks.")
        return cache.items.map(\.model)
    }

    func saveTracks(_ tracks: [SpotifyTrack], for playlistIds: [String]) {
        saveCache(
            Cache(ids: playlistIds, items: tracks.map(CodableTrack.init),
                  fetchedAt: Date(), totalCounts: [:]),
            to: CacheFile.tracks
        )
        cachedTracks = tracks
        logger.info("Tracks cache saved — \(tracks.count) tracks.")
    }

    func clearTracksCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.tracks))
        cachedTracks = []
        logger.info("Tracks cache cleared.")
    }

    // MARK: - Episodes Cache

    func loadEpisodes(for showIds: [String]) -> [SpotifyEpisode]? {
        guard let cache: Cache<CodableEpisode> = loadCache(from: CacheFile.episodes),
              cache.ids.sorted() == showIds.sorted(),
              isValid(cache, maxAge: defaultCacheAge) else { return nil }
        logger.info("Episodes cache hit — \(cache.items.count) episodes.")
        return cache.items.map(\.model)
    }

    func saveEpisodes(_ episodes: [SpotifyEpisode], for showIds: [String]) {
        saveCache(
            Cache(ids: showIds, items: episodes.map(CodableEpisode.init),
                  fetchedAt: Date(), totalCounts: [:]),
            to: CacheFile.episodes
        )
        cachedEpisodes = episodes
        logger.info("Episodes cache saved — \(episodes.count) episodes.")
    }

    func clearEpisodesCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.episodes))
        cachedEpisodes = []
        logger.info("Episodes cache cleared.")
    }

    // MARK: - Generic Helpers

    private func loadCache<T: Decodable>(from file: String) -> Cache<T>? {
        // Return in-memory copy if available — avoids repeated disk reads within a session.
        if file == CacheFile.albums, let mem = albumCacheInMemory as? Cache<T> { return mem }
        if file == CacheFile.tracks, let mem = trackCacheInMemory as? Cache<T> { return mem }
        if file == CacheFile.episodes, let mem = episodeCacheInMemory as? Cache<T> { return mem }
        guard let data = try? Data(contentsOf: fileURL(file)) else { return nil }
        let decoded = try? JSONDecoder().decode(Cache<T>.self, from: data)
        // Warm the in-memory copy for future calls this session.
        if file == CacheFile.albums { albumCacheInMemory = decoded as? Cache<CodableAlbum> }
        if file == CacheFile.tracks { trackCacheInMemory = decoded as? Cache<CodableTrack> }
        if file == CacheFile.episodes { episodeCacheInMemory = decoded as? Cache<CodableEpisode> }
        return decoded
    }

    private func saveCache<T: Encodable>(_ cache: Cache<T>, to file: String) {
        // Update in-memory copy immediately so subsequent reads in the same session are fresh.
        if file == CacheFile.albums { albumCacheInMemory = cache as? Cache<CodableAlbum> }
        if file == CacheFile.tracks { trackCacheInMemory = cache as? Cache<CodableTrack> }
        if file == CacheFile.episodes { episodeCacheInMemory = cache as? Cache<CodableEpisode> }
        // Persist to disk on a background thread.
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(cache) else { return }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(file)
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    private func isValid<T>(_ cache: Cache<T>, maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(cache.fetchedAt) < maxAge
    }

    private func fileURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }
}
