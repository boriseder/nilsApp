//
//  AudiobookSeriesSelectionView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A view that displays a grid of curated audiobook series for the child to choose from.
struct AudiobookSeriesSelectionView: View {
    let artists: [CuratedArtist]
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService

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
                    ForEach(artists) { artist in
                        NavigationLink {
                            AudiobookGridView(viewModel: AudiobookGridViewModel(artists: [artist], apiService: spotifyAPIService))
                        } label: {
                            ItemTile(
                                title: artist.name,
                                imageURL: artist.imageURL,
                                placeholderIcon: "person.fill",
                                accentColor: .orange
                            )
                        }
                        .buttonStyle(.plain) // Removes the default blue tint from the text
                    }
                }
                .padding(40)
            }
        }
        .navigationTitle("Meine Hörbücher")
    }
}