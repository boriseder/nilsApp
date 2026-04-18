// Models Group
import Foundation

/// A top-level container that holds all the content curated by the parent.
/// This object will be encoded and saved to the device's local storage.
struct CuratedContent: Codable, Equatable {
    var audiobookSeries: [CuratedArtist]
    var musicPlaylists: [CuratedPlaylist]
    var podcastShows: [CuratedShow]

    static let empty = CuratedContent(audiobookSeries: [], musicPlaylists: [], podcastShows: [])
}

/// Represents an approved audiobook series (which corresponds to a Spotify "Artist").
/// The app will use the `id` to fetch all albums for this artist.
struct CuratedArtist: Codable, Identifiable, Equatable {
    /// The Spotify Artist ID.
    let id: String
    let name: String
    let imageURL: URL?
}

/// Represents an approved music playlist.
/// The app will use the `id` to fetch the tracks in this playlist.
struct CuratedPlaylist: Codable, Identifiable, Equatable {
    /// The Spotify Playlist ID.
    let id: String
    let name: String
    let imageURL: URL?
}

/// Represents an approved podcast (which corresponds to a Spotify "Show").
/// The app will use the `id` to fetch all episodes for this show.
struct CuratedShow: Codable, Identifiable, Equatable {
    /// The Spotify Show ID.
    let id: String
    let name: String
    let imageURL: URL?
}

/// Represents a playable album fetched from the Spotify API.
/// This is a transient model used purely for the UI, not saved to disk.
struct SpotifyAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: URL?
    let uri: String
}

/// Represents a playable track fetched from a Spotify Playlist.
/// This is a transient model used purely for the UI, not saved to disk.
struct SpotifyTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let artistName: String
    let imageURL: URL?
    let uri: String
    let duration: TimeInterval
}

/// Represents a playable episode fetched from a Spotify Podcast Show.
/// This is a transient model used purely for the UI, not saved to disk.
struct SpotifyEpisode: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let imageURL: URL?
    let uri: String
    let duration: TimeInterval
    let releaseDate: Date?
}

/// Enum to categorize content types for searching in the Admin area.
enum SearchCategory: String, CaseIterable, Identifiable {
    case audiobooks = "Audiobooks"
    case music = "Music Playlists"
    case podcasts = "Podcasts"
    var id: String { self.rawValue }
}