import SwiftUI

/// Main mixer window view - displays all channel strips
struct MixerView: View {
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var pluginManager: MacPluginManager
    @ObservedObject var themeProvider: ThemeProvider = .shared

    @State private var showingAddChannel = false
    @State private var selectedChannelIndex: Int?
    @State private var showingPresetEditor = false
    @State private var showPresetGrid = false
    @State private var showingRenamePopover = false
    @State private var editingSessionName = ""
    @State private var showChannelSettings = true  // Collapsible channel settings

    private var colors: ThemeColors { themeProvider.colors }

    var body: some View {
        ZStack {
            if audioEngine.isRestoringPlugins {
                // Loading screen while restoring plugins
                LoadingScreen(progress: audioEngine.restorationProgress, colors: colors)
            } else {
                // Main content: channels + settings panel + master (always visible)
                HStack(spacing: 0) {
                    // Left: Mixer/Presets + optional channel settings
                    HSplitView {
                        // Main mixer area
                        VStack(spacing: 0) {
                            // Header
                            headerView

                            // Main content
                            if showPresetGrid {
                                PresetGridView()
                                    .background(colors.windowBackground)
                            } else {
                                GeometryReader { geometry in
                                    // Just channel strips (master moved to right)
                                    channelStripsContent(height: geometry.size.height)
                                }
                                .background(colors.windowBackground)
                            }

                            // Status bar
                            statusBarView
                        }
                        .background(colors.windowBackground)

                        // Channel detail (collapsible)
                        if showChannelSettings,
                           let selectedIndex = selectedChannelIndex,
                           selectedIndex < audioEngine.channelStrips.count {
                            ChannelDetailView(
                                channel: audioEngine.channelStrips[selectedIndex],
                                config: binding(for: selectedIndex),
                                colors: colors
                            )
                            .background(colors.windowBackground)
                        }
                    }

                    // Right: Master section (always visible)
                    GeometryReader { geometry in
                        masterSection(height: geometry.size.height)
                    }
                    .frame(width: 80)
                }
            }
        }
        .background(colors.windowBackground)
        .navigationTitle(windowTitle)
    }

