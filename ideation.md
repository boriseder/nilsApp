# Project: Safe Spotify for a 6-Year-Old

This document outlines the ideation phase for an iPad app designed to provide a safe and simple Spotify experience for a young child.

## 1. Core Concept

A "walled garden" music player for the iPad. The app will use a parent's Spotify Premium account but will only expose pre-approved playlists and songs to the child. This prevents access to explicit content, podcasts, or the full, overwhelming Spotify catalog, ensuring a safe listening environment.

## 2. Target Audience

*   **Primary User:** A 6-year-old child. The user interface (UI) and user experience (UX) must be tailored to this age group: highly visual, simple to navigate, and resilient to accidental taps.
*   **Secondary User (Administrator):** The parent. The parent is responsible for setting up the app, authenticating with Spotify, and curating the content available to the child.

## 3. Key Features & User Stories

### For the Child (The "Player" View)
The app will have three distinct sections for the child, based on the core use cases.

*   **Visual Playlist Navigation:** Instead of text lists, the child will see large, tappable album art or custom playlist images to choose their music.
*   **Simplified Playback:** A clean "Now Playing" screen with huge, obvious buttons for Play/Pause, Next, and Previous. Volume control will likely be handled by the iPad's physical buttons to keep the interface simple.
*   **No Search or Browse:** The child cannot search for new music or browse Spotify's general library. They can only access what the parent has selected.
*   **Strict Walled Garden:** The app will be locked using iOS's **Guided Access** feature. This is a system-level lock that prevents the child from exiting the app, ensuring they cannot access the main Spotify app or any other part of the OS. This is more robust than simply hiding app icons.
*   **No Social Features:** All links to social sharing, friend activity, etc., will be removed.
### Use Case 1: Audiobooks (e.g., "Pumuckl", "TKKG Junior")

*   **Hierarchical Navigation:** The main screen will show the approved audiobook series (represented as Spotify "Artists"). Tapping a series will lead to a visual grid of all its stories (represented as "Albums").
*   **Visual Album Grid:** The screen for a series must be able to display a large number of albums (~100+) in a child-friendly way, likely a horizontally scrolling grid of album covers.
*   **Simple Playback:** Tapping an album cover starts playback from the beginning of that album (story).
*   **Scrubber Control:** The "Now Playing" screen for audiobooks will feature a prominent slider/scrubber so the child can easily move to different parts of the story, but track-by-track selection is not needed.

> **User Story:** "As a 6-year-old, I want to tap on the 'Pumuckl' picture, then scroll through all the story pictures until I find the one I want to listen to."

### Use Case 2: Music Playlist

*   **Direct Access:** The main screen will provide access to a small number (e.g., 2-3) of curated music playlists (e.g., "Calm Music," "Dance Songs").
*   **Full Playlist Control:** Inside a playlist view, the child can see all the songs, tap a specific song to play it, shuffle the entire playlist, or just play from the top.
*   **Standard Playback Screen:** The "Now Playing" screen will have large Play/Pause, Next, and Previous buttons.

> **User Story:** "As a 6-year-old, I want to tap on 'Dance Songs', see the list, and be able to play my favorite one right away or shuffle them all."

### Use Case 3: Curated Podcasts

*   **Simple Podcast Library:** Similar to audiobooks, the main screen will provide access to a list of parent-approved podcast shows.
*   **Episode List:** Tapping a podcast show will display a simple, vertical list of available episodes (newest first).
*   **Direct Episode Play:** Tapping an episode starts playback.

> **User Story:** "As a 6-year-old, I want to see the picture of my favorite science show and tap on the latest episode to listen."

---

### For the Parent (The "Admin" View)

The parent's setup view will focus purely on utility. We will use out-of-the-box (OOTB) standard SwiftUI lists and controls—no need for a visually rich UX, just simple and functional curation.

