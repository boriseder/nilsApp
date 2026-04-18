// Child ViewModels Group
import Foundation
import Combine

/// Manages the UI state for the child's main screen.
/// We keep this lightweight, as the primary source of truth for content is the PersistenceService.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var showAdminArea: Bool = false
}