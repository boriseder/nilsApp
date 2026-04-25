// Views/Child Group
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var persistenceService: PersistenceService
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @StateObject private var viewModel = HomeViewModel()

    @StateObject private var audiobookGridViewModel = AudiobookGridViewModel()
    @StateObject private var playlistViewModel = PlaylistViewModel()
    @StateObject private var podcastViewModel = PodcastViewModel()

    @State private var showNowPlayingSheet = false
    @State private var appearAnimated = false

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Warmer, ruhiger Hintergrund
                Color(red: 0.97, green: 0.96, blue: 0.93)
                    .ignoresSafeArea()

                // Dekorative Kreise im Hintergrund
                backgroundDecoration

                if persistenceService.curatedContent.audiobookSeries.isEmpty &&
                   persistenceService.curatedContent.musicPlaylists.isEmpty &&
                   persistenceService.curatedContent.podcastShows.isEmpty {
                    emptyCuratedContentState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            header
                                .padding(.horizontal, 40)
                                .padding(.top, 20)
                                .padding(.bottom, 32)

                            // Category Grid
                            LazyVGrid(columns: columns, spacing: 24) {
                                audiobooksLink
                                musicLink
                                podcastsLink
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, playerViewModel.currentTrackURI != nil ? 120 : 40)
                        }
                    }
                }

                // MiniPlayer
                if playerViewModel.currentTrackURI != nil {
                    VStack {
                        Spacer()
                        MiniPlayerBar(showNowPlayingSheet: $showNowPlayingSheet)
                            .environmentObject(playerViewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    adminButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            configureViewModels()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appearAnimated = true
            }
        }
        .onChange(of: persistenceService.curatedContent) { _, _ in
            configureViewModels()
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hallo, Nils! 👋")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))

                Text("Was möchtest\ndu hören?")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))
                    .lineSpacing(2)
            }
            .opacity(appearAnimated ? 1 : 0)
            .offset(y: appearAnimated ? 0 : 20)

            Spacer()
        }
    }

    // MARK: - Background Decoration

    private var backgroundDecoration: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 400, height: 400)
                .offset(x: -150, y: -200)

            Circle()
                .fill(Color.purple.opacity(0.07))
                .frame(width: 300, height: 300)
                .offset(x: 200, y: 100)

            Circle()
                .fill(Color.green.opacity(0.07))
                .frame(width: 250, height: 250)
                .offset(x: 100, y: 400)
        }
        .ignoresSafeArea()
    }

    // MARK: - Admin Button

    private var adminButton: some View {
        Button {
            viewModel.showAdminArea = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
            }
        }
    }

    // MARK: - Navigation Links

    @ViewBuilder
    private var audiobooksLink: some View {
        if !persistenceService.curatedContent.audiobookSeries.isEmpty {
            NavigationLink {
                if persistenceService.curatedContent.audiobookSeries.count == 1 {
                    AudiobookGridView(viewModel: audiobookGridViewModel)
                } else {
                    AudiobookSeriesSelectionView(
                        artists: persistenceService.curatedContent.audiobookSeries
                    )
                }
            } label: {
                CategoryCard(
                    title: "Hörbücher",
                    subtitle: "\(persistenceService.curatedContent.audiobookSeries.count) Serien",
                    icon: "headphones",
                    accentColor: Color(red: 1.0, green: 0.55, blue: 0.2),
                    bgColor: Color(red: 1.0, green: 0.93, blue: 0.84),
                    index: 0,
                    animated: appearAnimated
                )
            }
            .buttonStyle(BounceButtonStyle())
        }
    }

    @ViewBuilder
    private var musicLink: some View {
        if !persistenceService.curatedContent.musicPlaylists.isEmpty {
            NavigationLink {
                if persistenceService.curatedContent.musicPlaylists.count == 1 {
                    MusicPlaylistView(viewModel: playlistViewModel)
                } else {
                    MusicPlaylistSelectionView(
                        playlists: persistenceService.curatedContent.musicPlaylists
                    )
                }
            } label: {
                CategoryCard(
                    title: "Musik",
                    subtitle: "\(persistenceService.curatedContent.musicPlaylists.count) Playlists",
                    icon: "music.note",
                    accentColor: Color(red: 0.55, green: 0.3, blue: 0.9),
                    bgColor: Color(red: 0.93, green: 0.89, blue: 0.99),
                    index: 1,
                    animated: appearAnimated
                )
            }
            .buttonStyle(BounceButtonStyle())
        }
    }

    @ViewBuilder
    private var podcastsLink: some View {
        if !persistenceService.curatedContent.podcastShows.isEmpty {
            NavigationLink {
                if persistenceService.curatedContent.podcastShows.count == 1 {
                    PodcastShowView(viewModel: podcastViewModel)
                } else {
                    PodcastShowSelectionView(
                        shows: persistenceService.curatedContent.podcastShows
                    )
                }
            } label: {
                CategoryCard(
                    title: "Videos",
                    subtitle: "\(persistenceService.curatedContent.podcastShows.count) Shows",
                    icon: "play.tv",
                    accentColor: Color(red: 0.15, green: 0.75, blue: 0.45),
                    bgColor: Color(red: 0.86, green: 0.97, blue: 0.91),
                    index: 2,
                    animated: appearAnimated
                )
            }
            .buttonStyle(BounceButtonStyle())
        }
    }

    // MARK: - Category Card

    private struct CategoryCard: View {
        let title: String
        let subtitle: String
        let icon: String
        let accentColor: Color
        let bgColor: Color
        let index: Int
        let animated: Bool

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                // Hintergrund
                RoundedRectangle(cornerRadius: 28)
                    .fill(bgColor)

                // Dekorativer Kreis rechts oben
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .offset(x: 60, y: -60)

                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .offset(x: 80, y: -20)

                // Icon rechts oben
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.2))
                                .frame(width: 72, height: 72)

                            Image(systemName: icon)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        .padding(.top, 28)
                        .padding(.trailing, 28)
                    }
                    Spacer()
                }

                // Text unten links
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(0.15))
                        )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .frame(height: 220)
            .shadow(color: accentColor.opacity(0.2), radius: 20, x: 0, y: 8)
            .opacity(animated ? 1 : 0)
            .offset(y: animated ? 0 : 30)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.75)
                .delay(Double(index) * 0.1 + 0.2),
                value: animated
            )
        }
    }

    // MARK: - Bounce Button Style

    private struct BounceButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }

    // MARK: - Empty State

    private var emptyCuratedContentState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
            }

            Text("Willkommen!")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))

            Text("Tippe auf das Zahnrad,\num Inhalte hinzuzufügen.")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
                .padding(.horizontal, 60)
        }
    }

    // MARK: - Configure

    private func configureViewModels() {
        let content = persistenceService.curatedContent
        audiobookGridViewModel.configure(
            artists: content.audiobookSeries,
            apiService: spotifyAPIService,
            persistenceService: persistenceService
        )
        playlistViewModel.configure(
            playlists: content.musicPlaylists,
            apiService: spotifyAPIService,
            persistenceService: persistenceService
        )
        podcastViewModel.configure(
            shows: content.podcastShows,
            apiService: spotifyAPIService,
            persistenceService: persistenceService
        )
    }
}
