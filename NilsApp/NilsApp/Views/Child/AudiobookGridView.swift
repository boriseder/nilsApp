// Child Views Group
import SwiftUI

/// Displays a visual, scrollable grid of albums for a selected audiobook series.
struct AudiobookGridView: View {
    @StateObject var viewModel: AudiobookGridViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    
    // Defines a flexible grid that adapts well to landscape orientations
    let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 40)
    ]
    
    var body: some View {
        ZStack {
            // A friendly, kid-appealing background gradient
            LinearGradient(
                colors: [.cyan.opacity(0.2), .mint.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.albums.isEmpty {
                ProgressView("Loading stories...")
                    .scaleEffect(1.5)
                    .font(.title)
            } else if let error = viewModel.errorMessage {
                errorStateView(message: error)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.albums) { album in
                            albumCard(for: album)
                        }
                    }
                    .padding(40)
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
                            .cornerRadius(32)
                    } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(32)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32)
                            .fill(Color.orange.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.orange)
                    }
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
            
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