// Services Group
import Foundation
import Combine
import os
import SpotifyiOS
import Network

// MARK: - Delegate Shim
//
// WHY THIS EXISTS:
// The build setting SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor makes every type in
// this module implicitly @MainActor. SPTAppRemoteDelegate and SPTAppRemotePlayerStateDelegate
// are ObjC protocols whose methods are called from non-main threads. Swift 6 cannot
// reconcile "@MainActor conformance" with "called from any thread" — no combination of
// nonisolated, @preconcurrency, or Task{} on the main class resolves this without the
// compiler either refusing the conformance or warning that the annotation has no effect.
//
// The solution: a plain NSObject subclass declared in this file inherits the module-wide
// @MainActor default, but we can suppress it per-type with `nonisolated(unsafe)` storage
// and explicit actor hops. Because it's a small, focused shim with no @Published properties,
// the pattern is clean and safe.

/// A lightweight ObjC-compatible shim that receives Spotify SDK callbacks and
/// forwards them to `SpotifySDKService` on the MainActor.
final class SpotifyDelegateShim: NSObject {

    // Weak reference back to the service — avoids retain cycles.
    weak var service: SpotifySDKService?

    init(service: SpotifySDKService) {
        self.service = service
    }
    
}

extension SpotifyDelegateShim: SPTAppRemoteDelegate {

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            guard let service = self?.service else { return }
            service.isConnected = true
            service.hasPauseTimeoutOccurred = false
            service.logger.info("Spotify App Remote connected.")
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { (_, error) in
                if let error {
                    service.logger.error("Subscribe error: \(error.localizedDescription)")
                }
            })
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor [weak service] in
            service?.isConnected = false
            service?.logger.error("SDK connection failed: \(error?.localizedDescription ?? "no error")")
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor [weak service] in
            service?.isConnected = false
            service?.hasPauseTimeoutOccurred = true
            service?.logger.warning("SDK disconnected: \(error?.localizedDescription ?? "no error")")
        }
    }
}

extension SpotifyDelegateShim: SPTAppRemotePlayerStateDelegate {

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        // Extract values here (on SDK thread) before hopping actors
        let uri        = playerState.track.uri
        let paused     = playerState.isPaused
        let position   = TimeInterval(playerState.playbackPosition) / 1000.0
        let duration   = TimeInterval(playerState.track.duration) / 1000.0
        let name       = playerState.track.name
        let artist     = playerState.track.artist.name
        let rawImageId = playerState.track.imageIdentifier
            .replacingOccurrences(of: "spotify:image:", with: "")
        let imageURL   = URL(string: "https://i.scdn.co/image/\(rawImageId)")

        Task { @MainActor [weak service] in
            guard let service else { return }
            service.isConnected = true
            service.hasPauseTimeoutOccurred = false
            service.currentTrackURI = uri
            service.isPlaying = !paused
            service.currentProgress = position
            service.trackDuration = duration
            service.trackName = name
            service.artistName = artist
            service.trackImageURL = imageURL
            service.logger.debug("Player state: isPlaying=\(!paused), position=\(position)s")
        }
    }
}

// MARK: - SpotifySDKService

final class SpotifySDKService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published fileprivate(set) var isConnected: Bool = false
    @Published fileprivate(set) var hasPauseTimeoutOccurred: Bool = false
    @Published fileprivate(set) var currentTrackURI: String?
    @Published fileprivate(set) var isPlaying: Bool = false
    @Published fileprivate(set) var currentProgress: TimeInterval = 0
    @Published fileprivate(set) var artistName: String?
    @Published fileprivate(set) var trackDuration: TimeInterval = 0
    @Published fileprivate(set) var trackImageURL: URL?
    @Published fileprivate(set) var trackName: String?

    // MARK: - Internal (accessed by shim)

    internal let logger = Logger(subsystem: "com.nilsapp", category: "SpotifySDKService")
    internal var pendingSeekURI: String?
    internal var pendingSeekPosition: TimeInterval?

    // MARK: - Private

    private var appRemote: SPTAppRemote?

    // The shim owns the ObjC delegate conformances so SpotifySDKService
    // never has to fight the module-wide @MainActor default.
    private var delegateShim: SpotifyDelegateShim?

    // NEU: schwache Referenz auf APIService
    private weak var apiService: SpotifyAPIService?

    
    // MARK: - Init

    init(apiService: SpotifyAPIService) {
        self.apiService = apiService
        super.init()
        setupAppRemote()
    }

    private func setupAppRemote() {
        let configuration = SPTConfiguration(
            clientID: Constants.spotifyClientId,
            redirectURL: Constants.spotifyRedirectURI
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        let shim = SpotifyDelegateShim(service: self)
        remote.delegate = shim
        appRemote = remote
        delegateShim = shim
        logger.debug("Spotify App Remote initialized.")
        triggerLocalNetworkPrivacyAlert()
    }

    // MARK: - Connection Lifecycle

    func connect() {
        // Falls wir bereits verbinden oder verbunden sind, abbrechen
        guard !isConnected else { return }
        
        logger.info("Attempting to connect to Spotify App...")
        hasPauseTimeoutOccurred = false
        
        Task {
            do {
                guard let api = apiService else {
                    logger.error("APIService is nil")
                    return
                }
                let token = try await api.getValidToken()
                await MainActor.run {
                    self.appRemote?.connectionParameters.accessToken = token
                    self.appRemote?.connect()
                }
            } catch {
                // Das wird uns den genauen Grund verraten (z.B. HTTP 401 oder Keychain Error)
                logger.error("Token error: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnect() {
        logger.info("Disconnecting from Spotify App...")
        appRemote?.disconnect()
    }
    
    func triggerLocalNetworkPrivacyAlert() {
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(integerLiteral: 9095)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection.stateUpdateHandler = { state in
            // Dies triggert den iOS-Dialog beim ersten Mal
            print("Network state update: \(state)")
        }
        connection.start(queue: .main)
    }

    // MARK: - Playback Controls

    func play(uri: String, fromPosition position: TimeInterval? = nil) {
        guard isConnected else {
            logger.warning("Not connected — reconnecting before play.")
            connect()
            return
        }
        
        if let position = position, position > 0 {
            logger.info("Playing URI: \(uri, privacy: .public) with pending seek to \(position)s")
            pendingSeekURI = uri
            pendingSeekPosition = position
        } else {
            logger.info("Playing URI: \(uri, privacy: .public)")
            pendingSeekURI = nil
            pendingSeekPosition = nil
        }
        
        appRemote?.playerAPI?.play(uri)
    }

    func pause() {
        logger.info("Pausing playback.")
        appRemote?.playerAPI?.pause()
    }

    func resume() {
        logger.info("Resuming playback.")
        if hasPauseTimeoutOccurred || !isConnected {
            connect()
        } else {
            appRemote?.playerAPI?.resume()
        }
    }

    func previous() {
        guard isConnected else { return }
        appRemote?.playerAPI?.skip(toPrevious: nil)
    }

    func next() {
        guard isConnected else { return }
        appRemote?.playerAPI?.skip(toNext: nil)
    }

    func seek(to position: TimeInterval) {
        guard isConnected else { return }
        appRemote?.playerAPI?.seek(toPosition: Int(position * 1000))
    }
}
