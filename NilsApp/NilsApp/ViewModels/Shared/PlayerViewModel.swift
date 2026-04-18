// Shared ViewModels Group
import Foundation
import Combine
import os

/// The shared ViewModel responsible for managing global playback state.
/// This will be injected as an @EnvironmentObject so any child view can control playback.
@MainActor
final class PlayerViewModel: ObservableObject {
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTrackURI: String?
    @Published private(set) var currentProgress: TimeInterval = 0
    @Published private(set) var trackName: String?
    @Published private(set) var artistName: String?
    @Published private(set) var trackDuration: TimeInterval = 0 // Added trackDuration to PlayerViewModel
    @Published private(set) var trackImageURL: URL?
    
    /// Forwarded from the SDK Service. When true, the UI must show a "Tap to Resume" 
    /// button instead of standard playback controls to handle the ~30s timeout.
    @Published private(set) var hasPauseTimeoutOccurred: Bool = false
    
    private let sdkService: SpotifySDKService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PlayerViewModel")
    private var cancellables = Set<AnyCancellable>()
    
    // Prefix for saving local playback cache in UserDefaults
    private let progressCacheKeyPrefix = "nilsapp_progress_"
    
    init(sdkService: SpotifySDKService) {
        self.sdkService = sdkService
        
        // Observe the SDK timeout state so the UI can react immediately
        sdkService.$hasPauseTimeoutOccurred
            .assign(to: &$hasPauseTimeoutOccurred)

        // Subscribe to SpotifySDKService's published properties for live player state updates
        sdkService.$currentTrackURI
            .assign(to: &$currentTrackURI)
        sdkService.$isPlaying
            .assign(to: &$isPlaying)
        sdkService.$currentProgress
            .assign(to: &$currentProgress)
        sdkService.$trackName
            .assign(to: &$trackName)
        sdkService.$artistName
            .assign(to: &$artistName)
        sdkService.$trackImageURL
            .assign(to: &$trackImageURL)
        sdkService.$trackDuration
            .assign(to: &$trackDuration)
    }


    // MARK: - Playback Commands

    /// Plays a given URI. If it's long-form content, it checks for a local position cache.
    func play(uri: String, isLongForm: Bool) {
        currentTrackURI = uri

        if isLongForm {
            let savedProgress = UserDefaults.standard.double(forKey: progressCacheKeyPrefix + uri)
            if savedProgress > 0 {
                logger.info("Found local playback cache for \(uri, privacy: .public) at \(savedProgress)s. Playing and seeking.")
                // Command SDK to play, then immediately seek to the saved progress.
                // The SpotifySDKService's play method will handle the actual SDK call.
                sdkService.play(uri: uri)
                sdkService.seek(to: savedProgress)
            } else {
                sdkService.play(uri: uri)
            }
        } else {
            // Standard music play (starts from beginning)
            sdkService.play(uri: uri)
        }
    }
    func pause() {
        sdkService.pause()
        saveCurrentProgress()
    }

    func resume() {
        sdkService.resume()
    }

    func scrub(to time: TimeInterval) {
        currentProgress = time
        logger.info("Scrubbing to \(time)s.")
        sdkService.seek(to: time)
        saveCurrentProgress()
    }

    private func saveCurrentProgress() {
        guard let uri = currentTrackURI else { return }
        // Always save progress locally as a reliable fallback for Audiobooks/Podcasts
        UserDefaults.standard.set(currentProgress, forKey: progressCacheKeyPrefix + uri) //
        logger.debug("Saved progress \(self.currentProgress)s for \(uri, privacy: .public)")
    }

    /// Skips to the previous track/episode.
    func previous() {
        sdkService.previous()
    }

    /// Skips to the next track/episode.
    func next() {
        sdkService.next()
    }
}