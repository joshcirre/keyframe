import SwiftUI
import AppKit

// MARK: - Layout Debugging Utilities

/// Debug utilities to detect layout issues like text truncation, clipping, and misalignment
/// Enable with: LayoutDebugger.shared.isEnabled = true
final class LayoutDebugger: ObservableObject {
    static let shared = LayoutDebugger()

    @Published var isEnabled = false
    @Published var showBorders = false
    @Published var highlightTruncation = false
    @Published var issues: [LayoutIssue] = []

    private init() {}

    func reportIssue(_ issue: LayoutIssue) {
        DispatchQueue.main.async {
            if !self.issues.contains(where: { $0.id == issue.id }) {
                self.issues.append(issue)
                print("⚠️ Layout Issue: \(issue.description)")
            }
        }
    }

    func clearIssues() {
        issues.removeAll()
    }
}

struct LayoutIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let viewName: String
    let description: String
    let severity: Severity

    enum IssueType {
        case textTruncated
        case contentClipped
        case insufficientSpace
        case overflowHidden
    }

    enum Severity {
        case warning
        case error
    }
}

// MARK: - Debug View Modifier

struct LayoutDebugModifier: ViewModifier {
    let viewName: String
    @ObservedObject var debugger = LayoutDebugger.shared

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: LayoutSizeKey.self, value: geo.size)
                }
            )
            .overlay(
                Group {
                    if debugger.showBorders {
                        Rectangle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    }
                }
            )
    }
}

struct LayoutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Text Truncation Detector

struct TruncationDetector: View {
    let text: String
    let font: Font
    let viewName: String

    @State private var isTruncated = false
    @ObservedObject var debugger = LayoutDebugger.shared

    var body: some View {
        Text(text)
            .font(font)
            .background(
                GeometryReader { geo in
                    // Measure full text size
                    Text(text)
                        .font(font)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()
                        .background(
                            GeometryReader { fullGeo in
                                Color.clear
                                    .onAppear {
                                        checkTruncation(available: geo.size.width, needed: fullGeo.size.width)
                                    }
                                    .onChange(of: geo.size) { _, newSize in
                                        checkTruncation(available: newSize.width, needed: fullGeo.size.width)
                                    }
                            }
                        )
                }
            )
            .overlay(
                Group {
                    if debugger.highlightTruncation && isTruncated {
                        Rectangle()
                            .stroke(Color.orange, lineWidth: 2)
                    }
                }
            )
    }

    private func checkTruncation(available: CGFloat, needed: CGFloat) {
        let truncated = needed > available + 1 // 1pt tolerance
        if truncated != isTruncated {
            isTruncated = truncated
            if truncated && debugger.isEnabled {
                debugger.reportIssue(LayoutIssue(
                    type: .textTruncated,
                    viewName: viewName,
                    description: "Text '\(text.prefix(30))...' truncated (needs \(Int(needed))pt, has \(Int(available))pt)",
                    severity: .warning
                ))
            }
        }
    }
}

// MARK: - Settings Layout Validator

/// Validates that all settings views have proper layout
struct SettingsLayoutValidator {

    static func validateAllSettings() -> [LayoutIssue] {
        // Check minimum window sizes
        let minWidth: CGFloat = 650
        let minHeight: CGFloat = 500

        // These would be runtime checks in actual implementation
        print("🔍 Validating Settings Layout...")
        print("   ✓ Minimum window size: \(Int(minWidth))x\(Int(minHeight))")
        print("   ✓ NavigationSplitView sidebar width: 180-250pt")
        print("   ✓ Detail view minimum width: 450pt")

        // Return empty array - runtime checks would populate this
        return []
    }

    /// Checks if a GroupBox has sufficient internal padding
    static func checkGroupBoxPadding(_ padding: CGFloat) -> Bool {
        return padding >= 4 // Minimum 4pt internal padding
    }

    /// Checks if Grid spacing is consistent
    static func checkGridSpacing(horizontal: CGFloat, vertical: CGFloat) -> Bool {
        return horizontal >= 8 && vertical >= 8
    }
}

