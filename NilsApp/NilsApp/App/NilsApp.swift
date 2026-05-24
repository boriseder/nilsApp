// App Group
import SwiftUI
import os

/// AppDelegate is used here strictly to enforce the Landscape orientation lock programmatically.
/// This ensures a stable, media-focused experience for the child and prevents accidental rotations.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

@main
struct NilsAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let logger = Logger(subsystem: "com.nilsapp", category: "NilsAppApp")

    // MARK: - Core Services
    @StateObject private var persistenceService: PersistenceService
    @StateObject private var spotifyAPIService: SpotifyAPIService
    @StateObject private var spotifySDKService: SpotifySDKService

    // MARK: - Shared ViewModels
    @StateObject private var playerViewModel: PlayerViewModel

    init() {
        // Activate the UIApplication.openURL swizzle so the Spotify SDK's
        // authorizeAndPlayURI works on iOS 26 (deprecated openURL returns false otherwise).
        _ = UIApplication.patchSpotifySDK

        let api         = SpotifyAPIService()
        let sdk         = SpotifySDKService(apiService: api)
        let persistence = PersistenceService()

        _spotifyAPIService = StateObject(wrappedValue: api)
        _spotifySDKService = StateObject(wrappedValue: sdk)
        _persistenceService = StateObject(wrappedValue: persistence)
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(sdkService: sdk))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(persistenceService)
                .environmentObject(spotifyAPIService)
                .environmentObject(spotifySDKService)
                .environmentObject(playerViewModel)
                .onOpenURL { url in
                    self.logger.info("Received URL: \(url.absoluteString, privacy: .public)")
                    if url.scheme == Constants.spotifyRedirectURI.scheme {
                        if url.absoluteString.contains("code=") {
                            Task { try? await self.spotifyAPIService.handleRedirectURL(url) }
                        }
                        self.spotifySDKService.connect()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                spotifySDKService.connect()
            case .background:
                spotifySDKService.disconnect()
            case .inactive:
                break
            default:
                break
            }
        }
    }
}
