import SwiftUI

/// Small floating toggle to cycle between System/Light/Dark appearance.
struct AppearanceToggleButton: View {
    @State private var appearance = AppearanceManager.shared

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            appearance.cycleAppearance()
        } label: {
            Image(systemName: appearance.currentAppearance.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TEColors.cream)
                .frame(width: 36, height: 36)
                .background(TEColors.darkGray.opacity(0.8))
                .overlay(Rectangle().strokeBorder(TEColors.midGray, lineWidth: 1))
                .accessibilityLabel("Appearance")
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        TEColors.black.ignoresSafeArea()
        AppearanceToggleButton()
    }
}
