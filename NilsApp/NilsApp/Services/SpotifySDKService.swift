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

            // FIX RESUME: If a resume was requested while disconnected, execute it now.
            // This must be checked before the seek logic, because a resume-after-timeout
            // should just call resume() — the SDK will restore the last playback position.
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

            // FIX 1: Execute pending seek if position > 0, then always clear the pending state.
            // Previously, if position was nil or 0 the pending properties were never cleared,
            // causing a stale seek to fire on any subsequent reconnect.
            if let uri = service.pendingSeekURI,
               let position = service.pendingSeekPosition,
               position > 0 {
                service.logger.info("Executing pending seek to \(position)s for URI: \(uri)")
                // Short delay — Spotify needs a moment after connect before playerAPI accepts seeks.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appRemote.playerAPI?.seek(toPosition: Int(position * 1000))
                    service.logger.info("Pending seek executed at \(position)s.")
                    service.pendingSeekURI = nil
                    service.pendingSeekPosition = nil
                }
            } else {
                // Always clear pending state on connect, even if we didn't seek.
                service.pendingSeekURI = nil
                service.pendingSeekPosition = nil
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor [weak service] in
            service?.isConnected = false
            // FIX 2: Clear isOpeningSpotify on connection failure so the "Opening Spotify…"
            // toast doesn't spin forever (e.g. Spotify not installed).
            service?.isOpeningSpotify = false
            service?.pendingResume = false
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
    /// Set to true when resume() is called while disconnected; cleared after the
    /// reconnect delegate fires and issues the actual playerAPI?.resume().
    internal var pendingResume: Bool = false

    // MARK: - Private

    private var appRemote: SPTAppRemote?

    // The shim owns the ObjC delegate conformances so SpotifySDKService
    // never has to fight the module-wide @MainActor default.
    private var delegateShim: SpotifyDelegateShim?

    private weak var apiService: SpotifyAPIService?

    private var localNetworkBrowser: NWBrowser?

    private var isConnecting = false

    // FIX 2: Task handle for the "Spotify not installed" timeout so it can be cancelled
    // if the connection succeeds before the timeout fires.
    private var openingSpotifyTimeoutTask: Task<Void, Never>?
    
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

    // MARK: - Playback Controls

    /// Plays a URI. Pass `contextURI` (album/playlist/show URI) to enable
    /// continuous/gapless playback of the whole context; `uri` is then used
    /// only as the starting offset within that context.
    func play(uri: String, contextURI: String? = nil, fromPosition position: TimeInterval? = nil) {
        // Resolve what we will actually hand to the SDK.
        // If a context is provided, we play the context so Spotify handles
        // auto-advance. The individual item URI is stored for the seek-on-connect path.
        let playURI = contextURI ?? uri

        guard isConnected else {
            logger.warning("Not connected — using authorizeAndPlayURI.")
            pendingResume = false
            pendingSeekURI = uri           // seek target is always the item, not context
            pendingSeekPosition = position
            isOpeningSpotify = true

            // FIX 2: Start a 10-second timeout. If Spotify never opens/connects (e.g. not
            // installed), isOpeningSpotify is cleared so the toast doesn't spin forever.
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
                        self.appRemote?.authorizeAndPlayURI(playURI)
                    }
                } catch {
                    self.isOpeningSpotify = false
                    self.openingSpotifyTimeoutTask?.cancel()
                    logger.error("Token error: \(error.localizedDescription)")
                }
            }
            return
        }

        // Already connected — play normally.
        openingSpotifyTimeoutTask?.cancel()
        pendingResume = false

        if let position = position, position > 0 {
            pendingSeekURI = uri
            pendingSeekPosition = position
        } else {
            pendingSeekURI = nil
            pendingSeekPosition = nil
        }
        
        logger.info("Playing URI: \(playURI, privacy: .public)")
        appRemote?.playerAPI?.play(playURI)
    }

    func pause() {
        logger.info("Pausing playback.")
        appRemote?.playerAPI?.pause()
    }

    /// Resumes playback. If the SDK is disconnected (e.g. after the ~30s timeout),
    /// reconnects first and issues the resume in the connection callback.
    func resume() {
        logger.info("Resuming playback.")
        if isConnected {
            appRemote?.playerAPI?.resume()
        } else {
            // Mark that we want a resume as soon as we reconnect.
            // The delegate shim's appRemoteDidEstablishConnection will pick this up.
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
