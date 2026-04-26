// App Group
import Foundation

struct Constants {

    // MARK: - Spotify App Credentials

    static let spotifyClientId    = "30df49e256a14250b787957dc10377b8"
    static let spotifyRedirectURI = URL(string: "nilsapp://callback")!

    // MARK: - Spotify Accounts Endpoints
    //
    // All OAuth and token operations go through accounts.spotify.com.
    // Keeping these separate from the API base makes it obvious which
    // calls require authorisation headers and which do not.

    static let spotifyAccountsBase    = "https://accounts.spotify.com"
    static let spotifyAuthorizeURL    = "\(spotifyAccountsBase)/authorize"
    static let spotifyTokenURL        = "\(spotifyAccountsBase)/api/token"

    // MARK: - Spotify Web API Endpoints

    static let spotifyAPIBase         = "https://api.spotify.com/v1"

    /// Artist albums — append `/{artistId}/albums`
    static let spotifyArtistsBase     = "\(spotifyAPIBase)/artists"

    /// Playlist items — append `/{playlistId}/items`
    static let spotifyPlaylistsBase   = "\(spotifyAPIBase)/playlists"

    /// Show episodes — append `/{showId}/episodes`
    static let spotifyShowsBase       = "\(spotifyAPIBase)/shows"

    /// Current user's playlists
    static let spotifyMyPlaylists     = "\(spotifyAPIBase)/me/playlists"

    /// Search — append `?q=…&type=…`
    static let spotifySearch          = "\(spotifyAPIBase)/search"

    // MARK: - Spotify CDN

    /// Cover art and track images — append `/{imageId}`
    static let spotifyImageBase       = "https://i.scdn.co/image"

    // MARK: - Market

    /// Default market for episode availability queries.
    static let defaultMarket          = "AT"
}