    /// Window title showing document name and dirty indicator
    private var windowTitle: String {
        var title = sessionStore.currentSession.displayName
        if sessionStore.isDocumentDirty {
            title += " — Edited"
        }
        return title
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // View toggle
            HStack(spacing: 0) {
                Button(action: { showPresetGrid = false }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(TEFonts.mono(12, weight: .bold))
                        .frame(width: 36, height: 28)
                        .background(!showPresetGrid ? colors.accent : colors.controlBackground)
                        .foregroundColor(!showPresetGrid ? .white : colors.primaryText)
                }
                .buttonStyle(.plain)

                Button(action: { showPresetGrid = true }) {
                    Image(systemName: "square.grid.2x2")
                        .font(TEFonts.mono(12, weight: .bold))
                        .frame(width: 36, height: 28)
                        .background(showPresetGrid ? colors.accent : colors.controlBackground)
                        .foregroundColor(showPresetGrid ? .white : colors.primaryText)
                }
                .buttonStyle(.plain)
            }
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))

            // Session name (clickable to rename) with save button
            HStack(spacing: 6) {
                Button(action: {
                    editingSessionName = sessionStore.currentSession.name
                    showingRenamePopover = true
                }) {
                    HStack(spacing: 6) {
                        Text(sessionStore.currentSession.name.uppercased())
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(colors.primaryText)

                        if sessionStore.isDocumentDirty {
                            Circle()
                                .fill(colors.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingRenamePopover) {
                    VStack(spacing: 12) {
                        Text("SESSION NAME")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.secondaryText)

                        TextField("", text: $editingSessionName)
                            .font(TEFonts.mono(14))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .frame(width: 200)
                            .background(colors.controlBackground)
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                            .onChange(of: editingSessionName) { _, newValue in
                                let uppercased = newValue.uppercased()
                                if uppercased != newValue {
                                    editingSessionName = uppercased
                                }
                            }

                        HStack(spacing: 8) {
                            Button("CANCEL") {
                                showingRenamePopover = false
                            }
                            .font(TEFonts.mono(10, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colors.controlBackground)
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))

                            Button("SAVE") {
                                sessionStore.currentSession.name = editingSessionName
                                sessionStore.saveCurrentSession()
                                showingRenamePopover = false
                            }
                            .font(TEFonts.mono(10, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(.white)
                            .background(colors.accent)
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(colors.windowBackground)
                }

                // Compact save button
                CompactSaveButton(
                    isDirty: sessionStore.isDocumentDirty,
                    colors: colors,
                    onSave: { sessionStore.saveCurrentSession() }
                )
            }

            Spacer()

            // Current preset indicator
            if let index = sessionStore.currentPresetIndex,
               index < sessionStore.currentSession.presets.count {
                let preset = sessionStore.currentSession.presets[index]
                HStack(spacing: 6) {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 8, height: 8)
                    Text(preset.name.uppercased())
                        .font(TEFonts.mono(12, weight: .medium))
                        .foregroundColor(colors.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colors.accent.opacity(0.15))
                .overlay(Rectangle().strokeBorder(colors.accent, lineWidth: 1))
            }

            Spacer()

            // Add channel button (only in mixer view)
            if !showPresetGrid {
                Button(action: { addChannel() }) {
                    Image(systemName: "plus")
                        .font(TEFonts.mono(14, weight: .bold))
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.plain)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                .help("Add Channel")
            }

            // Toggle channel settings sidebar
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showChannelSettings.toggle() } }) {
                Image(systemName: "sidebar.trailing")
                    .font(TEFonts.mono(14, weight: .bold))
                    .frame(width: 32, height: 28)
                    .foregroundColor(showChannelSettings ? colors.accent : colors.secondaryText)
            }
            .buttonStyle(.plain)
            .background(showChannelSettings ? colors.accent.opacity(0.15) : colors.controlBackground)
            .overlay(Rectangle().strokeBorder(showChannelSettings ? colors.accent : colors.border, lineWidth: colors.borderWidth))
            .help(showChannelSettings ? "Hide Channel Settings" : "Show Channel Settings")

            // Engine toggle
            Button(action: toggleEngine) {
                Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                    .font(TEFonts.mono(14, weight: .bold))
                    .frame(width: 32, height: 28)
                    .foregroundColor(audioEngine.isRunning ? colors.success : colors.secondaryText)
            }
            .buttonStyle(.plain)
            .background(colors.controlBackground)
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            .help(audioEngine.isRunning ? "Stop Engine" : "Start Engine")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)
    }

    // MARK: - Channel Strips

    private func channelStripsContent(height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                    TEChannelStripView(
                        channel: channel,
                        config: binding(for: index),
                        isSelected: selectedChannelIndex == index,
                        onSelect: { selectedChannelIndex = index },
                        onRemove: { removeChannel(at: index) },
                        colors: colors,
                        containerHeight: height - 24  // Account for padding
                    )
                }

                // Add channel placeholder
                if audioEngine.channelStrips.isEmpty {
                    emptyStateView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: height)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(colors.secondaryText)

            Text("NO CHANNELS")
                .font(TEFonts.mono(14, weight: .bold))
                .foregroundColor(colors.primaryText)

            Text("Click + to add a channel")
                .font(TEFonts.mono(11))
                .foregroundColor(colors.secondaryText)

            Button("ADD CHANNEL") {
                addChannel()
            }
            .font(TEFonts.mono(11, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colors.accent)
            .foregroundColor(.white)
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
        }
        .frame(minWidth: 200, minHeight: 300)
        .padding()
    }

    // MARK: - Master Section

    /// Check if master volume is being learned
    private var isLearningMaster: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .masterVolume
    }

    private var hasMasterMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .masterVolume }
    }

    private func masterSection(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Top section (fixed)
            Text("MASTER")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)
                .padding(.bottom, 8)

            // Level meter (stretches)
            TEMeterView(level: audioEngine.peakLevel, colors: colors)
                .frame(width: 24)
                .frame(maxHeight: .infinity)

            // Bottom section (fixed)
            VStack(spacing: 8) {
                // Master fader - vertical
                TEVerticalFader(value: $audioEngine.masterVolume, colors: colors)
                    .frame(width: 44, height: 160)
                    .overlay(
                        Rectangle()
                            .strokeBorder(isLearningMaster ? colors.accent : (hasMasterMapping ? Color.blue : Color.clear), lineWidth: 2)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isLearningMaster)
                    )
                    .contextMenu {
                        if isLearningMaster {
                            Button("Cancel Learn") {
                                midiEngine.cancelMIDILearn()
                            }
                        } else {
                            Button("MIDI Learn Master Volume") {
                                midiEngine.startMIDILearn(for: .masterVolume)
                            }

                            if hasMasterMapping {
                                Button("Clear Master Mapping") {
                                    if let mapping = midiEngine.midiMappings.first(where: { $0.target == .masterVolume }) {
                                        midiEngine.removeMapping(mapping)
                                    }
                                }
                            }
                        }
                    }

                // Volume label
                Text("\(Int(audioEngine.masterVolume * 100))")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(colors.primaryText)
                    .monospacedDigit()

                // CPU load
                VStack(spacing: 2) {
                    Text("CPU")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(colors.secondaryText)
                    Text("\(Int(audioEngine.cpuUsage))%")
                        .font(TEFonts.mono(11, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(audioEngine.cpuUsage > 80 ? colors.error : colors.primaryText)
                }
            }
            .padding(.top, 8)
        }
        .frame(width: 80, height: height - 24)  // Account for padding
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(width: colors.borderWidth).foregroundColor(colors.border), alignment: .leading)
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack(spacing: 12) {
            // Engine status
            Circle()
                .fill(audioEngine.isRunning ? colors.success : colors.error)
                .frame(width: 8, height: 8)
            Text(audioEngine.isRunning ? "RUNNING" : "STOPPED")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(colors.primaryText)

            Rectangle()
                .fill(colors.border)
                .frame(width: 1, height: 12)

            // MIDI activity
            if let lastActivity = midiEngine.lastActivity,
               Date().timeIntervalSince(lastActivity) < 1.0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .stroke(colors.secondaryText, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
            Text("MIDI: \(midiEngine.connectedSources.count)")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(colors.primaryText)

            // MIDI Learn indicator
            if let target = midiEngine.learningTarget {
                Rectangle()
                    .fill(colors.border)
                    .frame(width: 1, height: 12)

                HStack(spacing: 4) {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 8, height: 8)
                    Text("LEARNING: \(target.displayName)")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.accent)

                    Button(action: { midiEngine.cancelMIDILearn() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(colors.secondaryText)
                }
            }

            Spacer()

            // Mappings count
            if !midiEngine.midiMappings.isEmpty {
                Text("\(midiEngine.midiMappings.count) MAPPINGS")
                    .font(TEFonts.mono(10))
                    .foregroundColor(colors.secondaryText)

                Rectangle()
                    .fill(colors.border)
                    .frame(width: 1, height: 12)
            }

            // BPM
            Text("\(midiEngine.currentBPM) BPM")
                .font(TEFonts.mono(11, weight: .bold))
                .monospacedDigit()
                .foregroundColor(colors.primaryText)

            Rectangle()
                .fill(colors.border)
                .frame(width: 1, height: 12)

            // Scale info
            Text("\(NoteName.from(midiValue: midiEngine.currentRootNote)?.displayName ?? "?") \(midiEngine.currentScaleType.rawValue)")
                .font(TEFonts.mono(11, weight: .medium))
                .foregroundColor(colors.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .top)
    }

    // MARK: - Actions

    private func toggleEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        } else {
            audioEngine.start()
        }
    }

    private func addChannel() {
        guard audioEngine.addChannel() != nil else { return }

        let config = MacChannelConfiguration(
            name: "Channel \(audioEngine.channelStrips.count)"
        )
        sessionStore.addChannel(config)

        // Select the new channel
        selectedChannelIndex = audioEngine.channelStrips.count - 1
    }

    private func removeChannel(at index: Int) {
        audioEngine.removeChannel(at: index)
        sessionStore.removeChannel(at: index)

        if selectedChannelIndex == index {
            selectedChannelIndex = nil
        } else if let selected = selectedChannelIndex, selected > index {
            selectedChannelIndex = selected - 1
        }
    }

    private func binding(for index: Int) -> Binding<MacChannelConfiguration> {
        Binding(
            get: {
                guard index < sessionStore.currentSession.channels.count else {
                    return MacChannelConfiguration(name: "Channel \(index + 1)")
                }
                return sessionStore.currentSession.channels[index]
            },
            set: { newValue in
                sessionStore.updateChannel(newValue)
            }
        )
    }
}

