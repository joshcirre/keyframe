import SwiftUI
import UIKit

/// Manages app appearance settings including dark mode for iOS
@Observable
@MainActor
final class AppearanceManager {

    // MARK: - Singleton

    static let shared = AppearanceManager()

    // MARK: - Observable Properties

    var currentAppearance: AppAppearance {
        didSet {
            applyAppearance()
            saveSettings()
        }
    }

    /// Lock orientation when true
    var isOrientationLocked: Bool = false {
        didSet {
            applyOrientationLock()
            saveSettings()
        }
    }

    /// The locked orientation (portrait or landscape)
    var lockedOrientation: LockedOrientation = .portrait {
        didSet {
            if isOrientationLocked {
                applyOrientationLock()
            }
            saveSettings()
        }
    }

    // MARK: - Persistence

    @ObservationIgnored private let appearanceKey = "ios.appearance"
    @ObservationIgnored private let orientationLockKey = "ios.orientationLocked"
    @ObservationIgnored private let lockedOrientationKey = "ios.lockedOrientation"

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        // Load saved appearance or default to light (matching current app behavior)
        if let savedValue = defaults.string(forKey: appearanceKey),
           let appearance = AppAppearance(rawValue: savedValue) {
            currentAppearance = appearance
        } else {
            currentAppearance = .light
        }

        // Load orientation lock settings
        let savedIsLocked = defaults.bool(forKey: orientationLockKey)
        var savedLockedOrientation: LockedOrientation = .portrait
        if let savedOrientationString = defaults.string(forKey: lockedOrientationKey),
           let orientation = LockedOrientation(rawValue: savedOrientationString) {
            savedLockedOrientation = orientation
        }
        
        // Set AppDelegate lock immediately (before didSet triggers)
        if savedIsLocked {
            let mask: UIInterfaceOrientationMask = savedLockedOrientation == .portrait ? .portrait : .landscape
            AppDelegate.orientationLock = mask
        }
        
        // Now set properties (this will call didSet but AppDelegate is already configured)
        isOrientationLocked = savedIsLocked
        lockedOrientation = savedLockedOrientation

        // Apply on init (delayed to ensure windows exist)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyAppearance()
            if self?.isOrientationLocked == true {
                self?.applyOrientationLock()
            }
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

    // MARK: - Orientation Lock

    private func applyOrientationLock() {
        DispatchQueue.main.async {
            if self.isOrientationLocked {
                let mask: UIInterfaceOrientationMask = self.lockedOrientation == .portrait ? .portrait : .landscape
                AppDelegate.orientationLock = mask
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
                }
            } else {
                AppDelegate.orientationLock = .all
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
                }
            }
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentAppearance.rawValue, forKey: appearanceKey)
        defaults.set(isOrientationLocked, forKey: orientationLockKey)
        defaults.set(lockedOrientation.rawValue, forKey: lockedOrientationKey)
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

// MARK: - Locked Orientation Enum

enum LockedOrientation: String, CaseIterable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var displayName: String { rawValue.uppercased() }

    var icon: String {
        switch self {
        case .portrait: return "iphone"
        case .landscape: return "iphone.landscape"
        }
    }
}
