// KOMPLETT — AudiobookSeriesSelectionView.swift
import SwiftUI

struct AudiobookSeriesSelectionView: View {
    let artists: [CuratedArtist]
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
                    ForEach(artists) { artist in
                        NavigationLink {
                            // Immer nur den gewählten Artist — nie das ganze Array
                            AudiobookGridView(viewModel: {
                                let vm = AudiobookGridViewModel()
                                vm.configure(
                                    artists: [artist],  // ← explizit nur dieser eine Artist
                                    apiService: spotifyAPIService,
                                    persistenceService: persistenceService
                                )
                                return vm
                            }())
                        } label: {
                            ItemTile(
                                title: artist.name,
                                imageURL: artist.imageURL,
                                placeholderIcon: "person.fill",
                                accentColor: .orange
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(40)
            }
        }
        .navigationTitle("Meine Hörbücher")
    }
}