*   **Secure Setup:** The parent will log in with their Spotify account. This part of the app will be protected by a simple PIN to prevent the child from accessing settings.
*   **App-Specific Passcode:** The admin area will be protected by a custom, app-specific PIN. It will explicitly *not* support Face ID or Touch ID, preventing the child from bypassing the lock using the iPad's device passcode fallback.
*   **Content Curation:** The admin screen will have three straightforward sections for the parent to manage:
    1.  **Audiobook Series:** The parent can search for and approve specific Spotify "Artists" (e.g., "Meister Eder und sein Pumuckl", "TKKG Junior").
    2.  **Music Playlists:** The parent can select a small number (2-3) of their personal playlists to make available to the child.
    3.  **Podcasts:** The parent can search for and approve specific podcast shows.
*   **Implicit Filtering:** The app should still automatically hide any tracks/episodes flagged as "explicit" by Spotify, even within an approved series or playlist.
*   **Screen Time Tracking:** iOS natively supports Screen Time for all installed apps. No custom code is required; you will be able to monitor app usage and set time limits directly from the iPad's system settings.

> **User Story:** "As a parent, I want to log in once, pick the specific audiobook series, the one playlist, and the specific podcasts that are okay for my son, and then lock it so he can't change it."

## 4. Tech Stack & Initial Considerations

*   **Platform:** iPadOS
*   **Language:** Swift 6 (using the latest stable Swift version).
*   **UI Framework:** SwiftUI.
*   **Core Dependencies:**
    *   **Data Layer:** The `Peter-Schorn/SpotifyAPI` Swift package will be used for all Spotify Web API interactions, including authentication, token refresh, and data fetching.
    *   **Playback Layer:** The official `Spotify App Remote SDK` will be used for controlling playback.
*   **Crucial SDK Constraint:** The App Remote SDK requires the main Spotify app to be installed. The "Walled Garden" will be enforced via **iOS Guided Access**, which makes the presence of the main Spotify app irrelevant as the child cannot switch to it.

## 5. Architecture: SwiftUI with MVVM

For this project, we will adopt a modern, pragmatic **MVVM (Model-View-ViewModel)** architecture tailored for SwiftUI. This pattern provides an excellent balance of structure, testability, and scalability without being over-engineered.

*   **Model (M):** The source of truth for our data. These are the simple `Codable` structs we've already defined (e.g., `CuratedContent`, `CuratedArtist`). They contain no business logic.

*   **View (V):** The SwiftUI views. Their only job is to display data provided by the ViewModel and to forward user interactions (like a button tap) to the ViewModel. They will be lightweight and declarative.

*   **ViewModel (VM):** `ObservableObject` classes that act as the bridge between the Model and the View. They contain the state and business logic for a given screen or feature.

### Key ViewModel Components:

*   **`HomeViewModel`**: Manages the display logic for the main screen, showing the curated categories if they exist.
*   **`AudiobookGridViewModel`**: Responsible for fetching and displaying the grid of albums for a selected `CuratedArtist`.
*   **`PlaylistViewModel`**: Fetches and manages the list of tracks for the `CuratedPlaylist`.
*   **`PodcastViewModel`**: Fetches and manages the list of episodes for a selected `CuratedShow`.
*   **`PlayerViewModel`**: A crucial, shared ViewModel (likely injected as an `@EnvironmentObject`) that manages the connection to the Spotify SDK and holds the global playback state (e.g., current track, playing/paused status, playback progress). This decouples all playback logic from the individual views.
*   **`AdminViewModel`**: Handles all logic for the parent's section, including PIN validation, searching Spotify, and saving the `CuratedContent` model.

### Services & Dependency Injection:

To keep our ViewModels clean and testable, we will abstract external dependencies into "Services" that are injected into the ViewModels.
*   **`SpotifyAPIService`**: A wrapper around the `Peter-Schorn/SpotifyAPI` package. It will handle authentication and data fetching logic.
*   **`PersistenceService`**: A new service responsible for saving and loading the `CuratedContent` object to/from the device's local storage.
*   **`SpotifySDKService`**: A wrapper around the Spotify App Remote SDK to manage connection, authentication, and playback commands. This will be the primary dependency for our `PlayerViewModel`.

