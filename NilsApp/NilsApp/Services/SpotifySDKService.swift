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
            service.isOpeningSpotify = false
            service.logger.info("Spotify App Remote connected.")
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { (_, error) in
                if let error {
                    service.logger.error("Subscribe error: \(error.localizedDescription)")
                }
            })

            // Pending Seek ausführen — wird gesetzt wenn play() ohne aktive
            // Verbindung aufgerufen wurde und authorizeAndPlayURI verwendet hat.
            if let uri = service.pendingSeekURI,
               let position = service.pendingSeekPosition,
               position > 0 {
                service.logger.info("Executing pending seek to \(position)s for URI: \(uri)")
                // Kurze Verzögerung — Spotify braucht einen Moment nach dem Connect
                // bevor der playerAPI Seek-Commands annimmt.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appRemote.playerAPI?.seek(toPosition: Int(position * 1000))
                    service.logger.info("Pending seek executed at \(position)s.")
                    service.pendingSeekURI = nil
                    service.pendingSeekPosition = nil
                }
            }
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
    @Published fileprivate(set) var isOpeningSpotify: Bool = false

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

    // In SpotifySDKService — als private Property hinzufügen:
    private var localNetworkBrowser: NWBrowser?

    private var isConnecting = false
    
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
        guard !isConnected, !isConnecting else {
            logger.debug("connect() ignored — already connected or connecting.")
            return
        }
        isConnecting = true
        logger.info("Attempting to connect to Spotify App...")
        hasPauseTimeoutOccurred = false

        Task {
            defer {
                Task { @MainActor in
                    self.isConnecting = false
                }
            }
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
                logger.error("Token error: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        logger.info("Disconnecting from Spotify App...")
        appRemote?.disconnect()
    }
    
    func triggerLocalNetworkPrivacyAlert() {
        // Ein NetServiceBrowser-Lookup auf _spotify-connect._tcp
        // ist der einzige zuverlässige Weg, den iOS-Dialog zu triggern,
        // weil iOS ihn an Bonjour/Multicast-Aktivität knüpft — nicht an TCP.
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_spotify-connect._tcp", domain: "local."),
            using: .tcp
        )
        browser.stateUpdateHandler = { state in
            // Nur zum Triggern des Dialogs — Ergebnis ist irrelevant
        }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        
        // Nach 3 Sekunden stoppen — wir wollen nur den Dialog, keine dauernde Suche
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            browser.cancel()
        }
    }

    // MARK: - Playback Controls

    func play(uri: String, fromPosition position: TimeInterval? = nil) {
            guard isConnected else {
                logger.warning("Not connected — using authorizeAndPlayURI.")
                pendingSeekURI = uri
                pendingSeekPosition = position
            isOpeningSpotify = true  // Toast anzeigen
            
            Task {
                do {
                    guard let api = apiService else { return }
                    let token = try await api.getValidToken()
                    await MainActor.run {
                        self.appRemote?.connectionParameters.accessToken = token
                        self.appRemote?.authorizeAndPlayURI(uri)
                    }
                } catch {
                    self.isOpeningSpotify = false  // Bei Fehler zurücksetzen
                    logger.error("Token error: \(error.localizedDescription)")
                }
            }
            return
        }

        
        // Bereits verbunden — normal abspielen
        if let position = position, position > 0 {
            pendingSeekURI = uri
            pendingSeekPosition = position
        } else {
            pendingSeekURI = nil
            pendingSeekPosition = nil
        }
        
        logger.info("Playing URI: \(uri, privacy: .public)")
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
