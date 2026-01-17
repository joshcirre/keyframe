import SwiftUI

/// Mode selection - choose between local performance or remote control
struct ModeSelectionView: View {
    @State private var showingRemoteMode = false
    @State private var showingLocalMode = false
    @State private var logoScale: CGFloat = 0.8

    var body: some View {
        ZStack {
            TEColors.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Text("KEYFRAME")
                        .font(TEFonts.display(36, weight: .black))
                        .foregroundColor(TEColors.cream)
                        .tracking(6)
                        .scaleEffect(logoScale)

                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: 140, height: 4)
                }

                Spacer()

                // Mode buttons
                VStack(spacing: 20) {
                    // Local Mode
                    ModeButton(
                        icon: "pianokeys",
                        title: "LOCAL MODE",
                        subtitle: "Full performance engine on this device",
                        color: TEColors.orange
                    ) {
                        showingLocalMode = true
                    }

                    // Remote Mode
                    ModeButton(
                        icon: "link",
                        title: "REMOTE MODE",
                        subtitle: "Control Keyframe on your Mac",
                        color: TEColors.cream
                    ) {
                        showingRemoteMode = true
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                // Version
                Text("v1.0")
                    .font(TEFonts.mono(10, weight: .regular))
                    .foregroundColor(TEColors.darkGray)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                logoScale = 1.0
            }
        }
        .fullScreenCover(isPresented: $showingLocalMode) {
            PerformanceView()
        }
        .fullScreenCover(isPresented: $showingRemoteMode) {
            RemoteModeView()
        }
    }
}

// MARK: - Mode Button

struct ModeButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 50)

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(TEFonts.mono(16, weight: .bold))
                        .foregroundColor(TEColors.cream)

                    Text(subtitle)
                        .font(TEFonts.mono(11, weight: .regular))
                        .foregroundColor(TEColors.midGray)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TEColors.midGray)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(TEColors.darkGray.opacity(0.3))
            .overlay(
                Rectangle()
                    .strokeBorder(color.opacity(0.5), lineWidth: 2)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Preview

#Preview {
    ModeSelectionView()
}
