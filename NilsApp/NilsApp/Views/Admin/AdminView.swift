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
            // PIN-Check ist jetzt in PINEntryView — hier nur noch den
            // eigentlichen Admin-Content zeigen (isUnlocked ist garantiert true
            // wenn wir hier ankommen)
            List {
                spotifyAccountSection
                audiobooksSection
                musicSection
                podcastsSection
            }
            .navigationTitle("Admin-Bereich")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sperren") {
                        viewModel.lock()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                }
            }
            .sheet(isPresented: $showingSearchSheet) {
                AdminSearchView(category: searchCategory)
                    .environmentObject(viewModel)
            }
        }
    }
    
    // MARK: - List Sections
    
    private var spotifyAccountSection: some View {
        Section(header: Text("Spotify Account Status")) {
            HStack {
                Text("Logged In:")
                Spacer()
                Image(systemName: viewModel.spotifyAPIService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(viewModel.spotifyAPIService.isAuthorized ? .green : .red)
            }
            
            if viewModel.spotifyAPIService.requiresReauthentication {
                Text("Reauthentication required. Please log in again.")
                    .foregroundColor(.red)
            }
            
            Button("Log In / Reauthorize Spotify") {
                viewModel.loginToSpotify()
            }
        }
    }
    
    private var audiobooksSection: some View {
        Section(header: Text("Meine Hörbücher")) {
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
        Section(header: Text("Meine Playlists")) {
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
        Section(header: Text("Meine Videos")) {
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
