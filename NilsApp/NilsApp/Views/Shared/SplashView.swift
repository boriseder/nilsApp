//
//  SplashView.swift
//  nilsApp
//
//  Created by Boris on 18/04/2026.
//

import SwiftUI

/// A kid-friendly animated splash screen that appears before the main Walled Garden loads.
struct SplashView: View {
    @State private var isAnimatingIcon = false
    @State private var isTextVisible = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan.opacity(0.2), .mint.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 140))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .scaleEffect(isAnimatingIcon ? 1.05 : 0.95)
                
                Text("NilsApp")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .opacity(isTextVisible ? 1.0 : 0.0)
                    .offset(y: isTextVisible ? 0 : 20)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).repeatForever(autoreverses: true)) {
                isAnimatingIcon = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                isTextVisible = true
            }
        }
    }
}