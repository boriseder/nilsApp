// Admin Views Group
import SwiftUI

/// The secure entry point for the Admin area. Explicitly avoids FaceID/TouchID.
struct PINEntryView: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) var dismiss // For dismissing the sheet
    @State private var enteredPIN: String = ""
    
    var body: some View {
        // --- DEVELOPMENT MODE: BYPASS PIN ENTRY ---
        AdminView(viewModel: viewModel)
            .environmentObject(viewModel)
        /*
        VStack(spacing: 32) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text(viewModel.isPINSetup ? "Enter Admin PIN" : "Create Admin PIN")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Conditional view based on whether the admin area is unlocked
            if viewModel.isUnlocked {
                AdminView(viewModel: viewModel)
                    .environmentObject(viewModel) // Pass the AdminViewModel to AdminView
            } else {
                // PIN entry UI
                if viewModel.isPINSetup == false {
                    Text("This PIN prevents your child from exiting the safe area.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                SecureField("PIN (Min. 4 digits)", text: $enteredPIN)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                .onChange(of: enteredPIN) { _ in
                    // Clear error state as soon as the user starts typing again
                    if viewModel.pinError {
                        viewModel.pinError = false
                    }
                }
                
                if viewModel.pinError {
                    Text("Incorrect PIN. Please try again.")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                Button(action: submitPIN) {
                    Text(viewModel.isPINSetup ? "Unlock" : "Save PIN")
                        .font(.title2)
                        .bold()
                        .frame(maxWidth: 250)
                        .padding()
                        .background(enteredPIN.count >= 4 ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(enteredPIN.count < 4)
                
                // Cancel button to dismiss the sheet
                Button("Cancel") {
                    dismiss()
                }
                .font(.title2)
                .padding()
            }
        }
        .padding()
        // Reset PIN entry state when the view appears (e.g., if it was dismissed and reopened)
        .onAppear {
            enteredPIN = ""
            viewModel.pinError = false
            viewModel.lock() // Ensure it's locked when presented
        }
        */
    }
    
    private func submitPIN() {
        if viewModel.isPINSetup {
            viewModel.verifyPIN(enteredPIN)
        } else {
            viewModel.setupPIN(enteredPIN)
        }
        enteredPIN = ""
    }
}