import SwiftUI

struct PodcastShowView: View {
    @StateObject var viewModel: PodcastViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.98, blue: 0.94)
                .ignoresSafeArea()

            backgroundDecoration

            if viewModel.isLoading && viewModel.episodes.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else if viewModel.episodes.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.episodes) { episode in
                            episodeCard(for: episode)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await viewModel.fetchEpisodesAsync(forceRefresh: true)
                }
            }
        }
        .navigationTitle(
            viewModel.shows.count == 1
                ? viewModel.shows.first?.name ?? "Videos"
                : "Meine Videos"
        )
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.fetchEpisodes() }
    }

    // MARK: - Episode Card

    private func episodeCard(for episode: SpotifyEpisode) -> some View {
        let isPlaying = playerViewModel.currentTrackURI == episode.uri
            && playerViewModel.isPlaying

        return HStack(spacing: 20) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = episode.imageURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            episodePlaceholder
                        }
                    } else {
                        episodePlaceholder
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(
                    color: Color.green.opacity(isPlaying ? 0.4 : 0.12),
                    radius: isPlaying ? 14 : 6,
                    x: 0,
                    y: 4
                )

                if isPlaying {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.15, green: 0.75, blue: 0.45))
                            .frame(width: 30, height: 30)
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: 4)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(episode.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(
                        isPlaying
                            ? Color(red: 0.1, green: 0.6, blue: 0.35)
                            : Color(red: 0.1, green: 0.15, blue: 0.12)
                    )
                    .lineLimit(2)

                if !episode.description.isEmpty {
                    Text(episode.description)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color(red: 0.4, green: 0.5, blue: 0.44))
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    // Dauer
                    Label(formatDuration(episode.duration), systemImage: "clock")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.6, blue: 0.52))

                    // Datum
                    if let date = episode.releaseDate {
                        Text(date, style: .date)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.61))
                    }
                }
            }

            Spacer()

            // Play Button
            ZStack {
                Circle()
                    .fill(
                        isPlaying
                            ? Color(red: 0.15, green: 0.75, blue: 0.45)
                            : Color(red: 0.15, green: 0.75, blue: 0.45).opacity(0.15)
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(
                        isPlaying
                            ? .white
                            : Color(red: 0.15, green: 0.75, blue: 0.45)
                    )
                    .offset(x: isPlaying ? 0 : 2)
            }
            .shadow(
                color: Color.green.opacity(isPlaying ? 0.35 : 0.0),
                radius: 8,
                x: 0,
                y: 3
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.8))
                .shadow(
                    color: Color.green.opacity(isPlaying ? 0.15 : 0.06),
                    radius: isPlaying ? 16 : 8,
                    x: 0,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isPlaying
                        ? Color(red: 0.15, green: 0.75, blue: 0.45).opacity(0.3)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
        .onDebouncedTap {
            playerViewModel.play(uri: episode.uri, isLongForm: true)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPlaying)
    }

    private var episodePlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.green.opacity(0.15))
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green.opacity(0.5))
            )
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(red: 0.15, green: 0.75, blue: 0.45))
            Text("Lädt Episoden…")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.4, green: 0.55, blue: 0.44))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundColor(.green.opacity(0.4))
            Text("Keine Episoden gefunden")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.4, green: 0.55, blue: 0.44))
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Hoppla!")
                .font(.system(size: 28, weight: .heavy, design: .rounded))

            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Button("Nochmal versuchen") {
                viewModel.fetchEpisodes()
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color(red: 0.15, green: 0.75, blue: 0.45)))
            .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 4)
        }
    }

    private var backgroundDecoration: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.07))
                .frame(width: 320, height: 320)
                .offset(x: 180, y: -160)

            Circle()
                .fill(Color.green.opacity(0.05))
                .frame(width: 220, height: 220)
                .offset(x: -160, y: 320)
        }
        .ignoresSafeArea()
    }
}
