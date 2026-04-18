// Child Views Group
import SwiftUI

/// Displays a visual, scrollable grid of albums for a selected audiobook series.
struct AudiobookGridView: View {
    @StateObject var viewModel: AudiobookGridViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    
    // Defines a flexible grid that adapts well to landscape orientations
    let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.albums.isEmpty {
                ProgressView("Loading stories...")
                    .scaleEffect(1.5)
                    .font(.title)
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.albums) { album in
                            albumCard(for: album)
                        }
                    }
                    .padding(32)
                }
            }
        }
        .navigationTitle(viewModel.artists.count == 1 ? viewModel.artists.first?.name ?? "Meine Hörbücher" : "Meine Hörbücher")
        .onAppear {
            viewModel.fetchAlbums()
        }
    }
    
    // MARK: - Subviews
    
    private func albumCard(for album: SpotifyAlbum) -> some View {
        VStack(spacing: 16) {
            // Placeholder for actual AsyncImage once we have real URLs
            Group {
                if let imageURL = album.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(24)
                    } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(24)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.orange.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.orange)
                    }
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            Text(album.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        // The crucial debounced tap to prevent the child from rapidly firing 10 play commands
        .onDebouncedTap {
            // Audiobooks are long-form, so we tell the player to look for a cached position
            playerViewModel.play(uri: album.uri, isLongForm: true)
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
            
            Button("Try Again") {
                viewModel.fetchAlbums()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}