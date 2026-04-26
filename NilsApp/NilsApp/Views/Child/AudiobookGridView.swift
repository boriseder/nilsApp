// Child Views Group
import SwiftUI

struct AudiobookGridView: View {
    @StateObject var viewModel: AudiobookGridViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 28)
    ]

    // Welches Album gerade gedrückt wird — für Press-Animation
    @State private var pressedAlbumId: String?

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.93)
                .ignoresSafeArea()

            backgroundDecoration

            if viewModel.isLoading && viewModel.albums.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else if viewModel.albums.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(viewModel.albums) { album in
                            albumCard(for: album)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await viewModel.fetchAlbumsAsync(forceRefresh: true)
                }
            }
        }
        .navigationTitle(
            viewModel.artists.count == 1
                ? viewModel.artists.first?.name ?? "Hörbücher"
                : "Meine Hörbücher"
        )
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.fetchAlbums() }
    }

    // MARK: - Album Card

    private func albumCard(for album: SpotifyAlbum) -> some View {
        let isPressed = pressedAlbumId == album.id
        let isCurrentlyPlaying = playerViewModel.currentTrackURI == album.uri
            && playerViewModel.isPlaying

        return VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                // Cover Art
                Group {
                    if let url = album.imageURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            albumPlaceholder
                        }
                    } else {
                        albumPlaceholder
                    }
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(
                    color: Color.orange.opacity(isCurrentlyPlaying ? 0.5 : 0.15),
                    radius: isCurrentlyPlaying ? 20 : 12,
                    x: 0,
                    y: 6
                )

                // Playing-Indicator
                if isCurrentlyPlaying {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 40, height: 40)

                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: -8, y: -8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)

            // Titel
            Text(album.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))
                .frame(maxWidth: 220)
        }
        .onDebouncedTap {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                pressedAlbumId = album.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { pressedAlbumId = nil }
                // Play the album URI as the context so Spotify auto-advances between
                // tracks/chapters within the album — enabling gapless playback.
                playerViewModel.play(uri: album.uri, contextURI: album.uri, isLongForm: true)
            }
        }
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.3),
                        Color.orange.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 220, height: 220)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange.opacity(0.6))
            )
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.orange)
            Text("Lädt Geschichten…")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.5))
            Text("Noch keine Bücher")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Hoppla!")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))

            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
                .padding(.horizontal, 60)

            Button("Nochmal versuchen") {
                viewModel.fetchAlbums()
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Color.orange)
            )
            .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 4)
        }
    }

    private var backgroundDecoration: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.07))
                .frame(width: 350, height: 350)
                .offset(x: 200, y: -150)

            Circle()
                .fill(Color.orange.opacity(0.05))
                .frame(width: 250, height: 250)
                .offset(x: -150, y: 300)
        }
        .ignoresSafeArea()
    }
}
