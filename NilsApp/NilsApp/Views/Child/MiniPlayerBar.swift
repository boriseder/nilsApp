//
//  MiniPlayerBar.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A compact player bar displayed at the bottom of the HomeView when content is playing.
/// Tapping it presents the full NowPlayingView.
struct MiniPlayerBar: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Binding var showNowPlayingSheet: Bool

    var body: some View {
        HStack {
            // Album Art
            if let imageURL = playerViewModel.trackImageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading) {
                Text(playerViewModel.trackName ?? "Unknown Track")
                    .font(.headline)
                    .lineLimit(1)
                Text(playerViewModel.artistName ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 8)

            Spacer()

            DebouncedButton(action: {
                if playerViewModel.isPlaying {
                    playerViewModel.pause()
                } else {
                    playerViewModel.resume()
                }
            }) {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial) // Uses a subtle translucent background
        .cornerRadius(16)
        .padding(.horizontal)
        .onDebouncedTap {
            showNowPlayingSheet = true // Present the full NowPlayingView
        }
    }
}