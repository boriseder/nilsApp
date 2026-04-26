// Shared ViewModels Group
import Foundation
import Combine
import os

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
    
    // Status für die UI
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var hasPauseTimeoutOccurred: Bool = false
    
    private let sdkService: SpotifySDKService
    private let logger = Logger(subsystem: "com.nilsapp", category: "PlayerViewModel")
    private var cancellables = Set<AnyCancellable>()
    private let progressCacheKeyPrefix = "nilsapp_progress_"
    
    init(sdkService: SpotifySDKService) {
        self.sdkService = sdkService
        
        sdkService.$isConnected
            .assign(to: &$isConnected)
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
        sdkService.$isOpeningSpotify
            .assign(to: &$isOpeningSpotify)
            
        sdkService.$currentProgress
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] progress in
                guard let self = self, self.isPlaying, progress > 10.0 else { return }
                self.saveCurrentProgress()
            }
            .store(in: &cancellables)

        sdkService.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self = self, !playing else { return }
                self.saveCurrentProgress()
            }
            .store(in: &cancellables)
    }

    func play(uri: String, contextURI: String? = nil, isLongForm: Bool) {
        if isLongForm {
            let savedProgress = UserDefaults.standard.double(forKey: progressCacheKeyPrefix + uri)
            if savedProgress > 0 {
                logger.info("Found local playback cache for \(uri, privacy: .public) at \(savedProgress)s.")
                sdkService.play(uri: uri, contextURI: contextURI, fromPosition: savedProgress)
            } else {
                sdkService.play(uri: uri, contextURI: contextURI)
            }
        } else {
            // Track URI und Playlist Context werden an den Service gereicht
            sdkService.play(uri: uri, contextURI: contextURI)
        }
    }
    
    func pause() {
        guard isConnected else { return }
        sdkService.pause()
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
        guard currentProgress > 10.0 else { return }
        UserDefaults.standard.set(currentProgress, forKey: progressCacheKeyPrefix + uri)
    }

    func previous() {
        sdkService.previous()
    }

    func next() {
        sdkService.next()
    }
}
