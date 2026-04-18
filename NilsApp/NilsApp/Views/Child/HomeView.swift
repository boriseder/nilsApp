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
        // NavigationStack replaces NavigationView for modern iOS and avoids iPad split-view bugs.
        NavigationStack {
            ZStack {
                // A subtle background color for the home screen
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if persistenceService.curatedContent.audiobookSeries.isEmpty &&
                   persistenceService.curatedContent.musicPlaylists.isEmpty &&
                   persistenceService.curatedContent.podcastShows.isEmpty {
                    emptyCuratedContentState
                } else {
                    
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        // Only show the Audiobook tile if content has been curated.
                        if !persistenceService.curatedContent.audiobookSeries.isEmpty {
                            // NavigationLink to the AudiobookGridView
                            NavigationLink {
                                if persistenceService.curatedContent.audiobookSeries.count == 1 {
                                    AudiobookGridView(viewModel: AudiobookGridViewModel(artists: persistenceService.curatedContent.audiobookSeries, apiService: spotifyAPIService))
                                } else {
                                    AudiobookSeriesSelectionView(artists: persistenceService.curatedContent.audiobookSeries)
                                }
                            } label: {
                                CategoryTile(
                                    title: "Audiobooks",
                                    imageName: "book.closed.fill",
                                    accentColor: .orange
                                )
                            }
                        }

                        // Only show the Music tile if content has been curated.
                        if !persistenceService.curatedContent.musicPlaylists.isEmpty {
                            NavigationLink {
                                if persistenceService.curatedContent.musicPlaylists.count == 1 {
                                    MusicPlaylistView(viewModel: PlaylistViewModel(playlists: persistenceService.curatedContent.musicPlaylists, apiService: spotifyAPIService))
                                } else {
                                    MusicPlaylistSelectionView(playlists: persistenceService.curatedContent.musicPlaylists)
                                }
                            } label: {
                                CategoryTile(
                                    title: "Music",
                                    imageName: "music.note.list",
                                    accentColor: .purple
                                )
                            }
                        }

                        // Only show the Podcast tile if content has been curated.
                        if !persistenceService.curatedContent.podcastShows.isEmpty {
                            NavigationLink {
                                if persistenceService.curatedContent.podcastShows.count == 1 {
                                    PodcastShowView(viewModel: PodcastViewModel(shows: persistenceService.curatedContent.podcastShows, apiService: spotifyAPIService))
                                } else {
                                    PodcastShowSelectionView(shows: persistenceService.curatedContent.podcastShows)
                                }
                            } label: {
                                CategoryTile(
                                    title: "Podcasts",
                                    imageName: "mic.fill",
                                    accentColor: .green
                                )
                            }
                        }
                    }
                    .padding(40)
                }
                    
                } // End of else block
                
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
            // Navigation title and toolbar items are associated with the NavigationStack.
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
        .sheet(isPresented: $viewModel.showAdminArea) {
            PINEntryView(viewModel: AdminViewModel(persistenceService: persistenceService, spotifyAPIService: spotifyAPIService))
                .environmentObject(persistenceService)
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
    
    /// State view shown when no content has been curated by the parent yet.
    private var emptyCuratedContentState: some View {
        VStack(spacing: 30) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)
            
            Text("Welcome to NilsApp!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("It looks like you haven't curated any content yet. Tap the gear icon to get started!")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)
        }
        .foregroundColor(.secondary)
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