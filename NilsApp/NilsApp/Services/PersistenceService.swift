// Services Group
import Foundation
import Combine
import os

/// Service responsible for saving and loading the parent's curated content
/// to and from the device's local filesystem.
@MainActor
final class PersistenceService: ObservableObject {
    
    @Published private(set) var curatedContent: CuratedContent
    
    // NEU: Gecachte API-Daten
    @Published private(set) var cachedAlbums: [SpotifyAlbum] = []
    @Published private(set) var cachedTracks: [SpotifyTrack] = []
    @Published private(set) var cachedEpisodes: [SpotifyEpisode] = []
    
    private let fileName = "curated_content.json"
    private let albumsCacheFile = "cache_albums.json"
    private let tracksCacheFile = "cache_tracks.json"
    private let episodesCacheFile = "cache_episodes.json"
    private let maxCacheAge: TimeInterval = 60 * 60 * 24 // 24h
    
    private let logger = Logger(subsystem: "com.nilsapp", category: "PersistenceService")
    
    // MARK: - Codable Cache Wrapper
    
    private struct AlbumsCache: Codable {
        let artistIds: [String]
        let albums: [CodableAlbum]
        let fetchedAt: Date
    }
    
    private struct TracksCache: Codable {
        let playlistIds: [String]
        let tracks: [CodableTrack]
        let fetchedAt: Date
    }
    
    private struct EpisodesCache: Codable {
        let showIds: [String]
        let episodes: [CodableEpisode]
        let fetchedAt: Date
    }
    
    private struct CodableAlbum: Codable {
        let id, name, uri: String; let imageURL: URL?
        func toModel() -> SpotifyAlbum { SpotifyAlbum(id: id, name: name, imageURL: imageURL, uri: uri) }
    }
    private struct CodableTrack: Codable {
        let id, name, artistName, uri: String; let imageURL: URL?; let duration: TimeInterval
        func toModel() -> SpotifyTrack { SpotifyTrack(id: id, name: name, artistName: artistName, imageURL: imageURL, uri: uri, duration: duration) }
    }
    private struct CodableEpisode: Codable {
        let id, name, description, uri: String; let imageURL: URL?; let duration: TimeInterval; let releaseDate: Date?
        func toModel() -> SpotifyEpisode { SpotifyEpisode(id: id, name: name, description: description, imageURL: imageURL, uri: uri, duration: duration, releaseDate: releaseDate) }
    }
    
    // MARK: - Init
    
    init() {
        self.curatedContent = .empty
        load()
    }
    
    // MARK: - Curated Content (bestehend)
    
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL(albumsCacheFile))
            curatedContent = try JSONDecoder().decode(CuratedContent.self, from: Data(contentsOf: fileURL(fileName)))
        } catch {
            logger.warning("Could not load curated content (expected on first launch): \(error.localizedDescription)")
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
    
    // MARK: - Albums Cache
    
    func loadAlbums(for artistIds: [String]) -> [SpotifyAlbum]? {
        guard let cache: AlbumsCache = loadJSON(from: albumsCacheFile),
              cache.artistIds.sorted() == artistIds.sorted(),
              Date().timeIntervalSince(cache.fetchedAt) < maxCacheAge else { return nil }
        logger.info("Albums cache hit — \(cache.albums.count) albums.")
        return cache.albums.map { $0.toModel() }
    }
    
    func saveAlbums(_ albums: [SpotifyAlbum], for artistIds: [String]) {
        let cache = AlbumsCache(
            artistIds: artistIds,
            albums: albums.map { CodableAlbum(id: $0.id, name: $0.name, uri: $0.uri, imageURL: $0.imageURL) },
            fetchedAt: Date()
        )
        saveJSON(cache, to: albumsCacheFile)
        cachedAlbums = albums
        logger.info("Albums cache saved — \(albums.count) albums.")
    }
    
    func clearAlbumsCache() {
        try? FileManager.default.removeItem(at: fileURL(albumsCacheFile))
        cachedAlbums = []
        logger.info("Albums cache cleared.")
    }
    
    // MARK: - Tracks Cache
    
    func loadTracks(for playlistIds: [String]) -> [SpotifyTrack]? {
        guard let cache: TracksCache = loadJSON(from: tracksCacheFile),
              cache.playlistIds.sorted() == playlistIds.sorted(),
              Date().timeIntervalSince(cache.fetchedAt) < maxCacheAge else { return nil }
        logger.info("Tracks cache hit — \(cache.tracks.count) tracks.")
        return cache.tracks.map { $0.toModel() }
    }
    
    func saveTracks(_ tracks: [SpotifyTrack], for playlistIds: [String]) {
        let cache = TracksCache(
            playlistIds: playlistIds,
            tracks: tracks.map { CodableTrack(id: $0.id, name: $0.name, artistName: $0.artistName, uri: $0.uri, imageURL: $0.imageURL, duration: $0.duration) },
            fetchedAt: Date()
        )
        saveJSON(cache, to: tracksCacheFile)
        cachedTracks = tracks
        logger.info("Tracks cache saved — \(tracks.count) tracks.")
    }
    
    func clearTracksCache() {
        try? FileManager.default.removeItem(at: fileURL(tracksCacheFile))
        cachedTracks = []
        logger.info("Tracks cache cleared.")
    }
    
    // MARK: - Episodes Cache
    
    func loadEpisodes(for showIds: [String]) -> [SpotifyEpisode]? {
        guard let cache: EpisodesCache = loadJSON(from: episodesCacheFile),
              cache.showIds.sorted() == showIds.sorted(),
              Date().timeIntervalSince(cache.fetchedAt) < maxCacheAge else { return nil }
        logger.info("Episodes cache hit — \(cache.episodes.count) episodes.")
        return cache.episodes.map { $0.toModel() }
    }
    
    func saveEpisodes(_ episodes: [SpotifyEpisode], for showIds: [String]) {
        let cache = EpisodesCache(
            showIds: showIds,
            episodes: episodes.map { CodableEpisode(id: $0.id, name: $0.name, description: $0.description, uri: $0.uri, imageURL: $0.imageURL, duration: $0.duration, releaseDate: $0.releaseDate) },
            fetchedAt: Date()
        )
        saveJSON(cache, to: episodesCacheFile)
        cachedEpisodes = episodes
        logger.info("Episodes cache saved — \(episodes.count) episodes.")
    }
    
    func clearEpisodesCache() {
        try? FileManager.default.removeItem(at: fileURL(episodesCacheFile))
        cachedEpisodes = []
        logger.info("Episodes cache cleared.")
    }
    
    // MARK: - Helpers
    
    private func fileURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }
    
    private func loadJSON<T: Decodable>(from file: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    private func saveJSON<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(file), options: [.atomic, .completeFileProtection])
    }
}
