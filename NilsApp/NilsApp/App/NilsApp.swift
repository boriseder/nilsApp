// App Group
import SwiftUI
import os // Import os for Logger

/// AppDelegate is used here strictly to enforce the Landscape orientation lock programmatically.
/// This ensures a stable, media-focused experience for the child and prevents accidental rotations.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Lock the entire app to landscape (left and right)
        return .landscape
    }
}

@main
struct NilsAppApp: App {
    // Connect the AppDelegate to the SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Observe the app's lifecycle state (foreground/background)
    @Environment(\.scenePhase) private var scenePhase
    
    private let logger = Logger(subsystem: "com.nilsapp", category: "NilsAppApp")
    
    // MARK: - Core Services
    @StateObject private var persistenceService: PersistenceService
    @StateObject private var spotifyAPIService: SpotifyAPIService
    @StateObject private var spotifySDKService: SpotifySDKService
    
    // MARK: - Shared ViewModels
    @StateObject private var playerViewModel: PlayerViewModel
    
    @State private var showSplash = true
    
    init() {
        // 1. Erstelle die Basis-Instanzen
            let api = SpotifyAPIService()
            let sdk = SpotifySDKService(apiService: api)
            let persistence = PersistenceService()
            
            // 2. Initialisiere die StateObjects EINMALIG mit diesen Instanzen
            _spotifyAPIService = StateObject(wrappedValue: api)
            _spotifySDKService = StateObject(wrappedValue: sdk)
            _persistenceService = StateObject(wrappedValue: persistence)
            
            // 3. PlayerViewModel nutzt das bereits erstellte sdk
            _playerViewModel = StateObject(wrappedValue: PlayerViewModel(sdkService: sdk))
            
            // WICHTIG: Keine weiteren Zuweisungen an _spotifyAPIService danach!
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                } else {
                    HomeView()
                        .environmentObject(persistenceService)
                        .environmentObject(spotifyAPIService)
                        .environmentObject(spotifySDKService)
                        .environmentObject(playerViewModel)
                        .transition(.opacity)
                        // Handle incoming URLs, specifically for Spotify OAuth redirects.
                        .onOpenURL { url in
                            self.logger.info("Received URL: \(url.absoluteString, privacy: .public)")
                            // Check if the URL is a Spotify redirect URI.
                            // The SpotifyAPIService will handle the actual token exchange.
                            if url.scheme == Constants.spotifyRedirectURI.scheme {
                                Task { try? await self.spotifyAPIService.handleRedirectURL(url) }
                            }
                        }
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // Reconnect to the Spotify App Remote SDK when coming to the foreground
                spotifySDKService.connect()
            case .background:
                // Disconnect to clean up resources when fully backgrounded
                spotifySDKService.disconnect()
            case .inactive:
                // Do nothing. Disconnecting on inactive (e.g., pulling down Control Center) 
                // drops the connection prematurely and interrupts the child's experience.
                break
            default:
                break
            }
        }
    }
}
