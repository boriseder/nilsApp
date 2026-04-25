import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Binding var showNowPlayingSheet: Bool

    // Scrubber drag state — mirrors NowPlayingView pattern from the fix-4 change
    @State private var isDragging: Bool = false
    @State private var dragValue: TimeInterval = 0
    @State private var scrubDebounceTask: Task<Void, Never>?

    // Upward-swipe lift state
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // ── Interactive scrubber ──────────────────────────────────────────
            scrubberRow

            // ── Main row: art · info · controls ──────────────────────────────
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
        // simultaneousGesture prevents the DragGesture from swallowing taps (fix #5)
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

    private var scrubberRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                // Filled portion
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isDragging ? 1.0 : 0.75))
                    .frame(
                        width: filledWidth(in: geo.size.width),
                        height: 4
                    )
                    .animation(
                        isDragging ? nil : .linear(duration: 1),
                        value: playerViewModel.currentProgress
                    )

                // Thumb — only visible while dragging
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

            if playerViewModel.trackDuration > 0 {
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

    private var controls: some View {
        HStack(spacing: 8) {
            DebouncedButton(action: { playerViewModel.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }

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
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                    Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .offset(x: playerViewModel.isPlaying ? 0 : 1.5)
                }
            }

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