This approach ensures a clean separation of concerns, makes the app highly testable, and aligns perfectly with modern SwiftUI development practices for 2026.

## 6. Visual Design Language: Apple's Human Interface Guidelines (HIG)

To define how the app will look, we will adhere strictly to Apple's Human Interface Guidelines. This provides a best-practice, high-quality, and familiar foundation for the app's visual design, aligning with our goal of a pragmatic, modern application.

Our application of the HIG will focus on:

*   **Clarity & Deference:** The UI will be minimal and defer to the content (album and podcast art). We will use generous spacing, extremely large touch targets, and legible typography. The overall aesthetic will be clean and simple, avoiding custom chrome or distracting backgrounds.
*   **Standard Components:** We will prioritize the use of standard, unmodified SwiftUI components which are inherently HIG-compliant.
    *   **Grids (`LazyVGrid`):** For the audiobook album selection screen.
    *   **Lists (`List`):** For the music playlist and podcast episode lists.
    *   **Sheets:** For presenting the "Now Playing" view and the PIN-entry screen.
*   **SF Symbols:** All iconography within the app will be sourced from Apple's SF Symbols library. This ensures visual consistency, accessibility, and a native look and feel. We will select simple, universally understood symbols (e.g., `play.fill`, `music.note`, `mic.fill`) for playback controls and category buttons.
*   **Materials:** We may use system materials (e.g., `.ultraThinMaterial`) for overlays like a "Now Playing" bar to create a subtle sense of depth while letting the album art show through.

This decision formally answers how the app's UI will be designed and implemented.

## 7. Core Data Models (Defined)

To manage the parent's selections, we will define a set of `Codable` Swift structures in a new `DataModels.swift` file. These models will represent the curated items and will be saved locally on the device.

*   **`CuratedContent`**: A top-level container struct that holds all the curated data.
    *   `audiobookSeries: [CuratedArtist]`
    *   `musicPlaylists: [CuratedPlaylist]`
    *   `podcastShows: [CuratedShow]`

*   **`CuratedArtist`**: Represents an approved audiobook series (a Spotify Artist).
    *   `id: String` (Spotify Artist ID)
    *   `name: String`
    *   `imageURL: URL?`

*   **`CuratedPlaylist`**: Represents an approved music playlist.
    *   `id: String` (Spotify Playlist ID)
    *   `name: String`
    *   `imageURL: URL?`

*   **`CuratedShow`**: Represents an approved podcast show.
    *   `id: String` (Spotify Show ID)
    *   `name: String`
    *   `imageURL: URL?`

## 8. Technical Deep Dive (Completed)

*   **Fetch all albums for an artist:** **(✓ Answered)** Yes, this is possible by using the access token from the SDK to call the `GET /v1/artists/{id}/albums` Web API endpoint. We must handle pagination to retrieve all albums.
*   **Fetch all episodes for a podcast show:** **(✓ Answered)** Yes, using the `GET /v1/shows/{id}/episodes` endpoint. It functions identically to album fetching, requiring pagination to retrieve the entire list of episodes.
*   **Playback Control:** **(✓ Answered)** Yes, the Spotify App Remote SDK reliably controls playback of all three content types by passing their respective URIs (`spotify:album:{id}`, `spotify:track:{id}`, `spotify:episode:{id}`) directly to the `play` command.

## 9. Crucial Edge Cases & "Gotchas"

Before we write code, we must plan for these common technical realities:

*   **Token Refresh:** The Spotify Web API OAuth token expires every hour. The app must silently handle token refreshing in the background to prevent constant parent logins.
*   **App Lifecycle & SDK Reconnection:** The Spotify App Remote SDK disconnects when the app is backgrounded. The `SpotifySDKService` must actively listen for iOS lifecycle events and automatically reconnect to the Spotify app.
*   **Offline/Network Handling:** A kid-friendly "No Connection" UI is required for when the iPad leaves Wi-Fi. 
*   **Playback Resumption:** For long audiobooks and podcasts, we must implement a local playback position cache (e.g., in `UserDefaults`). This provides a reliable fallback, as Spotify's own position syncing can be inconsistent across sessions.
*   **Expired Spotify Premium:** The app must handle cases where the parent's Spotify Premium subscription has lapsed. This should result in a specific, child-friendly error state (e.g., "Ask a grown-up to check the music settings").
*   **SDK Pause Timeout:** The App Remote SDK disconnects after ~30 seconds of paused playback. The reconnection flow must be designed to be seamless and invisible to the child.
*   **Auth Refresh Failure:** If the API's silent token refresh completely fails and a new login is required, the app must strictly block the OAuth web view from appearing in the child's UI, showing an "Ask a grown-up to log in" error state instead.

