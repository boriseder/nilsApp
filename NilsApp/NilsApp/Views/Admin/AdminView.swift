// Admin Views Group
import SwiftUI

/// The main interface for the parent to manage the Walled Garden content.
/// Secured by the PINEntryView. Prioritizes standard, functional OOTB UI.
struct AdminView: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss // For dismissing the sheet
    // We inject the persistence service directly to observe the curated content updates
    @EnvironmentObject var persistenceService: PersistenceService
    
    @State private var showingSearchSheet = false
    @State private var searchCategory: SearchCategory = .audiobooks
    
    var body: some View {
        NavigationStack {
            if !viewModel.isUnlocked {
                PINEntryView(viewModel: viewModel) // PINEntryView will handle its own dismissal
            } else {
                List {
                    audiobooksSection
                    musicSection
                    podcastsSection
                }
                .navigationTitle("Admin Area")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Lock button also dismisses the sheet
                        Button("Lock") {
                            viewModel.lock()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .sheet(isPresented: $showingSearchSheet) {
                    AdminSearchView(category: searchCategory)
                        .environmentObject(viewModel)
                }
            }
        } // End of NavigationStack
    }
    
    // MARK: - List Sections
    
    private var audiobooksSection: some View {
        Section(header: Text("Audiobook Series")) {
            ForEach(persistenceService.curatedContent.audiobookSeries) { artist in
                Text(artist.name)
            }
            .onDelete(perform: viewModel.removeAudiobookSeries)
            
            Button(action: {
                searchCategory = .audiobooks
                showingSearchSheet = true
            }) {
                Label("Add Audiobook Series...", systemImage: "plus")
            }
        }
    }
    
    private var musicSection: some View {
        Section(header: Text("Music Playlists")) {
            ForEach(persistenceService.curatedContent.musicPlaylists) { playlist in
                Text(playlist.name)
            }
            .onDelete(perform: viewModel.removeMusicPlaylist)
            
            Button(action: {
                searchCategory = .music
                showingSearchSheet = true
            }) {
                Label("Add Music Playlist...", systemImage: "plus")
            }
        }
    }
    
    private var podcastsSection: some View {
        Section(header: Text("Podcasts")) {
            ForEach(persistenceService.curatedContent.podcastShows) { show in
                Text(show.name)
            }
            .onDelete(perform: viewModel.removePodcastShow)
            
            Button(action: {
                searchCategory = .podcasts
                showingSearchSheet = true
            }) {
                Label("Add Podcast...", systemImage: "plus")
            }
        }
    }
}