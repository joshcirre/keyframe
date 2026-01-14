import SwiftUI
import AppKit

// MARK: - TE Design System (Teenage Engineering Inspired)

/// Color palette inspired by Teenage Engineering's aesthetic
enum TEColors {
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let warmWhite = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let orange = Color(red: 1.0, green: 0.45, blue: 0.0)
    static let black = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let darkGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    static let midGray = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let lightGray = Color(red: 0.85, green: 0.83, blue: 0.80)
    static let red = Color(red: 0.9, green: 0.2, blue: 0.15)
    static let green = Color(red: 0.2, green: 0.75, blue: 0.3)
    static let yellow = Color(red: 0.95, green: 0.8, blue: 0.0)

    // Dark mode variants
    static let darkBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let darkSurface = Color(red: 0.18, green: 0.18, blue: 0.18)
    static let darkBorder = Color(red: 0.4, green: 0.4, blue: 0.4)
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

// MARK: - App Theme Enum

/// The visual style/theme of the app
enum AppTheme: String, CaseIterable {
    case native = "Native"
    case te = "Keyframe"

    var displayName: String {
        switch self {
        case .native: return "Native macOS"
        case .te: return "Keyframe (TE Style)"
        }
    }

    var icon: String {
        switch self {
        case .native: return "apple.logo"
        case .te: return "keyboard"
        }
    }
}

// MARK: - Theme Environment Key

struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .native
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Theme Colors (Semantic Colors Based on Theme)

/// Provides semantic colors that adapt based on the current theme and appearance
struct ThemeColors {
    let theme: AppTheme
    let isDark: Bool

    init(theme: AppTheme, isDark: Bool) {
        self.theme = theme
        self.isDark = isDark
    }

    // MARK: - Backgrounds

    var windowBackground: Color {
        switch theme {
        case .native:
            return Color(nsColor: .windowBackgroundColor)
        case .te:
            return isDark ? TEColors.darkBackground : TEColors.cream
        }
    }

    var controlBackground: Color {
        switch theme {
        case .native:
            return Color(nsColor: .controlBackgroundColor)
        case .te:
            return isDark ? TEColors.darkSurface : TEColors.warmWhite
        }
    }

    var sectionBackground: Color {
        switch theme {
        case .native:
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        case .te:
            return isDark ? TEColors.darkSurface : TEColors.warmWhite
        }
    }

    // MARK: - Text

    var primaryText: Color {
        switch theme {
        case .native:
            return Color(nsColor: .labelColor)
        case .te:
            return isDark ? TEColors.warmWhite : TEColors.black
        }
    }

    var secondaryText: Color {
        switch theme {
        case .native:
            return Color(nsColor: .secondaryLabelColor)
        case .te:
            return isDark ? TEColors.midGray : TEColors.darkGray
        }
    }

    // MARK: - Accent Colors

    var accent: Color {
        switch theme {
        case .native:
            return Color.accentColor
        case .te:
            return TEColors.orange
        }
    }

    var accentText: Color {
        switch theme {
        case .native:
            return .white
        case .te:
            return .white
        }
    }

    // MARK: - Borders

    var border: Color {
        switch theme {
        case .native:
            return Color(nsColor: .separatorColor)
        case .te:
            return isDark ? TEColors.darkBorder : TEColors.black
        }
    }

    var borderWidth: CGFloat {
        switch theme {
        case .native:
            return 1
        case .te:
            return 2
        }
    }

    // MARK: - Status Colors

    var success: Color {
        switch theme {
        case .native:
            return .green
        case .te:
            return TEColors.green
        }
    }

    var warning: Color {
        switch theme {
        case .native:
            return .yellow
        case .te:
            return TEColors.yellow
        }
    }

    var error: Color {
        switch theme {
        case .native:
            return .red
        case .te:
            return TEColors.red
        }
    }

    // MARK: - Corner Radius

    var cornerRadius: CGFloat {
        switch theme {
        case .native:
            return 6
        case .te:
            return 0  // Brutalist = no rounded corners
        }
    }

    var smallCornerRadius: CGFloat {
        switch theme {
        case .native:
            return 4
        case .te:
            return 0
        }
    }

    // MARK: - Fonts

    func bodyFont(size: CGFloat = 13) -> Font {
        switch theme {
        case .native:
            return .system(size: size)
        case .te:
            return TEFonts.mono(size)
        }
    }

    func headingFont(size: CGFloat = 14) -> Font {
        switch theme {
        case .native:
            return .system(size: size, weight: .semibold)
        case .te:
            return TEFonts.display(size, weight: .bold)
        }
    }

    func monoFont(size: CGFloat = 12) -> Font {
        // Both themes use mono for technical text
        return .system(size: size, design: .monospaced)
    }
}

// MARK: - Theme Provider

/// Observable object that provides current theme colors
final class ThemeProvider: ObservableObject {
    static let shared = ThemeProvider()

    @Published var theme: AppTheme = .native
    @Published var isDark: Bool = false

    private init() {
        // Observe appearance changes
        updateDarkMode()

        // Listen for effective appearance changes
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDarkMode()
        }
    }

    private func updateDarkMode() {
        isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var colors: ThemeColors {
        ThemeColors(theme: theme, isDark: isDark)
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
            .cornerRadius(themeColors.cornerRadius)
            .clipped()
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
            .cornerRadius(themeColors.cornerRadius)
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
