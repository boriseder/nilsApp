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
    @Published private(set) var trackDuration: TimeInterval = 0
    @Published private(set) var trackImageURL: URL?
    @Published private(set) var isOpeningSpotify: Bool = false

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
        
        sdkService.$hasPauseTimeoutOccurred
            .assign(to: &$hasPauseTimeoutOccurred)

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
            
        // Automatically save playback progress every 5 seconds while playing.
        sdkService.$currentProgress
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] progress in
                // Only save after 10s to avoid capturing intros as resume positions.
                guard let self = self, self.isPlaying, progress > 10.0 else { return }
                self.saveCurrentProgress()
            }
            .store(in: &cancellables)

        // FIX 6: Save progress on pause using the position delivered by the SDK callback,
        // not from currentProgress which may be up to 5 seconds stale (throttled above).
        // We watch isPlaying transitions: true → false means the SDK confirmed the pause
        // and currentProgress at that instant reflects the actual paused position.
        sdkService.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self = self, !playing else { return }
                // isPlaying just became false — save the SDK-confirmed position.
                self.saveCurrentProgress()
            }
            .store(in: &cancellables)

        sdkService.$isOpeningSpotify
            .assign(to: &$isOpeningSpotify)
    }


    // MARK: - Playback Commands

    /// Plays a given URI. If it's long-form content, it checks for a local position cache.
    func play(uri: String, isLongForm: Bool) {
        guard uri != currentTrackURI || !isPlaying else {
            logger.info("Ignoring duplicate play call for URI: \(uri, privacy: .public)")
            return
        }

        if isLongForm {
            let savedProgress = UserDefaults.standard.double(forKey: progressCacheKeyPrefix + uri)
            if savedProgress > 0 {
                logger.info("Found local playback cache for \(uri, privacy: .public) at \(savedProgress)s.")
                sdkService.play(uri: uri, fromPosition: savedProgress)
            } else {
                sdkService.play(uri: uri)
            }
        } else {
            sdkService.play(uri: uri)
        }
    }
    
    func pause() {
        sdkService.pause()
        // FIX 6: Do NOT call saveCurrentProgress() here — currentProgress is throttled
        // and may be stale by up to 5 seconds. The Combine subscription above saves
        // progress when isPlaying transitions to false (SDK-confirmed pause position).
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
        guard currentProgress > 10.0 else {
            logger.debug("Skipping progress save — too early (\(self.currentProgress)s)")
            return
        }
        UserDefaults.standard.set(currentProgress, forKey: progressCacheKeyPrefix + uri)
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
