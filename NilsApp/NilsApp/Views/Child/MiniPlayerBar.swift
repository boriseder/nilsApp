import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Binding var showNowPlayingSheet: Bool

    // Lokaler Drag-State für Swipe-to-Dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar — ganz oben, keine Padding
            progressBar

            HStack(spacing: 14) {
                // Album Art
                albumArt

                // Track Info
                trackInfo

                Spacer()

                // Controls
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(playerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Nur nach oben wischen erlauben (zum Öffnen)
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height * 0.3
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        showNowPlayingSheet = true
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
        )
        .onDebouncedTap {
            showNowPlayingSheet = true
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 3)

                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(
                        width: playerViewModel.trackDuration > 0
                            ? geo.size.width * CGFloat(playerViewModel.currentProgress / playerViewModel.trackDuration)
                            : 0,
                        height: 3
                    )
                    .animation(.linear(duration: 1), value: playerViewModel.currentProgress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Album Art

    private var albumArt: some View {
        Group {
            if let url = playerViewModel.trackImageURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    artPlaceholder
                }
            } else {
                artPlaceholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.2))
            .overlay(
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            )
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playerViewModel.trackName ?? "Nichts läuft")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(playerViewModel.artistName ?? "")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 8) {
            // Previous — etwas kleiner, weniger wichtig für Kinder
            DebouncedButton(action: { playerViewModel.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }

            // Play/Pause — größter Button
            DebouncedButton(action: {
                if playerViewModel.isPlaying {
                    playerViewModel.pause()
                } else {
                    playerViewModel.resume()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                    Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        // Play-Icon braucht minimales Offset wegen optischer Mitte
                        .offset(x: playerViewModel.isPlaying ? 0 : 1.5)
                }
            }

            // Next
            DebouncedButton(action: { playerViewModel.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
        }
    }

    // MARK: - Background

    private var playerBackground: some View {
        ZStack {
            // Basis — dunkles Glas
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.75))

            // Subtiler Farbakzent basierend auf Accent-Color
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.4),
                            Color.accentColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Glassmorphism-Schimmer
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}