// MARK: - TE Channel Strip View

struct TEChannelStripView: View {
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @EnvironmentObject var midiEngine: MacMIDIEngine
    var isSelected: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void
    let colors: ThemeColors
    var containerHeight: CGFloat? = nil  // Optional height to stretch to

    @State private var showingPluginBrowser = false

    /// Check if this channel is the current MIDI learn target
    private var isLearningVolume: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .channelVolume && target.channelId == channel.id
    }

    private var isLearningMute: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .channelMute && target.channelId == channel.id
    }

    private var hasVolumeMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .channelVolume && $0.targetChannelId == channel.id }
    }

    private var hasMuteMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .channelMute && $0.targetChannelId == channel.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section (fixed height)
            VStack(spacing: 6) {
                channelNameView
                instrumentSlotView
            }
            .padding(.bottom, 6)

            // Meter section (stretches to fill available space)
            stretchingMeterView

            // Bottom section (fixed height)
            VStack(spacing: 6) {
                volumeFaderView
                volumeValueView
                muteSoloButtons
                removeButton
            }
            .padding(.top, 6)
        }
        .padding(8)
        .frame(width: 72, height: containerHeight)
        .background(isSelected ? colors.accent.opacity(0.1) : colors.controlBackground)
        .overlay(Rectangle().strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: colors.borderWidth))
        .onTapGesture { onSelect() }
        .sheet(isPresented: $showingPluginBrowser) {
            PluginBrowserView(channel: channel, config: $config)
        }
    }

    // Meter that stretches to fill available space
    private var stretchingMeterView: some View {
        GeometryReader { geometry in
            TEMeterView(level: channel.peakLevel, colors: colors)
                .frame(width: 20, height: geometry.size.height)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Subviews

    private var channelNameView: some View {
        Text(config.name.uppercased())
            .font(TEFonts.mono(10, weight: .bold))
            .foregroundColor(colors.primaryText)
            .lineLimit(1)
            .frame(width: 56)
    }

    private var instrumentSlotView: some View {
        Button(action: instrumentSlotAction) {
            VStack(spacing: 2) {
                if let info = channel.instrumentInfo {
                    Text(info.name)
                        .font(TEFonts.mono(8))
                        .lineLimit(2)
                        .foregroundColor(colors.primaryText)
                } else {
                    Image(systemName: "plus")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(colors.secondaryText)
                }
            }
            .frame(width: 56, height: 32)
            .background(colors.controlBackground)
            .overlay(
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: colors.borderWidth, dash: channel.instrumentInfo == nil ? [4, 2] : []))
                    .foregroundColor(colors.border)
            )
        }
        .buttonStyle(.plain)
    }

    private func instrumentSlotAction() {
        if channel.isInstrumentLoaded {
            // Open plugin editor window
            PluginWindowManager.shared.openInstrumentEditor(for: channel, channelName: config.name)
        } else {
            // Show plugin browser to add instrument
            showingPluginBrowser = true
        }
    }

    private var volumeFaderView: some View {
        TEVerticalFader(value: $channel.volume, colors: colors)
            .frame(width: 44, height: 160)
            .overlay(
                Rectangle()
                    .strokeBorder(isLearningVolume ? colors.accent : (hasVolumeMapping ? Color.blue : Color.clear), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isLearningVolume)
            )
            .contextMenu {
                volumeContextMenu
            }
    }

    @ViewBuilder
    private var volumeContextMenu: some View {
        if isLearningVolume {
            Button("Cancel Learn") {
                midiEngine.cancelMIDILearn()
            }
        } else {
            Button("MIDI Learn Volume") {
                midiEngine.startMIDILearn(for: .channelVolume(channelId: channel.id, name: config.name))
            }

            if hasVolumeMapping {
                Button("Clear Volume Mapping") {
                    if let mapping = midiEngine.midiMappings.first(where: {
                        $0.target == .channelVolume && $0.targetChannelId == channel.id
                    }) {
                        midiEngine.removeMapping(mapping)
                    }
                }
            }
        }
    }

    private var volumeValueView: some View {
        Text("\(Int(channel.volume * 100))")
            .font(TEFonts.mono(12, weight: .bold))
            .foregroundColor(colors.primaryText)
            .monospacedDigit()
    }

    private var muteSoloButtons: some View {
        HStack(spacing: 4) {
            muteButton
            soloButton
        }
    }

    private var muteButton: some View {
        Button(action: { channel.isMuted.toggle() }) {
            Text("M")
                .font(TEFonts.mono(10, weight: .bold))
                .frame(width: 24, height: 22)
                .background(channel.isMuted ? colors.error : colors.controlBackground)
                .foregroundColor(channel.isMuted ? .white : colors.primaryText)
                .overlay(
                    Rectangle()
                        .strokeBorder(isLearningMute ? colors.accent : (hasMuteMapping ? Color.blue : colors.border), lineWidth: colors.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            muteContextMenu
        }
    }

    @ViewBuilder
    private var muteContextMenu: some View {
        if isLearningMute {
            Button("Cancel Learn") {
                midiEngine.cancelMIDILearn()
            }
        } else {
            Button("MIDI Learn Mute") {
                midiEngine.startMIDILearn(for: .channelMute(channelId: channel.id, name: config.name))
            }

            if hasMuteMapping {
                Button("Clear Mute Mapping") {
                    if let mapping = midiEngine.midiMappings.first(where: {
                        $0.target == .channelMute && $0.targetChannelId == channel.id
                    }) {
                        midiEngine.removeMapping(mapping)
                    }
                }
            }
        }
    }

    private var soloButton: some View {
        Button(action: { channel.isSoloed.toggle() }) {
            Text("S")
                .font(TEFonts.mono(10, weight: .bold))
                .frame(width: 24, height: 22)
                .background(channel.isSoloed ? colors.warning : colors.controlBackground)
                .foregroundColor(channel.isSoloed ? TEColors.black : colors.primaryText)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
        }
        .buttonStyle(.plain)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "trash")
                .font(TEFonts.mono(10))
                .foregroundColor(colors.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TE Vertical Fader

struct TEVerticalFader: View {
    @Binding var value: Float
    let colors: ThemeColors

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)  // Avoid division by zero
            let safeValue = value.isFinite ? value : 0

            ZStack(alignment: .bottom) {
                // Track background
                Rectangle()
                    .fill(colors.controlBackground)

                // Fill
                Rectangle()
                    .fill(colors.accent)
                    .frame(height: max(0, height * CGFloat(safeValue)))

                // Handle line
                Rectangle()
                    .fill(colors.border)
                    .frame(height: 4)
                    .offset(y: -height * CGFloat(safeValue) + 2)
            }
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = 1.0 - Float(gesture.location.y / height)
                        value = max(0, min(1, newValue))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}

// MARK: - TE Meter View

struct TEMeterView: View {
    let level: Float
    let colors: ThemeColors

    private let segmentCount = 12

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)  // Avoid division by zero
            let safeLevel = level.isFinite ? level : 0

            VStack(spacing: 1) {
                ForEach((0..<segmentCount).reversed(), id: \.self) { index in
                    let segmentDB = dBForSegment(index)
                    let isLit = Double(safeLevel) >= segmentDB

                    Rectangle()
                        .fill(colorForSegment(index, isLit: isLit))
                        .frame(height: max(0, height / CGFloat(segmentCount) - 1))
                }
            }
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
        }
    }

    private func dBForSegment(_ index: Int) -> Double {
        let range = 60.0
        return -range + (Double(index) / Double(segmentCount - 1)) * range
    }

    private func colorForSegment(_ index: Int, isLit: Bool) -> Color {
        let db = dBForSegment(index)

        if !isLit {
            return colors.controlBackground
        }

        if db > -6 {
            return colors.error
        } else if db > -12 {
            return colors.warning
        } else {
            return colors.success
        }
    }
}

