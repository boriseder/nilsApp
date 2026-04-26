// Services Group
import Foundation
import Combine
import os
import SpotifyiOS
import Network

// MARK: - Delegate Shim

final class SpotifyDelegateShim: NSObject {
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

            if service.pendingResume {
                service.pendingResume = false
                service.pendingSeekURI = nil
                service.pendingSeekPosition = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    service.logger.info("Executing pending resume after reconnect.")
                    appRemote.playerAPI?.resume()
                }
                return
            }

            if let uri = service.pendingSeekURI,
               let position = service.pendingSeekPosition,
               position > 0 {
                service.logger.info("Executing pending seek to \(position)s for URI: \(uri)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appRemote.playerAPI?.seek(toPosition: Int(position * 1000))
                    service.logger.info("Pending seek executed at \(position)s.")
                    service.pendingSeekURI = nil
                    service.pendingSeekPosition = nil
                }
            } else {
                service.pendingSeekURI = nil
                service.pendingSeekPosition = nil
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor [weak service] in
            service?.isConnected = false
            service?.isOpeningSpotify = false
            service?.pendingResume = false
            // FIX: UI-Status auf Reconnect setzen, wenn die Verbindung fehlschlägt
            service?.hasPauseTimeoutOccurred = true
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

    internal let logger = Logger(subsystem: "com.nilsapp", category: "SpotifySDKService")
    internal var pendingSeekURI: String?
    internal var pendingSeekPosition: TimeInterval?
    internal var pendingResume: Bool = false

    private var appRemote: SPTAppRemote?
    private var delegateShim: SpotifyDelegateShim?
    private weak var apiService: SpotifyAPIService?
    private var localNetworkBrowser: NWBrowser?
    private var isConnecting = false
    private var openingSpotifyTimeoutTask: Task<Void, Never>?
    
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

    func connect() {
        guard !isConnected, !isConnecting else {
            logger.debug("connect() ignored — already connected or connecting.")
            return
        }
        isConnecting = true
        logger.info("Attempting to connect to Spotify App...")

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
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_spotify-connect._tcp", domain: "local."),
            using: .tcp
        )
        browser.stateUpdateHandler = { state in }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            browser.cancel()
        }
    }

    func play(uri: String, contextURI: String? = nil, fromPosition position: TimeInterval? = nil) {
        // Um einen spezifischen Track in einer Playlist zu starten, übergeben wir die Track-URI.
        let playURI = uri

        guard isConnected else {
            logger.warning("Not connected — using authorizeAndPlayURI.")
            pendingResume = false
            pendingSeekURI = uri
            pendingSeekPosition = position
            isOpeningSpotify = true

            openingSpotifyTimeoutTask?.cancel()
            openingSpotifyTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(10))
                await MainActor.run {
                    if self.isOpeningSpotify {
                        self.isOpeningSpotify = false
                        self.logger.warning("Spotify open timeout — Spotify may not be installed.")
                    }
                }
            }

            Task {
                do {
                    guard let api = apiService else { return }
                    let token = try await api.getValidToken()
                    await MainActor.run {
                        self.appRemote?.connectionParameters.accessToken = token
                        // Beim ersten Öffnen nutzen wir den Context (Playlist), damit die Queue geladen wird.
                        self.appRemote?.authorizeAndPlayURI(contextURI ?? uri)
                    }
                } catch {
                    self.isOpeningSpotify = false
                    self.openingSpotifyTimeoutTask?.cancel()
                    logger.error("Token error: \(error.localizedDescription)")
                }
            }
            return
        }

        openingSpotifyTimeoutTask?.cancel()
        pendingResume = false

        if let position = position, position > 0 {
            pendingSeekURI = uri
            pendingSeekPosition = position
        } else {
            pendingSeekURI = nil
            pendingSeekPosition = nil
        }
        
        logger.info("Playing Track URI: \(playURI, privacy: .public)")
        // FIX: 'asContext' entfernt, da es nicht Teil der SDK-Methode ist.
        appRemote?.playerAPI?.play(playURI)
    }

    func pause() {
        guard isConnected else { return }
        logger.info("Pausing playback.")
        appRemote?.playerAPI?.pause()
    }

    func resume() {
        logger.info("Resuming playback.")
        if isConnected {
            appRemote?.playerAPI?.resume()
        } else {
            pendingResume = true
            hasPauseTimeoutOccurred = false
            connect()
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
