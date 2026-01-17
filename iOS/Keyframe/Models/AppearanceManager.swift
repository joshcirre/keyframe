import SwiftUI
import UIKit

/// Manages app appearance settings including dark mode for iOS
final class AppearanceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppearanceManager()

    // MARK: - Published Properties

    @Published var currentAppearance: AppAppearance {
        didSet {
            applyAppearance()
            saveAppearance()
        }
    }

    // MARK: - Persistence

    private let appearanceKey = "ios.appearance"

    // MARK: - Initialization

    private init() {
        // Load saved appearance or default to light (matching current app behavior)
        if let savedValue = UserDefaults.standard.string(forKey: appearanceKey),
           let appearance = AppAppearance(rawValue: savedValue) {
            currentAppearance = appearance
        } else {
            currentAppearance = .light
        }

        // Apply on init (delayed to ensure windows exist)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyAppearance()
        }
    }

    // MARK: - Appearance Control

    private func applyAppearance() {
        DispatchQueue.main.async {
            let style: UIUserInterfaceStyle
            switch self.currentAppearance {
            case .system:
                style = .unspecified
            case .light:
                style = .light
            case .dark:
                style = .dark
            }

            // Apply to all windows
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }
    }

    private func saveAppearance() {
        UserDefaults.standard.set(currentAppearance.rawValue, forKey: appearanceKey)
    }

    // MARK: - Helpers

    /// Returns true if the app is currently in dark mode
    var isDarkMode: Bool {
        switch currentAppearance {
        case .system:
            return UITraitCollection.current.userInterfaceStyle == .dark
        case .dark:
            return true
        case .light:
            return false
        }
    }

    /// Cycle through appearance modes
    func cycleAppearance() {
        switch currentAppearance {
        case .system:
            currentAppearance = .light
        case .light:
            currentAppearance = .dark
        case .dark:
            currentAppearance = .system
        }
    }

    /// Get the preferred color scheme for SwiftUI views
    var colorScheme: ColorScheme? {
        switch currentAppearance {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

// MARK: - App Appearance Enum

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var displayName: String { rawValue.uppercased() }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}
