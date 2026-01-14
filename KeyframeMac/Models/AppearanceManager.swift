import SwiftUI
import AppKit

/// Manages app appearance settings including dark mode and theme
final class AppearanceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppearanceManager()

    // MARK: - Published Properties

    @Published var currentAppearance: AppAppearance {
        didSet {
            applyAppearance()
            saveSettings()
        }
    }

    @Published var currentTheme: AppTheme {
        didSet {
            saveSettings()
            ThemeProvider.shared.theme = currentTheme
        }
    }

    // MARK: - Persistence

    private let appearanceKey = "mac.appearance"
    private let themeKey = "mac.theme"

    // MARK: - Initialization

    private init() {
        // Load saved appearance or default to system
        if let savedValue = UserDefaults.standard.string(forKey: appearanceKey),
           let appearance = AppAppearance(rawValue: savedValue) {
            currentAppearance = appearance
        } else {
            currentAppearance = .system
        }

        // Load saved theme or default to native
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: savedTheme) {
            currentTheme = theme
        } else {
            currentTheme = .native
        }

        // Apply on init
        applyAppearance()
        ThemeProvider.shared.theme = currentTheme
    }

    // MARK: - Appearance Control

    private func applyAppearance() {
        DispatchQueue.main.async {
            switch self.currentAppearance {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(currentAppearance.rawValue, forKey: appearanceKey)
        UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
    }

    // MARK: - Helpers

    /// Returns true if the app is currently in dark mode
    var isDarkMode: Bool {
        switch currentAppearance {
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .dark:
            return true
        case .light:
            return false
        }
    }

    /// Cycle through appearance modes (for menu bar toggle)
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
}

// MARK: - App Appearance Enum

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Form {
            Section("Visual Style") {
                Picker("Style", selection: $appearanceManager.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        HStack {
                            Image(systemName: theme.icon)
                            Text(theme.displayName)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)

                // Theme description
                Text(themeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                // Preview
                HStack {
                    Spacer()
                    AppearancePreview(theme: appearanceManager.currentTheme)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Light/Dark Mode") {
                Picker("Mode", selection: $appearanceManager.currentAppearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        HStack {
                            Image(systemName: appearance.icon)
                            Text(appearance.displayName)
                        }
                        .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Image(systemName: appearanceManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(appearanceManager.isDarkMode ? .yellow : .orange)
                    Text(appearanceManager.isDarkMode ? "Dark Mode Active" : "Light Mode Active")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var themeDescription: String {
        switch appearanceManager.currentTheme {
        case .native:
            return "Uses standard macOS styling with system colors and rounded corners."
        case .te:
            return "Teenage Engineering-inspired brutalist design with cream/orange colors and sharp corners."
        }
    }
}

// MARK: - Appearance Preview

struct AppearancePreview: View {
    let theme: AppTheme
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private var colors: ThemeColors {
        ThemeColors(theme: theme, isDark: appearanceManager.isDarkMode)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Mini mixer preview
            HStack(spacing: theme == .te ? 0 : 4) {
                ForEach(0..<4, id: \.self) { index in
                    channelPreview(index: index)
                }
            }
            .padding(8)
            .background(colors.windowBackground)
            .cornerRadius(colors.cornerRadius)
            .overlay(
                Group {
                    if theme == .te {
                        Rectangle()
                            .strokeBorder(colors.border, lineWidth: colors.borderWidth)
                    } else {
                        RoundedRectangle(cornerRadius: colors.cornerRadius)
                            .stroke(colors.border, lineWidth: 1)
                    }
                }
            )

            Text("Preview")
                .font(colors.bodyFont(size: 10))
                .foregroundColor(colors.secondaryText)
        }
    }

    @ViewBuilder
    private func channelPreview(index: Int) -> some View {
        let isSelected = index == 0

        if theme == .te {
            // TE style: sharp corners, thick borders
            Rectangle()
                .fill(colors.controlBackground)
                .frame(width: 24, height: 44)
                .overlay(
                    VStack(spacing: 2) {
                        // Meter
                        Rectangle()
                            .fill(isSelected ? colors.accent : colors.success)
                            .frame(width: 6, height: 24)
                        // Label
                        Rectangle()
                            .fill(colors.secondaryText.opacity(0.3))
                            .frame(width: 12, height: 4)
                    }
                    .padding(4)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(colors.border, lineWidth: colors.borderWidth)
                )
        } else {
            // Native style: rounded corners
            RoundedRectangle(cornerRadius: 2)
                .fill(colors.controlBackground)
                .frame(width: 20, height: 40)
                .overlay(
                    VStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isSelected ? colors.accent.opacity(0.8) : colors.success.opacity(0.6))
                            .frame(width: 4, height: 20)
                        Spacer()
                    }
                    .padding(2)
                )
        }
    }
}

// MARK: - Menu Bar Appearance Toggle

struct AppearanceMenuContent: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ForEach(AppAppearance.allCases, id: \.self) { appearance in
            Button(action: { appearanceManager.currentAppearance = appearance }) {
                HStack {
                    Image(systemName: appearance.icon)
                    Text(appearance.displayName)
                    Spacer()
                    if appearanceManager.currentAppearance == appearance {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}
