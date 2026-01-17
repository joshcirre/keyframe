import SwiftUI

/// Remote mode view - connects to Mac and displays synced presets
struct RemoteModeView: View {
    @StateObject private var remote = KeyframeRemote.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TEColors.black.ignoresSafeArea()

            switch remote.connectionState {
            case .disconnected:
                disconnectedView

            case .searching, .found:
                searchingView

            case .connecting(let name):
                connectingView(name: name)

            case .connected(let name):
                connectedView(name: name)

            case .error(let message):
                errorView(message: message)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            remote.startSearching()
        }
        .onDisappear {
            remote.disconnect()
        }
    }

    // MARK: - Disconnected View

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(TEColors.midGray)

            Text("REMOTE MODE")
                .font(TEFonts.display(24, weight: .black))
                .foregroundColor(TEColors.cream)
                .tracking(4)

            Text("Connect to Keyframe on your Mac")
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundColor(TEColors.midGray)

            Button {
                remote.startSearching()
            } label: {
                Text("START SEARCHING")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(TEColors.orange)
                    .overlay(Rectangle().strokeBorder(TEColors.cream, lineWidth: 2))
            }

            exitButton
        }
    }

    // MARK: - Searching View

    private var searchingView: some View {
        VStack(spacing: 24) {
            SearchingAnimation()

            Text("SEARCHING")
                .font(TEFonts.display(20, weight: .black))
                .foregroundColor(TEColors.cream)
                .tracking(4)

            Text("Looking for Keyframe on your network...")
                .font(TEFonts.mono(12, weight: .regular))
                .foregroundColor(TEColors.midGray)

            Text("Make sure Keyframe is running on your Mac")
                .font(TEFonts.mono(11, weight: .regular))
                .foregroundColor(TEColors.darkGray)

            exitButton
        }
    }

    // MARK: - Connecting View

    private func connectingView(name: String) -> some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: TEColors.orange))
                .scaleEffect(1.5)

            Text("CONNECTING")
                .font(TEFonts.display(20, weight: .black))
                .foregroundColor(TEColors.cream)
                .tracking(4)

            Text(name)
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundColor(TEColors.midGray)
        }
    }

    // MARK: - Connected View (Main Remote Interface)

    private func connectedView(name: String) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                remoteHeader(name: name)

                // Main content
                HStack(spacing: 0) {
                    // Preset Grid
                    presetGrid
                        .frame(width: geometry.size.width * 0.75)

                    // Master Fader
                    masterFaderPanel
                        .frame(width: geometry.size.width * 0.25)
                }
            }
        }
    }

    private func remoteHeader(name: String) -> some View {
        HStack {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(TEColors.green)
                    .frame(width: 10, height: 10)

                Text("CONNECTED TO")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.midGray)

                Text(name.uppercased())
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(TEColors.cream)
            }

            Spacer()

            // Disconnect button
            Button {
                remote.disconnect()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("EXIT")
                        .font(TEFonts.mono(10, weight: .bold))
                }
                .foregroundColor(TEColors.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(TEColors.darkGray)
                .overlay(Rectangle().strokeBorder(TEColors.midGray, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))
    }

    private var presetGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(Array(remote.presets.enumerated()), id: \.element.id) { index, preset in
                    RemotePresetButton(
                        preset: preset,
                        isActive: remote.activePresetIndex == index,
                        onTap: {
                            remote.selectPreset(at: index)
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(TEColors.black)
    }

    private var masterFaderPanel: some View {
        VStack(spacing: 16) {
            Text("MASTER")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundColor(TEColors.cream)

            Spacer()

            // Large vertical fader
            RemoteFader(value: Binding(
                get: { remote.masterVolume },
                set: { remote.setMasterVolume($0) }
            ))
            .frame(width: 60, height: 200)

            // Volume display
            Text("\(Int(remote.masterVolume * 100))")
                .font(TEFonts.mono(24, weight: .bold))
                .foregroundColor(TEColors.cream)

            Spacer()
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(TEColors.darkGray.opacity(0.3))
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(TEColors.red)

            Text("CONNECTION ERROR")
                .font(TEFonts.display(20, weight: .black))
                .foregroundColor(TEColors.cream)
                .tracking(4)

            Text(message)
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundColor(TEColors.midGray)

            Button {
                remote.startSearching()
            } label: {
                Text("TRY AGAIN")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(TEColors.orange)
                    .overlay(Rectangle().strokeBorder(TEColors.cream, lineWidth: 2))
            }

            exitButton
        }
    }

    // MARK: - Common Components

    private var exitButton: some View {
        Button {
            remote.disconnect()
            dismiss()
        } label: {
            Text("EXIT REMOTE MODE")
                .font(TEFonts.mono(11, weight: .medium))
                .foregroundColor(TEColors.midGray)
                .padding(.top, 20)
        }
    }
}

// MARK: - Searching Animation

struct SearchingAnimation: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(TEColors.darkGray, lineWidth: 3)
                .frame(width: 80, height: 80)

            // Animated arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(TEColors.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(rotation))

            // Center icon
            Image(systemName: "wifi")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(TEColors.cream)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Remote Preset Button

struct RemotePresetButton: View {
    let preset: RemotePreset
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Spacer(minLength: 8)

                Text(preset.name.uppercased())
                    .font(TEFonts.mono(14, weight: .bold))
                    .foregroundColor(isActive ? .white : TEColors.cream)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let rootNote = preset.rootNote, let scale = preset.scale {
                    let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
                    Text("\(noteName) \(scale)")
                        .font(TEFonts.mono(11, weight: .medium))
                        .foregroundColor(isActive ? .white.opacity(0.8) : TEColors.midGray)
                }

                if let bpm = preset.bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(TEFonts.mono(10, weight: .regular))
                        .foregroundColor(isActive ? .white.opacity(0.6) : TEColors.darkGray)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(isActive ? TEColors.orange : TEColors.darkGray.opacity(0.5))
            .overlay(
                Rectangle()
                    .strokeBorder(isActive ? TEColors.cream : TEColors.midGray, lineWidth: isActive ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Remote Fader

struct RemoteFader: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                Rectangle()
                    .fill(TEColors.black)

                // Fill
                Rectangle()
                    .fill(TEColors.orange)
                    .frame(height: geometry.size.height * CGFloat(value))

                // Border
                Rectangle()
                    .strokeBorder(TEColors.cream, lineWidth: 2)

                // Handle
                Rectangle()
                    .fill(TEColors.cream)
                    .frame(height: 6)
                    .offset(y: -geometry.size.height * CGFloat(value) + 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percent = 1.0 - Float(gesture.location.y / geometry.size.height)
                        value = min(max(percent, 0), 1)
                    }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    RemoteModeView()
}
