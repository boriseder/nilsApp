//
//  DurationFormatter.swift
//  NilsApp
//
//  Created by Boris Eder on 25.04.26.
//


// Helpers Group
import Foundation

/// Globale Hilfsfunktion zum Formatieren von Zeitdauern.
/// Verfügbar in allen Views ohne Import.
func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}