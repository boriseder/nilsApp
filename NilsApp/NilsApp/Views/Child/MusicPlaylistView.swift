import SwiftUI

struct MusicPlaylistView: View {
    @StateObject var viewModel: PlaylistViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.95, blue: 1.0)
                .ignoresSafeArea()

            backgroundDecoration

            if viewModel.isLoading && viewModel.tracks.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else if viewModel.tracks.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                            trackRow(for: track, index: index)

                            if index < viewModel.tracks.count - 1 {
                                Divider()
                                    .padding(.leading, 96)
                                    .padding(.trailing, 24)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.7))
                    )
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await viewModel.fetchTracksAsync(forceRefresh: true)
                }
            }
        }
        .navigationTitle(
            viewModel.playlists.count == 1
                ? viewModel.playlists.first?.name ?? "Musik"
                : "Meine Playlists"
        )
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.fetchTracks() }
    }

    // MARK: - Track Row

    private func trackRow(for track: SpotifyTrack, index: Int) -> some View {
        let isPlaying = playerViewModel.currentTrackURI == track.uri
            && playerViewModel.isPlaying

        return HStack(spacing: 16) {
            // Track Nummer oder Playing-Indicator
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.55, green: 0.3, blue: 0.9))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.6, green: 0.55, blue: 0.65))
                }
            }
            .frame(width: 28)

            // Album Art
            Group {
                if let url = track.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        trackPlaceholder
                    }
                } else {
                    trackPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(
                color: Color.purple.opacity(isPlaying ? 0.4 : 0.0),
                radius: 8,
                x: 0,
                y: 2
            )

            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 17, weight: isPlaying ? .bold : .semibold, design: .rounded))
                    .foregroundColor(
                        isPlaying
                            ? Color(red: 0.55, green: 0.3, blue: 0.9)
                            : Color(red: 0.15, green: 0.12, blue: 0.1)
                    )
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.6, green: 0.55, blue: 0.65))
                    .lineLimit(1)
            }

            Spacer()

            // Dauer
            Text(formatDuration(track.duration))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.7, green: 0.65, blue: 0.75))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            isPlaying
                ? Color(red: 0.55, green: 0.3, blue: 0.9).opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onDebouncedTap {
            playerViewModel.play(uri: track.uri, isLongForm: false)
        }
    }

    private var trackPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.purple.opacity(0.15))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.purple.opacity(0.5))
            )
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(red: 0.55, green: 0.3, blue: 0.9))
            Text("Lädt Musik…")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.55))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.purple.opacity(0.4))
            Text("Keine Songs gefunden")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.55))
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Hoppla!")
                .font(.system(size: 28, weight: .heavy, design: .rounded))

            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Button("Nochmal versuchen") {
                viewModel.fetchTracks()
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.purple))
            .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 4)
        }
    }

    private var backgroundDecoration: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.07))
                .frame(width: 350, height: 350)
                .offset(x: -180, y: -120)

            Circle()
                .fill(Color.purple.opacity(0.05))
                .frame(width: 200, height: 200)
                .offset(x: 200, y: 350)
        }
        .ignoresSafeArea()
    }
}