// MARK: - Plugin Browser View (keep existing, just style it)

struct PluginBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @ObservedObject var themeProvider: ThemeProvider = .shared

    @StateObject private var pluginManager = MacPluginManager.shared

    @State private var selectedTab = 0
    @State private var searchText = ""

    private var colors: ThemeColors { themeProvider.colors }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PLUGIN BROWSER")
                    .font(TEFonts.mono(14, weight: .bold))
                    .foregroundColor(colors.primaryText)
                Spacer()
                Button("DONE") { dismiss() }
                    .font(TEFonts.mono(11, weight: .bold))
            }
            .padding()
            .background(colors.sectionBackground)

            // Tabs
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    Text("INSTRUMENTS")
                        .font(TEFonts.mono(11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == 0 ? colors.accent : colors.controlBackground)
                        .foregroundColor(selectedTab == 0 ? .white : colors.primaryText)
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = 1 }) {
                    Text("EFFECTS")
                        .font(TEFonts.mono(11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == 1 ? colors.accent : colors.controlBackground)
                        .foregroundColor(selectedTab == 1 ? .white : colors.primaryText)
                }
                .buttonStyle(.plain)
            }
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            .padding(.horizontal)

            // Search
            TextField("SEARCH", text: $searchText)
                .font(TEFonts.mono(12))
                .textFieldStyle(.plain)
                .padding(8)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                .padding()

            // Plugin list
            List {
                ForEach(filteredPlugins) { plugin in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                                .font(TEFonts.mono(12, weight: .medium))
                                .foregroundColor(colors.primaryText)
                            Text(plugin.manufacturerName)
                                .font(TEFonts.mono(10))
                                .foregroundColor(colors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        loadPlugin(plugin)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 500, idealHeight: 600)
        .background(colors.windowBackground)
    }

    private var filteredPlugins: [MacPluginInfo] {
        let plugins = selectedTab == 0 ? pluginManager.availableInstruments : pluginManager.availableEffects

        if searchText.isEmpty {
            return plugins
        }

        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manufacturerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadPlugin(_ plugin: MacPluginInfo) {
        let configBinding = $config
        let channelName = config.name

        if selectedTab == 0 {
            channel.loadInstrument(plugin.audioComponentDescription) { [channel] success, error in
                if success {
                    DispatchQueue.main.async {
                        channel.instrumentInfo = MacAUInfo(
                            name: plugin.name,
                            manufacturerName: plugin.manufacturerName,
                            componentType: plugin.audioComponentDescription.componentType,
                            componentSubType: plugin.audioComponentDescription.componentSubType,
                            componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                        )

                        configBinding.wrappedValue.instrument = MacPluginConfiguration(
                            name: plugin.name,
                            manufacturerName: plugin.manufacturerName,
                            audioComponentDescription: plugin.audioComponentDescription
                        )

                        // Auto-open the plugin editor window
                        PluginWindowManager.shared.openInstrumentEditor(
                            for: channel,
                            channelName: channelName
                        )
                    }
                }
            }
        } else {
            channel.addEffect(plugin.audioComponentDescription) { [channel] success, error in
                if success {
                    DispatchQueue.main.async {
                        let info = MacAUInfo(
                            name: plugin.name,
                            manufacturerName: plugin.manufacturerName,
                            componentType: plugin.audioComponentDescription.componentType,
                            componentSubType: plugin.audioComponentDescription.componentSubType,
                            componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                        )
                        channel.effectInfos.append(info)

                        configBinding.wrappedValue.effects.append(MacPluginConfiguration(
                            name: plugin.name,
                            manufacturerName: plugin.manufacturerName,
                            audioComponentDescription: plugin.audioComponentDescription
                        ))

                        // Auto-open the effect editor window
                        let effectIndex = channel.effects.count - 1
                        PluginWindowManager.shared.openEffectEditor(
                            for: channel,
                            effectIndex: effectIndex,
                            channelName: channelName
                        )
                    }
                }
            }
        }

        dismiss()
    }
}

// MARK: - Compact Save Button (for header)

struct CompactSaveButton: View {
    let isDirty: Bool
    let colors: ThemeColors
    let onSave: () -> Void

    @State private var showSavedFeedback = false

    var body: some View {
        Button(action: {
            onSave()

            // Show "saved" feedback
            withAnimation(.easeInOut(duration: 0.15)) {
                showSavedFeedback = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSavedFeedback = false
                }
            }
        }) {
            Image(systemName: showSavedFeedback ? "checkmark" : "square.and.arrow.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(showSavedFeedback ? colors.success : (isDirty ? colors.accent : colors.secondaryText))
        }
        .buttonStyle(.plain)
        .help(isDirty ? "Save Session (unsaved changes)" : "Save Session")
    }
}

// MARK: - Loading Screen

/// Loading screen displayed during app startup while plugins are being restored
struct LoadingScreen: View {
    let progress: String
    let colors: ThemeColors

    @State private var dotCount = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            colors.windowBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                // Logo
                VStack(spacing: 8) {
                    Text("KEYFRAME")
                        .font(TEFonts.display(32, weight: .black))
                        .foregroundColor(colors.primaryText)
                        .tracking(6)
                        .scaleEffect(logoScale)

                    Rectangle()
                        .fill(colors.accent)
                        .frame(width: 120, height: 4)
                }

                // Loading indicator
                VStack(spacing: 16) {
                    // Animated dots
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index <= dotCount ? colors.accent : colors.secondaryText.opacity(0.3))
                                .frame(width: 10, height: 10)
                        }
                    }

                    // Progress text
                    Text(progress.isEmpty ? "INITIALIZING" : progress.uppercased())
                        .font(TEFonts.mono(11, weight: .medium))
                        .foregroundColor(colors.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: 280)
                }
            }
        }
        .onAppear {
            // Animate logo scale
            withAnimation(.easeOut(duration: 0.5)) {
                logoScale = 1.0
            }

            // Animate loading dots
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    dotCount = (dotCount + 1) % 4
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
