// Views/Child Group
import SwiftUI

/// The main screen for the child, displaying large, tappable category tiles.
struct HomeView: View {
    @EnvironmentObject private var persistenceService: PersistenceService
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService // Inject SpotifyAPIService
    @EnvironmentObject private var playerViewModel: PlayerViewModel // Access the shared player state
    @StateObject private var viewModel = HomeViewModel()

    @State private var showNowPlayingSheet: Bool = false // State variable to control the presentation of the NowPlayingView sheet.

    // Use a flexible grid with a minimum item size to adapt to different iPad sizes.
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 300, maximum: 400))
    ]

    var body: some View {
        // The NavigationView is used for navigation and toolbar items.
        NavigationView {
            ZStack {
                // A subtle background color for the home screen
                Color(.systemGroupedBackground).ignoresSafeArea()

                // TODO: Add empty state view when no content is curated at all.

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        // Only show the Audiobook tile if content has been curated.
                        if let firstAudiobookArtist = persistenceService.curatedContent.audiobookSeries.first {
                            // NavigationLink to the AudiobookGridView
                            NavigationLink {
                                AudiobookGridView(viewModel: AudiobookGridViewModel(artist: firstAudiobookArtist, apiService: spotifyAPIService))
                            } label: {
                                CategoryTile(
                                    title: "Audiobooks",
                                    imageName: "book.closed.fill",
                                    accentColor: .orange
                                )
                            }
                            // Apply debounced tap to prevent rapid navigation
                            .buttonStyle(DebouncedButtonStyle())
                        }

                        // Only show the Music tile if content has been curated.
                        if !persistenceService.curatedContent.musicPlaylists.isEmpty {
                            Text("Music Tile") // Placeholder
                        }

                        // Only show the Podcast tile if content has been curated.
                        if !persistenceService.curatedContent.podcastShows.isEmpty {
                            Text("Podcasts Tile") // Placeholder
                        }
                    }
                    .padding(40)
                }
                
                // Mini-player bar appears at the bottom when a track is loaded
                // This is placed within the ZStack to float above the ScrollView content.
                if playerViewModel.currentTrackURI != nil {
                    VStack {
                        Spacer() // Pushes the mini-player to the bottom
                        MiniPlayerBar(showNowPlayingSheet: $showNowPlayingSheet)
                            .environmentObject(playerViewModel) // Ensure playerViewModel is available
                            .transition(.move(edge: .bottom)) // Smooth transition when it appears/disappears
                    }
                }
            }
            // Navigation title and toolbar items are associated with the NavigationView.
                .navigationTitle("My Library")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                // Admin button moved to the trailing edge of the navigation bar
                // to avoid conflict with the mini-player at the bottom.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showAdminArea = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title)
                    }
                }
            }
        }
        .navigationViewStyle(.stack) // Use stack style for iPad
        .sheet(isPresented: $viewModel.showAdminArea) {
            // The Admin view will be presented here.
            // For now, it's a placeholder Text.
            Text("Admin Area Placeholder")
        }
        // Present the NowPlayingView as a sheet when showNowPlayingSheet is true.
        .sheet(isPresented: $showNowPlayingSheet) {
            NowPlayingView()
                .environmentObject(playerViewModel) // Ensure playerViewModel is available
        }
    }
    
    // MARK: - Subviews
    
    /// A reusable tile for categories like Audiobooks, Music, Podcasts.
    private struct CategoryTile: View {
        let title: String
        let imageName: String
        let accentColor: Color
        
        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: imageName)
                    .font(.system(size: 100))
                    .foregroundColor(accentColor)
                
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 30)) // Make the entire area tappable
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with some mock data to see the tiles
        let service = PersistenceService()
        let mockContent = CuratedContent(audiobookSeries: [CuratedArtist(id: "1", name: "Pumuckl", imageURL: nil)], musicPlaylists: [CuratedPlaylist(id: "1", name: "Dance", imageURL: nil)], podcastShows: [])
        service.save(mockContent)

        return HomeView()
            .environmentObject(service)
            .previewInterfaceOrientation(.landscapeLeft)
    }
}