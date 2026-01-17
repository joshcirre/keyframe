import SwiftUI
import AppKit

// MARK: - TE Design System (Teenage Engineering Inspired)

/// Color palette inspired by Teenage Engineering's aesthetic
enum TEColors {
    // Light theme colors
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let warmWhite = Color(red: 0.99, green: 0.98, blue: 0.96)

    // Dark theme colors
    static let darkBackground = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let darkControl = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let darkSection = Color(red: 0.12, green: 0.12, blue: 0.12)

    // Text colors
    static let black = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let lightGray = Color(red: 0.9, green: 0.9, blue: 0.9)
    static let darkGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    static let midGray = Color(red: 0.6, green: 0.6, blue: 0.6)

    // Accent colors
    static let orange = Color(red: 1.0, green: 0.45, blue: 0.0)
    static let red = Color(red: 0.9, green: 0.2, blue: 0.15)
    static let green = Color(red: 0.2, green: 0.75, blue: 0.3)
    static let yellow = Color(red: 0.95, green: 0.8, blue: 0.0)
}

/// Font helpers for consistent typography
enum TEFonts {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Theme Colors

/// Provides semantic colors for the TE theme (light or dark mode)
struct ThemeColors {
    let isDarkMode: Bool

    init(isDarkMode: Bool = false) {
        self.isDarkMode = isDarkMode
    }

    // For compatibility with existing code that passes parameters
    init(theme: Any, isDark: Bool) {
        self.isDarkMode = isDark
    }

    // MARK: - Backgrounds

    var windowBackground: Color {
        isDarkMode ? TEColors.darkBackground : TEColors.cream
    }
    var controlBackground: Color {
        isDarkMode ? TEColors.darkControl : TEColors.warmWhite
    }
    var sectionBackground: Color {
        isDarkMode ? TEColors.darkSection : TEColors.warmWhite
    }

    // MARK: - Text

    var primaryText: Color {
        isDarkMode ? TEColors.lightGray : TEColors.black
    }
    var secondaryText: Color {
        isDarkMode ? TEColors.midGray : TEColors.darkGray
    }

    // MARK: - Accent Colors

    var accent: Color { TEColors.orange }
    var accentText: Color { .white }

    // MARK: - Borders

    var border: Color {
        isDarkMode ? TEColors.midGray : TEColors.black
    }
    var borderWidth: CGFloat { 2 }

    // MARK: - Status Colors

    var success: Color { TEColors.green }
    var warning: Color { TEColors.yellow }
    var error: Color { TEColors.red }

    // MARK: - Corner Radius (Brutalist = no rounded corners)

    var cornerRadius: CGFloat { 0 }
    var smallCornerRadius: CGFloat { 0 }

    // MARK: - Fonts

    func bodyFont(size: CGFloat = 13) -> Font {
        TEFonts.mono(size)
    }

    func headingFont(size: CGFloat = 14) -> Font {
        TEFonts.display(size, weight: .bold)
    }

    func monoFont(size: CGFloat = 12) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - Theme Provider

/// Observable object that provides theme colors with dark/light mode support
final class ThemeProvider: ObservableObject {
    static let shared = ThemeProvider()

    private let darkModeKey = "keyframe.isDarkMode"

    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: darkModeKey)
            updateAppearance()
        }
    }

    private init() {
        // Load saved preference (default to light mode)
        self.isDarkMode = UserDefaults.standard.bool(forKey: darkModeKey)

        // Apply appearance on launch
        DispatchQueue.main.async { [weak self] in
            self?.updateAppearance()
        }
    }

    var colors: ThemeColors {
        ThemeColors(isDarkMode: isDarkMode)
    }

    func toggleDarkMode() {
        isDarkMode.toggle()
    }

    private func updateAppearance() {
        NSApp.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
    }
}

// MARK: - View Modifiers

/// Applies TE-style section styling
struct TESectionStyle: ViewModifier {
    let themeColors: ThemeColors

    func body(content: Content) -> some View {
        content
            .background(themeColors.sectionBackground)
            .overlay(
                Rectangle()
                    .strokeBorder(themeColors.border, lineWidth: themeColors.borderWidth)
            )
    }
}

/// Applies TE-style button styling
struct TEButtonStyle: ButtonStyle {
    let themeColors: ThemeColors
    let isAccent: Bool

    init(themeColors: ThemeColors, isAccent: Bool = false) {
        self.themeColors = themeColors
        self.isAccent = isAccent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(themeColors.bodyFont())
            .foregroundColor(isAccent ? themeColors.accentText : themeColors.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isAccent ? themeColors.accent : themeColors.controlBackground)
            .overlay(
                Rectangle()
                    .strokeBorder(themeColors.border, lineWidth: themeColors.borderWidth)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - View Extensions

extension View {
    func teSectionStyle(colors: ThemeColors) -> some View {
        self.modifier(TESectionStyle(themeColors: colors))
    }

    func teButtonStyle(colors: ThemeColors, isAccent: Bool = false) -> some View {
        self.buttonStyle(TEButtonStyle(themeColors: colors, isAccent: isAccent))
    }
}

// MARK: - Legacy Compatibility

/// Kept for compatibility - not used
enum AppTheme: String, CaseIterable {
    case te = "Keyframe"

    var displayName: String { "Keyframe" }
    var icon: String { "keyboard" }
}
