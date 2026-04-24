//
//  MusicPlaylistView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// Displays a list of tracks for a selected music playlist.
struct MusicPlaylistView: View {
    @StateObject var viewModel: PlaylistViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan.opacity(0.2), .mint.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.tracks.isEmpty {
                ProgressView("Loading music...")
                    .scaleEffect(1.5)
                    .font(.title)
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else if viewModel.tracks.isEmpty {
                emptyStateView(message: "No music found in this playlist.")
            } else {
                List {
                    ForEach(viewModel.tracks) { track in
                        trackRow(for: track)
                    }
                }
                .listStyle(.plain) // Use plain list style for a cleaner look
                .scrollContentBackground(.hidden) // Let the gradient show through
            }
        }
        .navigationTitle(viewModel.playlists.count == 1 ? viewModel.playlists.first?.name ?? "Meine Playlists" : "Meine Playlists")
        .onAppear {
            viewModel.fetchTracks()
        }
    }
    
    // MARK: - Subviews
    
    private func trackRow(for track: SpotifyTrack) -> some View {
        HStack {
            if let imageURL = track.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
            }
            
            VStack(alignment: .leading) {
                Text(track.name)
                    .font(.title2)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(track.artistName)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            
            Spacer()
            
            Text(formatDuration(track.duration))
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .onDebouncedTap {
            // Music tracks are typically short-form, so no position caching is needed.
            playerViewModel.play(uri: track.uri, isLongForm: false)
        }
    }
    
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Text(message)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") { viewModel.fetchTracks() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
    
    private func emptyStateView(message: String) -> some View {
        Text(message).font(.title).foregroundColor(.secondary)
    }
}