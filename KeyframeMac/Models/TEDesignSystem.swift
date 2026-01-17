import SwiftUI
import AppKit

// MARK: - TE Design System (Teenage Engineering Inspired)

/// Color palette inspired by Teenage Engineering's aesthetic - Light theme
enum TEColors {
    // Light theme colors (always used)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let warmWhite = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let black = Color(red: 0.08, green: 0.08, blue: 0.08)
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

// MARK: - Theme Colors (Simplified - Always TE Light)

/// Provides semantic colors for the TE light theme
struct ThemeColors {
    // No configuration needed - always TE light theme
    init() {}

    // For compatibility with existing code that passes parameters
    init(theme: Any, isDark: Bool) {}

    // MARK: - Backgrounds

    var windowBackground: Color { TEColors.cream }
    var controlBackground: Color { TEColors.warmWhite }
    var sectionBackground: Color { TEColors.warmWhite }

    // MARK: - Text

    var primaryText: Color { TEColors.black }
    var secondaryText: Color { TEColors.darkGray }

    // MARK: - Accent Colors

    var accent: Color { TEColors.orange }
    var accentText: Color { .white }

    // MARK: - Borders

    var border: Color { TEColors.black }
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

// MARK: - Theme Provider (Simplified)

/// Observable object that provides theme colors - always TE light
final class ThemeProvider: ObservableObject {
    static let shared = ThemeProvider()

    private init() {
        // Force light mode on app launch
        DispatchQueue.main.async {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    var colors: ThemeColors { ThemeColors() }
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