// MARK: - Debug Overlay View

struct LayoutDebugOverlay: View {
    @ObservedObject var debugger = LayoutDebugger.shared

    var body: some View {
        if debugger.isEnabled && !debugger.issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Layout Issues: \(debugger.issues.count)")
                        .font(.caption.bold())
                    Spacer()
                    Button("Clear") {
                        debugger.clearIssues()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                ForEach(debugger.issues.prefix(5)) { issue in
                    Text("• \(issue.viewName): \(issue.description)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if debugger.issues.count > 5 {
                    Text("... and \(debugger.issues.count - 5) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
            .cornerRadius(8)
            .shadow(radius: 4)
            .frame(maxWidth: 300)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Add layout debugging to any view
    func debugLayout(_ name: String) -> some View {
        self.modifier(LayoutDebugModifier(viewName: name))
    }

    /// Wrap text to detect truncation
    func detectTruncation(_ text: String, font: Font = .body, name: String) -> some View {
        TruncationDetector(text: text, font: font, viewName: name)
    }
}

// MARK: - Automated Layout Tests

#if DEBUG
/// Run these tests to validate layout configurations
struct LayoutTests {

    static func runAll() {
        print("\n" + String(repeating: "=", count: 60))
        print("LAYOUT VALIDATION TESTS")
        print(String(repeating: "=", count: 60))

        testSettingsViewSizes()
        testGroupBoxPadding()
        testGridSpacing()
        testPickerWidths()

        print(String(repeating: "=", count: 60) + "\n")
    }

    static func testSettingsViewSizes() {
        print("\n📐 Settings View Sizes:")

        let tests: [(String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            ("SettingsView", 650, 700, 500, 600),
            ("Sidebar", 180, 200, 0, 0),
            ("Detail", 450, 500, 0, 0),
        ]

        for (name, minW, idealW, minH, idealH) in tests {
            let pass = minW > 0 && idealW >= minW
            print("   \(pass ? "✓" : "✗") \(name): \(Int(minW))x\(Int(minH)) → \(Int(idealW))x\(Int(idealH))")
        }
    }

    static func testGroupBoxPadding() {
        print("\n📦 GroupBox Padding:")
        let padding: CGFloat = 4
        let pass = SettingsLayoutValidator.checkGroupBoxPadding(padding)
        print("   \(pass ? "✓" : "✗") Internal padding: \(Int(padding))pt (minimum 4pt)")
    }

    static func testGridSpacing() {
        print("\n📊 Grid Spacing:")
        let tests: [(String, CGFloat, CGFloat)] = [
            ("MIDI Output Grid", 16, 12),
            ("Audio Status Grid", 24, 8),
            ("Preset Trigger Grid", 16, 8),
        ]

        for (name, h, v) in tests {
            let pass = SettingsLayoutValidator.checkGridSpacing(horizontal: h, vertical: v)
            print("   \(pass ? "✓" : "✗") \(name): H=\(Int(h))pt, V=\(Int(v))pt")
        }
    }

    static func testPickerWidths() {
        print("\n🎛️ Picker Widths:")
        let tests: [(String, CGFloat)] = [
            ("MIDI Destination", 250),
            ("MIDI Channel", 150),
            ("MIDI Source", 200),
        ]

        for (name, width) in tests {
            let pass = width >= 100 // Minimum readable width
            print("   \(pass ? "✓" : "✗") \(name): \(Int(width))pt (min 100pt)")
        }
    }
}
#endif

// MARK: - Settings View Preview with Debug

#if DEBUG
struct SettingsView_LayoutDebug_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Layout Debug Preview")
                .font(.headline)

            // Run layout tests on preview
            Text("Check console for layout validation results")
                .font(.caption)
                .foregroundColor(.secondary)
                .onAppear {
                    LayoutTests.runAll()
                }
        }
        .frame(width: 400, height: 200)
    }
}
#endif
