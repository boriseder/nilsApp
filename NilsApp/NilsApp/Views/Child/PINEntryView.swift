// Admin Views Group
import SwiftUI

struct PINEntryView: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) var dismiss
    @State private var enteredPIN: String = ""

    var body: some View {
        ZStack {
            // Warmer Hintergrund — konsistent mit dem Rest der App
            Color(red: 0.97, green: 0.96, blue: 0.93)
                .ignoresSafeArea()

            if viewModel.isUnlocked {
                // PIN korrekt — AdminView anzeigen
                AdminView(viewModel: viewModel)
                    .environmentObject(viewModel)
            } else {
                // PIN-Eingabe
                pinEntryContent
            }
        }
        .onAppear {
            enteredPIN = ""
            viewModel.pinError = false
            // Sicherstellen dass beim erneuten Öffnen immer gesperrt wird
            viewModel.lock()
        }
    }

    // MARK: - PIN Entry UI

    private var pinEntryContent: some View {
        VStack(spacing: 40) {
            Spacer()

            // Icon + Titel
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 100, height: 100)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                }

                Text(viewModel.isPINSetup ? "Admin-Bereich" : "PIN erstellen")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))

                Text(viewModel.isPINSetup
                     ? "Bitte PIN eingeben um fortzufahren."
                     : "Erstelle einen PIN um den Admin-Bereich zu schützen.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // PIN-Punkte Anzeige
            pinDotsDisplay

            // Numpad
            numpad

            // Fehler-Feedback
            if viewModel.pinError {
                Text("Falscher PIN. Bitte nochmal versuchen.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                    .transition(.opacity.combined(with: .scale))
            }

            Spacer()

            // Abbrechen
            Button("Abbrechen") {
                dismiss()
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.4))
            .padding(.bottom, 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.pinError)
    }

    // MARK: - PIN Dots

    private var pinDotsDisplay: some View {
        HStack(spacing: 20) {
            ForEach(0..<4, id: \.self) { index in
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if index < enteredPIN.count {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: enteredPIN.count)
            }
        }
    }

    // MARK: - Numpad

    private var numpad: some View {
        VStack(spacing: 16) {
            ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { digit in
                        numpadButton(label: "\(digit)") {
                            appendDigit("\(digit)")
                        }
                    }
                }
            }
            // Letzte Reihe: leer, 0, Delete
            HStack(spacing: 24) {
                // Leerer Platzhalter
                Color.clear
                    .frame(width: 72, height: 72)

                numpadButton(label: "0") {
                    appendDigit("0")
                }

                // Delete
                Button {
                    deleteLastDigit()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.9, green: 0.88, blue: 0.85))
                            .frame(width: 72, height: 72)

                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(Color(red: 0.4, green: 0.38, blue: 0.35))
                    }
                }
            }
        }
    }

    private func numpadButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

                Text(label)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.1))
            }
        }
        .buttonStyle(BounceButtonStyle())
    }

    // MARK: - Helpers

    private func appendDigit(_ digit: String) {
        guard enteredPIN.count < 4 else { return }
        // Fehler-State beim Tippen zurücksetzen
        if viewModel.pinError { viewModel.pinError = false }
        enteredPIN += digit

        // Automatisch submitten sobald 4 Ziffern eingegeben
        if enteredPIN.count == 4 {
            submitPIN()
        }
    }

    private func deleteLastDigit() {
        guard !enteredPIN.isEmpty else { return }
        enteredPIN.removeLast()
        if viewModel.pinError { viewModel.pinError = false }
    }

    private func submitPIN() {
        if viewModel.isPINSetup {
            viewModel.verifyPIN(enteredPIN)
        } else {
            viewModel.setupPIN(enteredPIN)
        }
        // PIN-Feld immer leeren nach Submit — egal ob richtig oder falsch
        enteredPIN = ""
    }

    // MARK: - Button Style

    private struct BounceButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
                .animation(
                    .spring(response: 0.2, dampingFraction: 0.6),
                    value: configuration.isPressed
                )
        }
    }
}
