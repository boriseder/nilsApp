//
//  MusicPlaylistSelectionView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A view that displays a grid of curated music playlists for the child to choose from.
struct MusicPlaylistSelectionView: View {
    let playlists: [CuratedPlaylist]
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            MusicPlaylistView(viewModel: PlaylistViewModel(playlists: [playlist], apiService: spotifyAPIService))
                        } label: {
                            ItemTile(
                                title: playlist.name,
                                imageURL: playlist.imageURL,
                                placeholderIcon: "music.note.list",
                                accentColor: .purple
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(32)
            }
        }
        .navigationTitle("Meine Playlists")
    }
}