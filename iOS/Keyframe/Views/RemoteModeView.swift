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
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // Fullscreen preset grid
                    RemotePresetGridView(
                        presets: remote.presets,
                        activeIndex: remote.activePresetIndex,
                        onSelectPreset: { index in
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            remote.selectPreset(at: index)
                        }
                    )
                    .padding(.top, 44)  // Room for control buttons overlay
                    .background(TEColors.cream)

                    // Status bar
                    RemoteStatusBar(
                        macName: name,
                        presetCount: remote.presets.count,
                        activeIndex: remote.activePresetIndex
                    )
                }

                // Control buttons (top-right)
                remoteControlButtons
            }
        }
    }

    private var remoteControlButtons: some View {
        HStack(spacing: 6) {
            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(TEColors.green)
                    .frame(width: 8, height: 8)
                Text("LIVE")
                    .font(TEFonts.mono(9, weight: .bold))
                    .foregroundColor(TEColors.black)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TEColors.cream.opacity(0.9))
            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 1))

            // Close button
            Button {
                remote.disconnect()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TEColors.black)
                    .frame(width: 28, height: 28)
                    .background(TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
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

// MARK: - Remote Preset Grid View

struct RemotePresetGridView: View {
    let presets: [RemotePreset]
    let activeIndex: Int?
    let onSelectPreset: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let itemCount = presets.count
            let spacing: CGFloat = 6
            let padding: CGFloat = 6
            let availableWidth = geometry.size.width - (padding * 2)
            let availableHeight = geometry.size.height - (padding * 2)

            let (columns, rows) = calculateGrid(itemCount: max(1, itemCount), availableWidth: availableWidth, availableHeight: availableHeight)

            let totalHorizontalSpacing = spacing * CGFloat(columns - 1)
            let totalVerticalSpacing = spacing * CGFloat(rows - 1)
            let itemWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(columns)
            let itemHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

            let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)

            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    RemotePresetGridButton(
                        preset: preset,
                        isActive: activeIndex == index,
                        onTap: { onSelectPreset(index) }
                    )
                    .frame(height: itemHeight)
                }
            }
            .padding(padding)
        }
    }

    private func calculateGrid(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> (columns: Int, rows: Int) {
        guard itemCount > 0 else { return (1, 1) }

        var bestColumns = 1
        var bestScore: CGFloat = 0

        for cols in 1...max(1, itemCount) {
            let rows = Int(ceil(Double(itemCount) / Double(cols)))
            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)

            let cellAspect = cellWidth / cellHeight
            let targetAspect: CGFloat = 1.5
            let aspectScore = 1.0 / (1.0 + abs(cellAspect - targetAspect))

            let usedCells = itemCount
            let totalCells = cols * rows
            let fillScore = CGFloat(usedCells) / CGFloat(totalCells)

            let score = aspectScore * 0.6 + fillScore * 0.4

            if score > bestScore {
                bestScore = score
                bestColumns = cols
            }
        }

        let bestRows = Int(ceil(Double(itemCount) / Double(bestColumns)))
        return (bestColumns, bestRows)
    }
}

// MARK: - Remote Preset Grid Button

struct RemotePresetGridButton: View {
    let preset: RemotePreset
    let isActive: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height)
            let nameFontSize: CGFloat = max(16, min(minDimension * 0.35, 48))
            let songNameFontSize: CGFloat = max(12, nameFontSize * 0.5)

            Button(action: onTap) {
                ZStack {
                    VStack(spacing: minDimension * 0.03) {
                        Spacer(minLength: 4)

                        // Preset name (main)
                        Text(preset.name.uppercased())
                            .font(TEFonts.mono(nameFontSize, weight: .black))
                            .foregroundColor(isActive ? .white : TEColors.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)

                        // Song name (if set)
                        if let songName = preset.songName, !songName.isEmpty {
                            Text(songName.uppercased())
                                .font(TEFonts.mono(songNameFontSize, weight: .medium))
                                .foregroundColor(isActive ? .white.opacity(0.7) : TEColors.midGray)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)

                    // BPM indicator (top-left orange dot if BPM is set)
                    if preset.bpm != nil {
                        VStack {
                            HStack {
                                Circle()
                                    .fill(TEColors.orange)
                                    .frame(width: 10, height: 10)
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(isActive ? TEColors.orange : TEColors.warmWhite)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(TEColors.black, lineWidth: isActive ? 3 : 2)
                )
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(.easeOut(duration: 0.1), value: isPressed)
            }
            .buttonStyle(.plain)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Remote Status Bar

struct RemoteStatusBar: View {
    let macName: String
    let presetCount: Int
    let activeIndex: Int?

    var body: some View {
        HStack(spacing: 16) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(TEColors.green)
                    .frame(width: 8, height: 8)

                Text("REMOTE")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.black)
            }

            // Mac name
            Text(macName.uppercased())
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(TEColors.darkGray)

            Spacer()

            // Preset count
            if let index = activeIndex {
                Text("\(index + 1)/\(presetCount)")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(TEColors.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 32)
        .background(TEColors.warmWhite)
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(TEColors.black),
            alignment: .top
        )
    }
}

// MARK: - Preview

#Preview {
    RemoteModeView()
}
