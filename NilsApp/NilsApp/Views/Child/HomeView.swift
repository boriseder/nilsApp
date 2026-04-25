// Views/Child Group
import SwiftUI

/// The main screen for the child, displaying large, tappable category tiles.
struct HomeView: View {
    @EnvironmentObject private var persistenceService: PersistenceService
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @StateObject private var viewModel = HomeViewModel()

    @State private var showNowPlayingSheet: Bool = false

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 300, maximum: 400))
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.cyan.opacity(0.2), .mint.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                if persistenceService.curatedContent.audiobookSeries.isEmpty &&
                   persistenceService.curatedContent.musicPlaylists.isEmpty &&
                   persistenceService.curatedContent.podcastShows.isEmpty {
                    emptyCuratedContentState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 40) {

                            if !persistenceService.curatedContent.audiobookSeries.isEmpty {
                                NavigationLink {
                                    if persistenceService.curatedContent.audiobookSeries.count == 1 {
                                        AudiobookGridView(viewModel: AudiobookGridViewModel(
                                            artists: persistenceService.curatedContent.audiobookSeries,
                                            apiService: spotifyAPIService,
                                            persistenceService: persistenceService
                                        ))
                                    } else {
                                        AudiobookSeriesSelectionView(
                                            artists: persistenceService.curatedContent.audiobookSeries
                                        )
                                    }
                                } label: {
                                    CategoryTile(
                                        title: "Meine Hörbücher",
                                        imageName: "book.closed.fill",
                                        accentColor: .orange
                                    )
                                }
                            }

                            if !persistenceService.curatedContent.musicPlaylists.isEmpty {
                                NavigationLink {
                                    if persistenceService.curatedContent.musicPlaylists.count == 1 {
                                        MusicPlaylistView(viewModel: PlaylistViewModel(
                                            playlists: persistenceService.curatedContent.musicPlaylists,
                                            apiService: spotifyAPIService,
                                            persistenceService: persistenceService
                                        ))
                                    } else {
                                        MusicPlaylistSelectionView(
                                            playlists: persistenceService.curatedContent.musicPlaylists
                                        )
                                    }
                                } label: {
                                    CategoryTile(
                                        title: "Meine Playlists",
                                        imageName: "music.note.list",
                                        accentColor: .purple
                                    )
                                }
                            }

                            if !persistenceService.curatedContent.podcastShows.isEmpty {
                                NavigationLink {
                                    if persistenceService.curatedContent.podcastShows.count == 1 {
                                        PodcastShowView(viewModel: PodcastViewModel(
                                            shows: persistenceService.curatedContent.podcastShows,
                                            apiService: spotifyAPIService,
                                            persistenceService: persistenceService
                                        ))
                                    } else {
                                        PodcastShowSelectionView(
                                            shows: persistenceService.curatedContent.podcastShows
                                        )
                                    }
                                } label: {
                                    CategoryTile(
                                        title: "Meine Videos",
                                        imageName: "mic.fill",
                                        accentColor: .green
                                    )
                                }
                            }

                        }
                        .padding(40)
                    }
                }

                if playerViewModel.currentTrackURI != nil {
                    VStack {
                        Spacer()
                        MiniPlayerBar(showNowPlayingSheet: $showNowPlayingSheet)
                            .environmentObject(playerViewModel)
                            .transition(.move(edge: .bottom))
                    }
                }
            }
            .toolbar {
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
            PINEntryView(viewModel: AdminViewModel(
                persistenceService: persistenceService,
                spotifyAPIService: spotifyAPIService
            ))
            .environmentObject(persistenceService)
            .environmentObject(spotifyAPIService)
            .environmentObject(playerViewModel)
        }
        .sheet(isPresented: $showNowPlayingSheet) {
            NowPlayingView()
                .environmentObject(playerViewModel)
        }
    }

    // MARK: - Subviews

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
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
    }

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
        let service = PersistenceService()
        let mockContent = CuratedContent(
            audiobookSeries: [CuratedArtist(id: "1", name: "Pumuckl", imageURL: nil)],
            musicPlaylists: [CuratedPlaylist(id: "1", name: "Dance", imageURL: nil)],
            podcastShows: []
        )
        service.save(mockContent)

        let apiService = SpotifyAPIService()
        let sdkService = SpotifySDKService(apiService: apiService)

        return HomeView()
            .environmentObject(service)
            .environmentObject(apiService)
            .environmentObject(PlayerViewModel(sdkService: sdkService))
            .environmentObject(sdkService)
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
