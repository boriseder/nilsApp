// Services Group
import Foundation
import Combine
import os

/// Service responsible for saving and loading the parent's curated content
/// to and from the device's local filesystem.
@MainActor
final class PersistenceService: ObservableObject {
    
    /// The current state of the curated content. 
    /// ViewModels can observe this to react to changes made in the Admin UI.
    @Published private(set) var curatedContent: CuratedContent
    
    private let fileName = "curated_content.json"
    private let logger = Logger(subsystem: "com.nilsapp", category: "PersistenceService")
    
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(fileName)
    }
    
    init() {
        // Initialize with empty content first to satisfy Swift initialization rules
        self.curatedContent = .empty
        // Then attempt to load saved data from disk
        load()
    }
    
    /// Loads the curated content from the local JSON file.
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decodedContent = try JSONDecoder().decode(CuratedContent.self, from: data)
            self.curatedContent = decodedContent
            logger.info("Successfully loaded curated content from disk.")
        } catch {
            // It's normal for this to fail on the very first launch before the parent has saved anything.
            logger.warning("Could not load curated content (expected on first launch): \(error.localizedDescription)")
            self.curatedContent = .empty
        }
    }
    
    /// Saves the provided curated content to the local JSON file and updates the published state.
    func save(_ content: CuratedContent) {
        do {
            let encodedData = try JSONEncoder().encode(content)
            try encodedData.write(to: fileURL, options: [.atomic, .completeFileProtection])
            self.curatedContent = content
            logger.info("Successfully saved curated content to disk.")
        } catch {
            logger.error("Failed to save curated content: \(error.localizedDescription)")
        }
    }
}