// Views/Shared Group
import SwiftUI

/// The full-screen "Now Playing" view, presented as a sheet.
/// Shows album art, track info, a scrubber, and playback controls.
/// The scrubber doubles as a position resumption tool for audiobooks/podcasts.
struct NowPlayingView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    // FIX 4: Local drag state so the slider feels responsive without hammering
    // the Spotify SDK with a seek call on every frame of a drag gesture.
    @State private var isDragging: Bool = false
    @State private var dragValue: TimeInterval = 0
    @State private var scrubDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            if playerViewModel.hasPauseTimeoutOccurred {
                // SDK timed out after ~30s pause — show reconnect affordance
                reconnectView
            } else {
                mainPlayerContent
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
        .background(Color(.systemBackground))
    }

    // MARK: - Main Player

    private var mainPlayerContent: some View {
        VStack(spacing: 28) {
            // Album Art
            albumArtView
                .frame(maxWidth: 360, maxHeight: 360)

            // Track Info
            VStack(spacing: 6) {
                Text(playerViewModel.trackName ?? "Nothing Playing")
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(playerViewModel.artistName ?? "")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Scrubber — essential for audiobooks & podcasts
            scrubberView

            // Controls
            playbackControls
        }
    }

    // MARK: - Album Art

    private var albumArtView: some View {
        Group {
            if let url = playerViewModel.trackImageURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                } placeholder: {
                    artPlaceholder
                }
            } else {
                artPlaceholder
            }
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.secondary.opacity(0.2))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Scrubber

    private var scrubberView: some View {
        VStack(spacing: 6) {
            // FIX 4: Use local drag state so the slider thumb tracks the finger immediately,
            // but the actual SDK seek is debounced — only fired 150ms after the user stops
            // moving. This prevents flooding the Spotify App Remote with dozens of IPC calls
            // per second during a fast scrub, which could cause disconnects.
            Slider(
                value: Binding(
                    get: {
                        isDragging ? dragValue : playerViewModel.currentProgress
                    },
                    set: { newValue in
                        isDragging = true
                        dragValue = newValue

                        // Debounce: cancel the previous pending seek and schedule a new one.
                        scrubDebounceTask?.cancel()
                        scrubDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                playerViewModel.scrub(to: newValue)
                                isDragging = false
                            }
                        }
                    }
                ),
                in: 0...max(playerViewModel.trackDuration, 1)
            )
            .accentColor(.primary)

            HStack {
                Text(formatTime(isDragging ? dragValue : playerViewModel.currentProgress))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(playerViewModel.trackDuration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 52) {
            // Previous
            DebouncedButton(action: { playerViewModel.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.primary)
            }

            // Play / Pause — largest button, most important for a child
            DebouncedButton(action: {
                if playerViewModel.isPlaying {
                    playerViewModel.pause()
                } else {
                    playerViewModel.resume()
                }
            }) {
                Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primary)
            }

            // Next
            DebouncedButton(action: { playerViewModel.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Reconnect View

    /// Shown when the SDK disconnects after ~30s pause timeout.
    private var reconnectView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "pause.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("Music Paused")
                .font(.title)
                .fontWeight(.bold)

            Text("Tap to resume where you left off.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            DebouncedButton(action: { playerViewModel.resume() }) {
                Text("Tap to Resume")
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: 280)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
