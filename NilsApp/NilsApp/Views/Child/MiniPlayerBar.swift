// Views/Child Group
import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Binding var showNowPlayingSheet: Bool

    // Scrubber drag state
    @State private var isDragging: Bool = false
    @State private var dragValue: TimeInterval = 0
    @State private var scrubDebounceTask: Task<Void, Never>?

    // Upward-swipe lift state
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            scrubberRow
            HStack(spacing: 14) {
                albumArt
                trackInfo
                Spacer()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(playerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(y: dragOffset)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
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

    // MARK: - Scrubber
    //
    // Hidden while a timeout has occurred — scrubbing is meaningless without a
    // live SDK connection, and the reconnect banner takes visual priority.

    private var scrubberRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isDragging ? 1.0 : 0.75))
                    .frame(width: filledWidth(in: geo.size.width), height: 4)
                    .animation(isDragging ? nil : .linear(duration: 1),
                               value: playerViewModel.currentProgress)

                if isDragging {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, filledWidth(in: geo.size.width) - 7))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Do not allow scrubbing when disconnected.
                        guard !playerViewModel.hasPauseTimeoutOccurred else { return }
                        isDragging = true
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        dragValue = fraction * max(playerViewModel.trackDuration, 1)

                        scrubDebounceTask?.cancel()
                        scrubDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                playerViewModel.scrub(to: dragValue)
                            }
                        }
                    }
                    .onEnded { value in
                        guard !playerViewModel.hasPauseTimeoutOccurred else { return }
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        let position = fraction * max(playerViewModel.trackDuration, 1)
                        scrubDebounceTask?.cancel()
                        playerViewModel.scrub(to: position)
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 4)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        // Fade the scrubber out while disconnected so attention goes to the banner.
        .opacity(playerViewModel.hasPauseTimeoutOccurred ? 0.3 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: playerViewModel.hasPauseTimeoutOccurred)
    }

    private func filledWidth(in totalWidth: CGFloat) -> CGFloat {
        let duration = max(playerViewModel.trackDuration, 1)
        let progress = isDragging ? dragValue : playerViewModel.currentProgress
        return totalWidth * CGFloat(max(0, min(1, progress / duration)))
    }

    // MARK: - Album Art

    private var albumArt: some View {
        Group {
            if let url = playerViewModel.trackImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
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
        // Dim album art when disconnected to reinforce the "paused/offline" state.
        .opacity(playerViewModel.hasPauseTimeoutOccurred ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: playerViewModel.hasPauseTimeoutOccurred)
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
    //
    // When a timeout has occurred, a small "Tap to reconnect" label replaces the
    // time-remaining readout so the child has an obvious affordance.

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playerViewModel.trackName ?? "Nichts läuft")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            if playerViewModel.hasPauseTimeoutOccurred {
                // Reconnect hint — tapping the bar opens NowPlayingView which
                // shows the full reconnect affordance with a large "Tap to Resume"
                // button. This label tells the child where to tap.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text("Antippen um fortzufahren")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            } else if playerViewModel.trackDuration > 0 {
                let remaining = max(0, playerViewModel.trackDuration - (isDragging ? dragValue : playerViewModel.currentProgress))
                Text("-\(formatTime(remaining))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            } else {
                Text(playerViewModel.artistName ?? "")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Controls
    //
    // The centre button adapts to three states:
    //
    //   • hasPauseTimeoutOccurred == true
    //     → Reconnect icon (arrow.clockwise). Tapping calls resume(), which now
    //       sets pendingResume = true and reconnects the SDK before playing.
    //       The icon is amber/warm so it reads as "action needed" at a glance.
    //
    //   • isPlaying == true
    //     → Standard pause icon.
    //
    //   • isPlaying == false (normal pause, SDK still connected)
    //     → Standard play icon.

    private var controls: some View {
        HStack(spacing: 8) {
            DebouncedButton(action: { playerViewModel.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(playerViewModel.hasPauseTimeoutOccurred ? 0.3 : 0.85))
                    .frame(width: 36, height: 36)
            }
            .disabled(playerViewModel.hasPauseTimeoutOccurred)

            // Centre button — reconnect / pause / play
            DebouncedButton(action: {
                if playerViewModel.hasPauseTimeoutOccurred {
                    // resume() in SpotifySDKService sets pendingResume and calls connect()
                    playerViewModel.resume()
                } else if playerViewModel.isPlaying {
                    playerViewModel.pause()
                } else {
                    playerViewModel.resume()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(playerViewModel.hasPauseTimeoutOccurred
                              ? Color(red: 1.0, green: 0.75, blue: 0.2) // amber — signals action needed
                              : Color.white)
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                    centreButtonIcon
                }
            }

            DebouncedButton(action: { playerViewModel.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(playerViewModel.hasPauseTimeoutOccurred ? 0.3 : 0.85))
                    .frame(width: 36, height: 36)
            }
            .disabled(playerViewModel.hasPauseTimeoutOccurred)
        }
    }

    /// The icon inside the centre button, isolated so the animation target is minimal.
    @ViewBuilder
    private var centreButtonIcon: some View {
        if playerViewModel.hasPauseTimeoutOccurred {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
        } else {
            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
                .offset(x: playerViewModel.isPlaying ? 0 : 1.5)
        }
    }

    // MARK: - Background

    private var playerBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.55))

            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.35),
                            Color.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, Int(time))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
