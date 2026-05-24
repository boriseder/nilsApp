import UIKit

extension UIApplication {
    // We execute this once to swap the methods in memory
    @MainActor
    static let patchSpotifySDK: Void = {
        // Using NSSelectorFromString avoids Swift compiler warnings for deprecated methods
        let originalSelector = NSSelectorFromString("openURL:")
        let swizzledSelector = #selector(modern_openURL(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIApplication.self, swizzledSelector) else {
            print("Failed to patch Spotify SDK")
            return
        }
        
        // Swap the broken SDK method with our modern implementation
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    // This method intercepts Spotify's outgoing call
    @MainActor
    @objc dynamic func modern_openURL(_ url: URL) -> Bool {
        // Route the request to the modern, non-deprecated iOS API
        self.open(url, options: [:], completionHandler: nil)
        
        // Return true to trick the Spotify SDK into thinking its synchronous call succeeded
        return true
    }
}
