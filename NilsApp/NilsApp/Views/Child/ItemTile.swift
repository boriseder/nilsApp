//
//  ItemTile.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A reusable tile for displaying a curated item (artist, playlist, or show) in a grid.
struct ItemTile: View {
    let title: String
    let imageURL: URL?
    let placeholderIcon: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(24)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(accentColor.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 64))
                        .foregroundColor(accentColor)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            Text(title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
    }
}