## 10. Final Polish & UX Considerations

To ensure a high-quality experience, we should also plan for the following:

*   **Onboarding & Empty States:**
    *   **First Launch:** The app should launch into a welcoming state that directs the parent to the admin section to begin curating content.
    *   **Child's View (Empty):** If a category (e.g., Podcasts) has no curated content, it will be **hidden entirely** from the child's home screen.
*   **UI State Management:** Our ViewModels must explicitly manage and publish loading and error states. The SwiftUI views will then react to these states by showing activity indicators while fetching data, and kid-friendly messages (e.g., "Couldn't load stories, check the internet!") on failure.
*   **Accessibility (A11y):** We will adhere to modern accessibility best practices. This includes using Dynamic Type for text (especially in the parent's admin panel) and ensuring VoiceOver can navigate the app's core functions.
*   **Orientation Lock:** **(Decision: Landscape)** The app will be locked strictly to landscape mode. This provides a stable, media-focused experience and simplifies layout design.
*   **Tap Debouncing:** **(Decision: Implement)** All navigation actions in the child's UI will be debounced to prevent glitches from rapid taps. This will be implemented via a reusable SwiftUI `ViewModifier` or custom `Button` style to keep the logic clean and isolated.
*   **Volume Control:** **(Decision: Rely on System Volume)** We assume the App Remote SDK respects the iOS system volume. We will explicitly verify this during the initial SDK integration (Step 3) to ensure the iPad's physical hardware buttons are the single source of truth.
*   **App Assets:** We will need to source or create a few key visual assets:
    *   A unique App Icon.
    *   Three distinct, simple, and recognizable icons for the "Audiobooks," "Music," and "Podcasts" categories on the home screen. SF Symbols will be the first choice for simplicity.

## 11. Implementation Plan

1.  **Guided Access Setup:** Manually test and validate that Guided Access fully locks the iPad to a single app, even during the Spotify SDK's brief app-switches for authentication.
2.  **Spotify Developer App Registration:** Register the app in the Spotify Developer Dashboard to obtain a Client ID and configure the Redirect URI.
3.  **`SpotifySDKService` Skeleton:** Create the service wrapper for the App Remote SDK. Implement the core connect, disconnect, and automatic reconnection logic based on app lifecycle events.
4.  **`PersistenceService`:** Implement the service to save and load the `CuratedContent` model to/from local device storage (e.g., a JSON file in the app's documents directory).
5.  **Admin View:** Build the complete parent-facing UI, including:
    *   PIN entry screen (no biometrics).
    *   A view to search for and add/remove curated artists, playlists, and shows using the `Peter-Schorn/SpotifyAPI` package.
6.  **Child Home Screen:** Build the main view for the child, displaying the three category tiles, which are hidden if no content is curated for them.
7.  **Audiobook Grid View:** Build the `LazyVGrid` for displaying album art, powered by a paginated fetch from the `SpotifyAPIService`.
8.  **Music Playlist View:** Build the list view for displaying tracks from a curated playlist. Implement shuffle and direct play functionality.
9.  **Podcast View:** Build the list view for displaying podcast episodes, sorted with the newest first.
10. **Now Playing Screen:** Build the shared "Now Playing" view, presented as a sheet. It must include a scrubber for audiobooks/podcasts and basic controls for all media types.

---

This is our starting point. What are your thoughts? We can dive deeper into any of these sections. For example, we could start sketching out what the main screen might look like or discuss specific features you'd like to add.
