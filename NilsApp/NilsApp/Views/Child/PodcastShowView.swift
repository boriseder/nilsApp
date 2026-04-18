//
//  PodcastShowView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// Displays a list of episodes for a selected podcast show.
struct PodcastShowView: View {
    @StateObject var viewModel: PodcastViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.episodes.isEmpty {
                ProgressView("Loading episodes...")
                    .scaleEffect(1.5)
                    .font(.title)
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else if viewModel.episodes.isEmpty {
                emptyStateView(message: "No episodes found for this show.")
            }
            else {
                List {
                    ForEach(viewModel.episodes) { episode in
                        episodeRow(for: episode)
                    }
                }
                .listStyle(.plain) // Use plain list style for a cleaner look
            }
        }
        .navigationTitle(viewModel.show.name)
        .onAppear {
            viewModel.fetchEpisodes()
        }
    }
    
    // MARK: - Subviews
    
    private func episodeRow(for episode: SpotifyEpisode) -> some View {
        HStack {
            if let imageURL = episode.imageURL {
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
                Text(episode.name)
                    .font(.title2)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(episode.description)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            
            Spacer()
            
            Text(formatDuration(episode.duration))
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .onDebouncedTap {
            // Podcast episodes are long-form, so we tell the player to look for a cached position.
            playerViewModel.play(uri: episode.uri, isLongForm: true)
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
            Button("Try Again") { viewModel.fetchEpisodes() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
    
    private func emptyStateView(message: String) -> some View {
        Text(message).font(.title).foregroundColor(.secondary)
    }
}

// Helper function for formatting duration, moved here for reuse across views
func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
}
