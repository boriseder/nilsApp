//
//  PodcastShowSelectionView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A view that displays a grid of curated podcast shows for the child to choose from.
struct PodcastShowSelectionView: View {
    let shows: [CuratedShow]
    @EnvironmentObject private var spotifyAPIService: SpotifyAPIService

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(shows) { show in
                        NavigationLink {
                            PodcastShowView(viewModel: PodcastViewModel(shows: [show], apiService: spotifyAPIService))
                        } label: {
                            ItemTile(
                                title: show.name,
                                imageURL: show.imageURL,
                                placeholderIcon: "mic.fill",
                                accentColor: .green
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(32)
            }
        }
        .navigationTitle("Podcasts")
    }
}