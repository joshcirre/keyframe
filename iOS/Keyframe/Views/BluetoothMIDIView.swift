import SwiftUI
import CoreAudioKit

/// Wrapper for iOS Bluetooth MIDI pairing (CABTMIDICentralViewController)
struct BluetoothMIDIView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("BLUETOOTH MIDI")
                        .font(TEFonts.display(16, weight: .black))
                        .foregroundColor(TEColors.black)
                        .tracking(2)

                    Spacer()

                    Button {
                        // Refresh MIDI destinations after pairing
                        MIDIEngine.shared.refreshDestinations()
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(TEColors.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(TEColors.warmWhite)

                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)

                // Bluetooth MIDI Central View Controller
                BluetoothMIDIViewControllerWrapper()
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - UIKit Wrapper

struct BluetoothMIDIViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let btViewController = CABTMIDICentralViewController()
        let navController = UINavigationController(rootViewController: btViewController)
        navController.navigationBar.isHidden = true
        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - Preview

#Preview {
    BluetoothMIDIView()
}
