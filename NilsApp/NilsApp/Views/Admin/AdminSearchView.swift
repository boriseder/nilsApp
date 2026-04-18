// Admin Views Group
import SwiftUI

/// A sheet presented in the Admin area to search for content on Spotify
/// and add it to the curated Walled Garden.
struct AdminSearchView: View {
    @EnvironmentObject var viewModel: AdminViewModel
    let category: SearchCategory
    
    @State private var searchQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Searching Spotify...")
                        Spacer()
                    }
                } else if let error = viewModel.searchErrorMessage {
                    Text(error)
                        .foregroundColor(.red)
                } else {
                    searchResults
                }
            }
            .searchable(text: $searchQuery, prompt: searchPrompt)
            .onSubmit(of: .search) {
                viewModel.performSearch(query: searchQuery, category: category) // Call the new generic search method
            }
            .navigationTitle(titleForCategory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                viewModel.clearSearch()
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var searchResults: some View {
        switch category {
        case .audiobooks:
            ForEach(viewModel.audiobookSearchResults) { artist in
                Button(action: { viewModel.addAudiobookSeries(artist); dismiss() }) {
                    Label(artist.name, systemImage: "person.circle")
                }
            }
        case .music:
            ForEach(viewModel.musicSearchResults) { playlist in
                Button(action: { viewModel.addMusicPlaylist(playlist); dismiss() }) {
                    Label(playlist.name, systemImage: "music.note.list")
                }
            }
        case .podcasts:
            ForEach(viewModel.podcastSearchResults) { show in
                Button(action: { viewModel.addPodcastShow(show); dismiss() }) {
                    Label(show.name, systemImage: "mic.circle")
                }
            }
        }
    }
    
    private var titleForCategory: String {
        switch category {
        case .audiobooks: return "Search Meine Hörbücher"
        case .music: return "Search Meine Playlists"
        case .podcasts: return "Search Meine Videos"
        }
    }
    
    private var searchPrompt: String {
        switch category {
        case .audiobooks: return "e.g., Pumuckl, TKKG"
        case .music: return "e.g., Calm Music, Kids Dance"
        case .podcasts: return "e.g., Science Kids"
        }
    }
}