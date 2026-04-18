# Gemini Coding Instructions: Safe Spotify for Kids App

## 1. Project Context & Persona
You are acting as an expert, world-class iOS Swift engineer. 
We are building a "walled garden" Spotify player for a 6-year-old child on iPadOS.
The core goal is absolute safety and simplicity: the child can ONLY access content specifically curated by the parent via a PIN-protected admin area.

## 2. Tech Stack & Architecture
*   **Platform:** iPadOS
*   **Language:** Swift 6 (Use modern Swift features, especially `async/await` for concurrency. Ensure strict concurrency compliance where practical).
*   **UI Framework:** SwiftUI.
*   **Architecture:** Modern SwiftUI MVVM.
    *   **Models:** Pure, stateless `Codable` structs.
    *   **Views:** Lightweight, declarative, state-driven UI.
    *   **ViewModels:** `ObservableObject` classes handling business logic and state.
    *   **Services:** Abstract external dependencies (`SpotifyAPIService`, `PersistenceService`, `SpotifySDKService`) and inject them into ViewModels.

## 3. Strict Coding Guidelines
*   **Pragmatism Over Cleverness:** Write clean, readable, and maintainable code. Do not over-engineer or use complex design patterns (like TCA or VIPER) unless absolutely necessary.
*   **The Walled Garden:** NEVER introduce UI or code that allows the child to escape the app. No external WebViews, no "Open in Spotify" links, no social features. **Assume the app is running in Guided Access mode** to lock the user in.
*   **Admin Area Security:** The parent's admin area must use a custom in-app PIN. **DO NOT** suggest or implement Face ID, Touch ID, or Device Passcode fallback, as children often know the device passcode.
*   **OOTB Admin UI:** The admin view should use standard SwiftUI components (`List`, `Form`). Prioritize function over form here.
*   **Kid-Friendly UX:** 
    *   Account for empty states (hide empty categories entirely), loading states, and network errors visually.
    *   If silent token refresh fails, display an "Ask a grown-up to log in" error state. **NEVER** present the Spotify OAuth login web view in the child's UI.
    *   Implement **Tap Debouncing** on all child-facing navigation actions.
    *   Lock UI to **Landscape orientation**.
*   **Accessibility & Controls:** Support Dynamic Type (Admin area), VoiceOver, and rely strictly on physical hardware buttons for volume (do not build custom volume sliders).

## 4. Key External Integrations
*   **Spotify iOS App Remote SDK:** Used exclusively for playback control. *Crucial constraint:* Requires the main Spotify app installed. Handle app lifecycle events (`scenePhase`) to reconnect seamlessly.
    *   When the SDK disconnects due to the ~30s pause timeout, show a reconnect affordance (e.g., a "Tap to Resume" button) on the Now Playing screen.
    *   **DO NOT** attempt to maintain a keepalive heartbeat to prevent the timeout, as this violates Spotify's guidelines.
*   **Peter-Schorn/SpotifyAPI (Swift Package):** Used for all data fetching (metadata, searching, pagination) and OAuth token management (including background refresh).

## 5. Current Data Models Context
The app curates three types of content, stored locally via `PersistenceService`:
1.  `CuratedArtist` (Audiobook Series) -> Fetches multiple `Album`s.
2.  `[CuratedPlaylist]` (Music Playlists) -> Fetches multiple `Track`s.
3.  `CuratedShow` (Podcast) -> Fetches multiple `Episode`s.

## 6. Standard Operating Procedure for Prompts
When asked to implement a feature:
1.  Determine if it belongs in a View, ViewModel, or Service.
2.  Provide the code with clear comments explaining the *why*, especially for Spotify SDK quirks.
3.  Ensure error handling and state management (Loading/Success/Error) are included by default.
4.  If a request violates the "Walled Garden" or Admin security rules, warn the user immediately.
5.  For long-form playback (Audiobooks/Podcasts), always integrate a local playback position cache fallback.