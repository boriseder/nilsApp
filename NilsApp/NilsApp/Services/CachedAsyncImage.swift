//
//  CachedAsyncImage.swift
//  NilsApp
//
//  Created by Boris Eder on 03.05.26.
//


// Views/Shared Group
import SwiftUI

/// A drop-in replacement for `AsyncImage` that routes through `ImageCache`.
///
/// Usage — matches the two `AsyncImage` call-site patterns used in NilsApp:
///
/// 1. Image + placeholder:
///    ```swift
///    CachedAsyncImage(url: track.imageURL) { image in
///        image.resizable().aspectRatio(contentMode: .fill)
///    } placeholder: {
///        Color.purple.opacity(0.15)
///    }
///    ```
///
/// 2. Phase-based (if you ever need it):
///    ```swift
///    CachedAsyncImage(url: url) { phase in
///        switch phase { ... }
///    }
///    ```
///
/// The view is generic over `Content` and `Placeholder`, identical to SwiftUI's
/// own `AsyncImage` signature, so existing call sites require only a find-replace
/// of `AsyncImage` → `CachedAsyncImage`.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {

    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var uiImage: UIImage? = nil
    @State private var task: Task<Void, Never>? = nil

    // MARK: - Init

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url         = url
        self.content     = content
        self.placeholder = placeholder
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear  { load() }
        .onDisappear { task?.cancel() }
        .onChange(of: url) { _, _ in
            uiImage = nil
            task?.cancel()
            load()
        }
    }

    // MARK: - Private

    private func load() {
        guard let url, uiImage == nil else { return }
        task = Task {
            let fetched = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { uiImage = fetched }
        }
    }
}

// MARK: - Convenience: nil-URL overload

extension CachedAsyncImage {
    /// Initialiser that accepts an optional URL directly (matches the most common
    /// call-site pattern in the app where `imageURL` is already `URL?`).
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        _: Void = ()   // disambiguator — not needed but kept for clarity
    ) {
        self.init(url: url, content: content, placeholder: placeholder)
    }
}