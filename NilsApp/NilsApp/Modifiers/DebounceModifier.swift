// Modifiers Group
import SwiftUI

/// A reusable SwiftUI ViewModifier to debounce tap gestures.
/// This prevents bugs caused by a child rapidly tapping the same item multiple times.
struct DebounceModifier: ViewModifier {
    let debounceTime: TimeInterval
    let action: () -> Void

    @State private var lastTapTime: Date = .distantPast

    func body(content: Content) -> some View {
        content
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
    func onDebouncedTap(debounceTime: TimeInterval = 0.5, perform action: @escaping () -> Void) -> some View {
        self.modifier(DebounceModifier(debounceTime: debounceTime, action: action))
    }
}

/// A custom Button that automatically debounces its action.
/// Implemented as a plain View wrapping a Button so we keep the standard
/// system button appearance (highlight on press) without needing PrimitiveButtonStyle.
struct DebouncedButton<Label: View>: View {
    var debounceTime: TimeInterval = 0.5
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        Button {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) >= debounceTime {
                lastTapTime = now
                action()
            }
        } label: {
            label()
        }
    }
}

/// A button style for use with `.buttonStyle(DebouncedButtonStyle())`.
/// Uses a DragGesture to track press state since PrimitiveButtonStyleConfiguration
/// does NOT expose `isPressed` — that property only exists on ButtonStyleConfiguration.
struct DebouncedButtonStyle: PrimitiveButtonStyle {
    var debounceTime: TimeInterval = 0.5

    @State private var lastTapTime: Date = .distantPast
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isPressed ? 0.7 : 1.0)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded   { _ in isPressed = false }
            )
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) >= debounceTime {
                    lastTapTime = now
                    configuration.trigger()
                }
            }
    }
}
