import SwiftUI
import AppKit

/// Manages app appearance - always uses TE dark theme
final class AppearanceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppearanceManager()

    // MARK: - Initialization

    private init() {
        // Force dark mode
        DispatchQueue.main.async {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Always dark mode
    var isDarkMode: Bool { true }
}
