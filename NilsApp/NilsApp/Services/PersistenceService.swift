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
    private let maxCacheAge: TimeInterval = 60 * 60 * 24 // 24 h

    private let logger = Logger(subsystem: "com.nilsapp", category: "PersistenceService")

    // MARK: - Generic Cache Envelope
    //
    // A single Codable wrapper replaces the three near-identical AlbumsCache /
    // TracksCache / EpisodesCache structs that existed before. `ids` is the set
    // of Spotify IDs whose data was fetched; it is used to invalidate the cache
    // when the parent adds or removes content in the Admin area.

    private struct Cache<T: Codable>: Codable {
        let ids: [String]
        let items: [T]
        let fetchedAt: Date
    }

    // MARK: - Codable Mirrors
    //
    // SpotifyAlbum / SpotifyTrack / SpotifyEpisode are not Codable by design
    // (they are transient UI models). These lightweight mirrors carry only the
    // properties we need to persist, keeping the public model layer clean.

    private struct CodableAlbum: Codable {
        let id, name, uri: String
        let imageURL: URL?
        init(_ m: SpotifyAlbum) { id = m.id; name = m.name; uri = m.uri; imageURL = m.imageURL }
        var model: SpotifyAlbum { SpotifyAlbum(id: id, name: name, imageURL: imageURL, uri: uri) }
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
    //
    // Using constants here means a typo only lives in one place and is caught
    // at compile time rather than causing a silent cache miss at runtime.

    private enum CacheFile {
        static let albums   = "cache_albums.json"
        static let tracks   = "cache_tracks.json"
        static let episodes = "cache_episodes.json"
    }

    // MARK: - Init

    init() {
        self.curatedContent = .empty
        load()
    }

    // MARK: - Curated Content (unchanged public surface)

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL(fileName))
            curatedContent = try JSONDecoder().decode(CuratedContent.self, from: data)
        } catch {
            logger.warning("Could not load curated content: \(error.localizedDescription)")
            curatedContent = .empty
        }
    }

    func save(_ content: CuratedContent) {
        do {
            let data = try JSONEncoder().encode(content)
            try data.write(to: fileURL(fileName), options: [.atomic, .completeFileProtection])
            curatedContent = content
            logger.info("Successfully saved curated content to disk.")
        } catch {
            logger.error("Failed to save curated content: \(error.localizedDescription)")
        }
    }

    // MARK: - Albums Cache (public API unchanged)

    func loadAlbums(for artistIds: [String]) -> [SpotifyAlbum]? {
        guard let cache: Cache<CodableAlbum> = loadCache(from: CacheFile.albums),
              cache.ids.sorted() == artistIds.sorted(),
              isValid(cache) else { return nil }
        logger.info("Albums cache hit — \(cache.items.count) albums.")
        return cache.items.map(\.model)
    }

    func saveAlbums(_ albums: [SpotifyAlbum], for artistIds: [String]) {
        saveCache(Cache(ids: artistIds, items: albums.map(CodableAlbum.init), fetchedAt: Date()),
                  to: CacheFile.albums)
        cachedAlbums = albums
        logger.info("Albums cache saved — \(albums.count) albums.")
    }

    func clearAlbumsCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.albums))
        cachedAlbums = []
        logger.info("Albums cache cleared.")
    }

    // MARK: - Tracks Cache (public API unchanged)

    func loadTracks(for playlistIds: [String]) -> [SpotifyTrack]? {
        guard let cache: Cache<CodableTrack> = loadCache(from: CacheFile.tracks),
              cache.ids.sorted() == playlistIds.sorted(),
              isValid(cache) else { return nil }
        logger.info("Tracks cache hit — \(cache.items.count) tracks.")
        return cache.items.map(\.model)
    }

    func saveTracks(_ tracks: [SpotifyTrack], for playlistIds: [String]) {
        saveCache(Cache(ids: playlistIds, items: tracks.map(CodableTrack.init), fetchedAt: Date()),
                  to: CacheFile.tracks)
        cachedTracks = tracks
        logger.info("Tracks cache saved — \(tracks.count) tracks.")
    }

    func clearTracksCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.tracks))
        cachedTracks = []
        logger.info("Tracks cache cleared.")
    }

    // MARK: - Episodes Cache (public API unchanged)

    func loadEpisodes(for showIds: [String]) -> [SpotifyEpisode]? {
        guard let cache: Cache<CodableEpisode> = loadCache(from: CacheFile.episodes),
              cache.ids.sorted() == showIds.sorted(),
              isValid(cache) else { return nil }
        logger.info("Episodes cache hit — \(cache.items.count) episodes.")
        return cache.items.map(\.model)
    }

    func saveEpisodes(_ episodes: [SpotifyEpisode], for showIds: [String]) {
        saveCache(Cache(ids: showIds, items: episodes.map(CodableEpisode.init), fetchedAt: Date()),
                  to: CacheFile.episodes)
        cachedEpisodes = episodes
        logger.info("Episodes cache saved — \(episodes.count) episodes.")
    }

    func clearEpisodesCache() {
        try? FileManager.default.removeItem(at: fileURL(CacheFile.episodes))
        cachedEpisodes = []
        logger.info("Episodes cache cleared.")
    }

    // MARK: - Generic Helpers
    //
    // These two methods replace six separate load*/save* implementations.
    // Any future cacheable type (e.g. radio stations) gets persistence for free
    // by adding only its Codable mirror and a thin public wrapper pair.

    private func loadCache<T: Decodable>(from file: String) -> Cache<T>? {
        guard let data = try? Data(contentsOf: fileURL(file)) else { return nil }
        return try? JSONDecoder().decode(Cache<T>.self, from: data)
    }

    private func saveCache<T: Encodable>(_ cache: Cache<T>, to file: String) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL(file), options: [.atomic, .completeFileProtection])
    }

    private func isValid<T>(_ cache: Cache<T>) -> Bool {
        Date().timeIntervalSince(cache.fetchedAt) < maxCacheAge
    }

    private func fileURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }
}
