import SwiftUI

/// Remote mode view - connects to a Keyframe host and displays synced presets
struct RemoteModeView: View {
    @StateObject private var remote = KeyframeRemote.shared
    @State private var appearance = AppearanceManager.shared
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

            // Bottom-right appearance toggle
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AppearanceToggleButton()
                        .padding(16)
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
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
                .foregroundStyle(TEColors.midGray)

            Text("REMOTE MODE")
                .font(TEFonts.display(24, weight: .black))
                .foregroundStyle(TEColors.cream)
                .tracking(4)

            Text("Connect to Keyframe on your Mac or iPad")
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundStyle(TEColors.midGray)

            Button {
                remote.startSearching()
            } label: {
                Text("START SEARCHING")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundStyle(.white)
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
                .foregroundStyle(TEColors.cream)
                .tracking(4)

            Text("Looking for Keyframe on your network...")
                .font(TEFonts.mono(12, weight: .regular))
                .foregroundStyle(TEColors.midGray)

            Text("Make sure Keyframe is running in Local Mode")
                .font(TEFonts.mono(11, weight: .regular))
                .foregroundStyle(TEColors.darkGray)

            if !remote.discoveredHosts.isEmpty {
                hostPicker
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
            }

            exitButton
        }
    }

    private var hostPicker: some View {
        VStack(spacing: 8) {
            Text("HOSTS")
                .font(TEFonts.mono(9, weight: .bold))
                .foregroundStyle(TEColors.darkGray)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(remote.discoveredHosts) { host in
                Button {
                    remote.connect(to: host)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TEColors.orange)
                            .frame(width: 24)

                        Text(host.name.uppercased())
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundStyle(TEColors.cream)
                            .lineLimit(1)

                        Spacer()

                        Text("CONNECT")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundStyle(TEColors.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(TEColors.darkGray.opacity(0.35))
                    .overlay(Rectangle().strokeBorder(TEColors.midGray, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.35))
        .overlay(Rectangle().strokeBorder(TEColors.darkGray, lineWidth: 1))
    }

    // MARK: - Connecting View

    private func connectingView(name: String) -> some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: TEColors.orange))
                .scaleEffect(1.5)

            Text("CONNECTING")
                .font(TEFonts.display(20, weight: .black))
                .foregroundStyle(TEColors.cream)
                .tracking(4)

            Text(name)
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundStyle(TEColors.midGray)
        }
    }

    // MARK: - Connected View (Main Remote Interface)

    private func connectedView(name: String) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                remoteHeader(name: name)

                // Main content
                if !remote.channels.isEmpty && geometry.size.width < 600 {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            presetGrid
                                .frame(width: geometry.size.width * 0.72)

                            masterFaderPanel
                                .frame(width: geometry.size.width * 0.28)
                        }

                        layerMixerPanel
                            .frame(height: min(280, geometry.size.height * 0.42))
                    }
                } else {
                    HStack(spacing: 0) {
                        presetGrid
                            .frame(width: geometry.size.width * (remote.channels.isEmpty ? 0.75 : 0.55))

                        if !remote.channels.isEmpty {
                            layerMixerPanel
                                .frame(width: geometry.size.width * 0.30)
                        }

                        masterFaderPanel
                            .frame(width: geometry.size.width * (remote.channels.isEmpty ? 0.25 : 0.15))
                    }
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
                    .foregroundStyle(TEColors.midGray)

                Text(name.uppercased())
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundStyle(TEColors.cream)
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
                .foregroundStyle(TEColors.cream)
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
        GeometryReader { geometry in
            if remote.presets.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: TEColors.orange))
                    Text("Loading presets...")
                        .font(TEFonts.mono(12, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let itemCount = remote.presets.count
                let spacing: CGFloat = 6
                let padding: CGFloat = 6
                let availableWidth = geometry.size.width - (padding * 2)
                let availableHeight = geometry.size.height - (padding * 2)

                let (columns, rows) = calculateRemoteGrid(itemCount: itemCount, availableWidth: availableWidth, availableHeight: availableHeight)

                let totalHorizontalSpacing = spacing * CGFloat(columns - 1)
                let totalVerticalSpacing = spacing * CGFloat(rows - 1)
                let itemWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(columns)
                let itemHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

                let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)

                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(Array(remote.presets.enumerated()), id: \.element.id) { index, preset in
                        RemotePresetButton(
                            preset: preset,
                            isActive: remote.activePresetIndex == index,
                            onTap: {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                remote.selectPreset(at: index)
                            }
                        )
                        .frame(height: itemHeight)
                    }
                }
                .padding(padding)
            }
        }
        .background(TEColors.black)
    }

    private func calculateRemoteGrid(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> (columns: Int, rows: Int) {
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

    private var masterFaderPanel: some View {
        VStack(spacing: 16) {
            Text("MASTER")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(TEColors.cream)

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
                .foregroundStyle(TEColors.cream)

            Spacer()
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(TEColors.darkGray.opacity(0.3))
    }

    private var layerMixerPanel: some View {
        VStack(spacing: 10) {
            Text("LAYERS")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(TEColors.cream)
                .padding(.top, 14)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(remote.channels) { channel in
                        RemoteLayerStrip(
                            channel: channel,
                            volume: Binding(
                                get: { remote.channels.first(where: { $0.id == channel.id })?.volume ?? channel.volume },
                                set: { remote.setChannelVolume($0, channelID: channel.id) }
                            ),
                            pan: Binding(
                                get: { remote.channels.first(where: { $0.id == channel.id })?.pan ?? channel.pan },
                                set: { remote.setChannelPan($0, channelID: channel.id) }
                            ),
                            onToggleMute: {
                                let isMuted = remote.channels.first(where: { $0.id == channel.id })?.isMuted ?? channel.isMuted
                                remote.setChannelMuted(!isMuted, channelID: channel.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity)
        .background(TEColors.darkGray.opacity(0.18))
        .overlay(Rectangle().frame(width: 1).foregroundStyle(TEColors.darkGray), alignment: .leading)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(TEColors.red)

            Text("CONNECTION ERROR")
                .font(TEFonts.display(20, weight: .black))
                .foregroundStyle(TEColors.cream)
                .tracking(4)

            Text(message)
                .font(TEFonts.mono(14, weight: .regular))
                .foregroundStyle(TEColors.midGray)

            Button {
                remote.startSearching()
            } label: {
                Text("TRY AGAIN")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundStyle(.white)
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
                .foregroundStyle(TEColors.midGray)
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
                .foregroundStyle(TEColors.cream)
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

// MARK: - Remote Preset Grid Button (Dark Theme)

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
                            .foregroundStyle(isActive ? .white : TEColors.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)

                        // Song name (if set)
                        if let songName = preset.songName, !songName.isEmpty {
                            Text(songName.uppercased())
                                .font(TEFonts.mono(songNameFontSize, weight: .medium))
                                .foregroundStyle(isActive ? .white.opacity(0.7) : TEColors.midGray)
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
                        .fill(isActive ? TEColors.orange : TEColors.darkGray.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(isActive ? TEColors.cream : TEColors.midGray, lineWidth: isActive ? 3 : 1)
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

// MARK: - Remote Status Bar (Dark Theme)

struct RemoteStatusBar: View {
    let hostName: String
    let presetCount: Int
    let activeIndex: Int?
    var masterVolume: Float = 1.0

    var body: some View {
        HStack(spacing: 16) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(TEColors.green)
                    .frame(width: 8, height: 8)

                Text("REMOTE")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.cream)
            }

            // Host name
            Text(hostName.uppercased())
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(TEColors.midGray)

            Spacer()

            // Master volume
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(TEColors.midGray)
                Text("\(Int(masterVolume * 100))")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.cream)
            }

            // Preset count
            if let index = activeIndex {
                Text("\(index + 1)/\(presetCount)")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(TEColors.cream)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 32)
        .background(TEColors.darkGray)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(TEColors.midGray),
            alignment: .top
        )
    }
}

// MARK: - Remote Preset Button (Simple)

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
                    .foregroundStyle(isActive ? .white : TEColors.cream)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let songName = preset.songName, !songName.isEmpty {
                    Text(songName.uppercased())
                        .font(TEFonts.mono(11, weight: .medium))
                        .foregroundStyle(isActive ? .white.opacity(0.8) : TEColors.midGray)
                }

                if let bpm = preset.bpm {
                    Text("\(bpm) BPM")
                        .font(TEFonts.mono(10, weight: .regular))
                        .foregroundStyle(isActive ? .white.opacity(0.6) : TEColors.darkGray)
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

// MARK: - Remote Layer Strip

private struct RemoteLayerStrip: View {
    let channel: RemoteChannel
    @Binding var volume: Float
    @Binding var pan: Float
    let onToggleMute: () -> Void

    private var accent: Color {
        channel.kind == .audioInput ? TEColors.blue : TEColors.orange
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(channel.name.uppercased())
                .font(TEFonts.mono(9, weight: .bold))
                .foregroundStyle(TEColors.cream)
                .lineLimit(1)
                .frame(width: 64)

            Text(channel.kind == .audioInput ? "AUDIO" : "INST")
                .font(TEFonts.mono(7, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(accent)

            RemoteFader(value: $volume)
                .frame(width: 38, height: 120)

            Text("\(Int(volume * 100))")
                .font(TEFonts.mono(11, weight: .bold))
                .foregroundStyle(TEColors.cream)
                .monospacedDigit()

            Button(action: onToggleMute) {
                Text("M")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(channel.isMuted ? .white : TEColors.red)
                    .frame(width: 36, height: 24)
                    .background(channel.isMuted ? TEColors.red : TEColors.black)
                    .overlay(Rectangle().strokeBorder(TEColors.red, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Slider(value: $pan, in: -1...1)
                .tint(accent)
                .frame(width: 62)
                .accessibilityLabel("\(channel.name) pan")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TEColors.black.opacity(0.55))
        .overlay(Rectangle().strokeBorder(TEColors.darkGray, lineWidth: 1))
    }
}

// MARK: - Preview

#Preview {
    RemoteModeView()
}
