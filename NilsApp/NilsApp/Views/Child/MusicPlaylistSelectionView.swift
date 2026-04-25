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
    @EnvironmentObject private var persistenceService: PersistenceService

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 40)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan.opacity(0.2), .mint.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            MusicPlaylistView(viewModel: {
                                let vm = PlaylistViewModel()
                                vm.configure(
                                    playlists: [playlist],
                                    apiService: spotifyAPIService,
                                    persistenceService: persistenceService
                                )
                                return vm
                            }())
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
                .padding(40)
            }
        }
        .navigationTitle("Meine Playlists")
    }
}
