// Modifiers Group
import SwiftUI

/// A reusable SwiftUI ViewModifier to debounce tap gestures.
/// This prevents bugs caused by a child rapidly tapping the same item multiple times.
struct DebounceModifier: ViewModifier {
    let debounceTime: TimeInterval
    let action: () -> Void
    
    // Tracks the last time the action was executed. 
    // Initialized to the distant past so the very first tap always works.
    @State private var lastTapTime: Date = .distantPast
    
    func body(content: Content) -> some View {
        content
            // contentShape ensures the whole visual area is tappable, not just the visible pixels
            .contentShape(Rectangle()) 
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) >= debounceTime {
                    lastTapTime = now
                    action()
                }
            }
    }
}

extension View {
    /// Applies a debounced tap gesture to the view.
    /// - Parameters:
    ///   - debounceTime: The minimum time between allowed taps (defaults to 0.5 seconds).
    ///   - action: The action to perform when tapped.
    func onDebouncedTap(debounceTime: TimeInterval = 0.5, perform action: @escaping () -> Void) -> some View {
        self.modifier(DebounceModifier(debounceTime: debounceTime, action: action))
    }
}

/// A custom Button that automatically debounces its action.
/// This preserves standard button visual states (like dimming when pressed) while protecting against rapid taps.
struct DebouncedButton<Label: View>: View {
    var debounceTime: TimeInterval = 0.5
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    
    var body: some View {
        Button(action: {
            // The actual debouncing is handled transparently 
        }) {
            label()
        }
        .buttonStyle(DebouncedButtonStyle(debounceTime: debounceTime, action: action))
    }
}

/// A primitive button style that handles the debouncing state for `DebouncedButton`
fileprivate struct DebouncedButtonStyle: PrimitiveButtonStyle {
    let debounceTime: TimeInterval
    let action: () -> Void
    
    @State private var lastTapTime: Date = .distantPast
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) >= debounceTime {
                    lastTapTime = now
                    action()
                }
            }
            // We use opacity to simulate the standard button press effect manually
            // since PrimitiveButtonStyle overrides the default system behavior.
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}