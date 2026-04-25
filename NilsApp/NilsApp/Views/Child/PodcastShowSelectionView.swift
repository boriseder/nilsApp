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
                    ForEach(shows) { show in
                        NavigationLink {
                            PodcastShowView(
                                viewModel: PodcastViewModel(
                                    shows: [show],
                                    apiService: spotifyAPIService,
                                    persistenceService: persistenceService
                                )
                            )
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
                .padding(40)
            }
        }
        .navigationTitle("Meine Videos")
    }
}



