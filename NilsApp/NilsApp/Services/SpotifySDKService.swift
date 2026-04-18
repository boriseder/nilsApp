// Services Group
import Foundation
import Combine
import os

import SpotifyiOS // Import the Spotify iOS App Remote SDK
/// A service wrapper for the Spotify iOS App Remote SDK.
/// This service handles connection lifecycle, playback commands, and 
/// enforces the rules defined in our architecture (e.g., handling the 30s timeout).
@MainActor
final class SpotifySDKService: NSObject, ObservableObject {
    
    /// Indicates whether the App Remote SDK is currently connected to the main Spotify app.
    @Published private(set) var isConnected: Bool = false
    
    /// Becomes true if the SDK disconnects automatically due to Spotify's ~30-second pause timeout.
    /// The UI should observe this and show a "Tap to Resume" button instead of failing silently.
    @Published private(set) var hasPauseTimeoutOccurred: Bool = false
    
    // Published properties reflecting the current player state from the Spotify app
    @Published private(set) var currentTrackURI: String?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentProgress: TimeInterval = 0 // in seconds
    @Published private(set) var artistName: String? // Added artistName
    @Published private(set) var trackDuration: TimeInterval = 0 // in seconds
    @Published private(set) var trackImageURL: URL?
    @Published private(set) var trackName: String?
    private let logger = Logger(subsystem: "com.nilsapp", category: "SpotifySDKService")
    
    private var appRemote: SPTAppRemote?
    
    override init() {
        super.init()
        setupAppRemote()
    }
    
    private func setupAppRemote() {
        // Initialize SPTConfiguration with Client ID and Redirect URI.
        let configuration = SPTConfiguration(
            clientID: Constants.spotifyClientId,
            redirectURL: Constants.spotifyRedirectURI
        )
        
        // Initialize SPTAppRemote with the configuration.
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        
        // Set self as the delegate for appRemote.
        appRemote?.delegate = self
        logger.debug("Spotify App Remote initialized with client ID: \(Constants.spotifyClientId, privacy: .public)")
    }
    
    // MARK: - Connection Lifecycle
    
    /// Attempts to connect to the Spotify app.
    func connect() {
        logger.info("Attempting to connect to Spotify App...")
        hasPauseTimeoutOccurred = false
        // The Spotify App Remote SDK handles authorization and connection.
        // Calling connect() will attempt to connect to the Spotify app.
        // If not authorized, it will attempt to authorize.
        appRemote?.connect()
        self.logger.info("Called appRemote.connect()")
    }
    
    /// Disconnects from the Spotify app. 
    /// Should be called when the app enters the background to save battery and follow SDK guidelines.
    func disconnect() {
        logger.info("Disconnecting from Spotify App...")
        
        // Call appRemote.disconnect()
        appRemote?.disconnect()
    }
    
    // MARK: - Playback Controls
    
    /// Plays a specific Spotify URI (Album, Track, or Episode).
    func play(uri: String) {
        guard isConnected else {
            logger.warning("Attempted to play \(uri) but SDK is not connected. Reconnecting...")
            connect()
            // In a real implementation, you would queue this URI to play after connection succeeds.
            return
        }
        logger.info("Playing URI: \(uri, privacy: .public)")
        // Call appRemote.playerAPI.play(uri)
        appRemote?.playerAPI?.play(uri)
    }
    
    func pause() {
        logger.info("Pausing playback.")
        // Call appRemote.playerAPI.pause()
        appRemote?.playerAPI?.pause()
        // Note: Spotify will automatically disconnect ~30s after pausing.
        // The SPTAppRemoteDelegate's didDisconnectWithError method will handle setting hasPauseTimeoutOccurred.
    }
    
    func resume() {
        logger.info("Resuming playback.")
        if hasPauseTimeoutOccurred || !isConnected {
            // If we timed out, we must fully reconnect before we can resume.
            // The connect() method will handle re-authorization if needed.
            connect()
        } else {
            // Call appRemote.playerAPI.resume()
            appRemote?.playerAPI?.resume()
        }
    }
    
    /// Seeks to a specific position in the currently playing track.
    func seek(to position: TimeInterval) {
        guard isConnected else {
            logger.warning("Attempted to seek but SDK is not connected.")
            return
        }
        logger.info("Seeking to \(position)s")
        // The Spotify SDK expects position in milliseconds.
        appRemote?.playerAPI?.seek(toPosition: Int(position * 1000))
    }
    
    // MARK: - SPTAppRemoteDelegate
} // End of SpotifySDKService class

extension SpotifySDKService: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidConnect(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.isConnected = true
            self.logger.info("Spotify App Remote connected.")
            // It's good practice to subscribe to player state updates here.
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { (success, error) in
                if let error = error {
                    self.logger.error("Error subscribing to player state: \(error.localizedDescription)")
                }
            })
        }
    }
    
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.logger.warning("Spotify App Remote disconnected with error: \(error?.localizedDescription ?? "unknown error")")
            // The SDK disconnects after ~30s of pause. We need to detect this.
            // The error object might contain specific codes for timeout, but for simplicity, we'll assume any disconnect after a pause could be a timeout.
            // A more robust implementation might check error codes.
            self.hasPauseTimeoutOccurred = true
        }
    }
    
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.logger.error("Spotify App Remote failed connection attempt with error: \(error?.localizedDescription ?? "unknown error")")
            // If connection fails, it might indicate a need for reauthentication.
            // However, the `SpotifyAPIService` handles the Web API authentication.
            // For the App Remote, a connection failure usually means the Spotify app isn't running or there's a transient issue.
            // We don't set `requiresReauthentication` here as it's for the Web API token.
        }
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate
extension SpotifySDKService: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in
            // This delegate method is called whenever the player state changes in the Spotify app.
            self.isConnected = true // If we're getting player state, we're connected.
            self.hasPauseTimeoutOccurred = false // If playback resumes, timeout is no longer relevant.
            
            // Update published properties based on the player state.
            // Note: PlayerViewModel will observe these changes.
            // We don't directly update PlayerViewModel's state here to maintain separation of concerns.
            self.currentTrackURI = playerState.track.uri
            self.isPlaying = !playerState.isPaused
            self.currentProgress = TimeInterval(playerState.playbackPosition) / 1000.0
            self.trackDuration = TimeInterval(playerState.track.duration) / 1000.0
            self.trackName = playerState.track.name
            self.artistName = playerState.track.artist.name
            
            // The Spotify SDK provides imageIdentifier, which is a Spotify URI. 
            // We convert it to the public Spotify i.scdn.co image URL.
            let imageIdentifier = playerState.track.imageIdentifier
            let rawId = imageIdentifier.replacingOccurrences(of: "spotify:image:", with: "")
            if let url = URL(string: "https://i.scdn.co/image/\(rawId)") {
                self.trackImageURL = url
            }
            self.logger.debug("Player state changed: isPlaying=\(self.isPlaying), trackURI=\(self.currentTrackURI ?? "nil", privacy: .public), position=\(self.currentProgress)s, duration=\(self.trackDuration)s")
        }
    }
}