import SwiftUI

/// Main mixer window view - displays all channel strips
struct MixerView: View {
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var pluginManager: MacPluginManager

    @State private var showingAddChannel = false
    @State private var selectedChannelIndex: Int?
    @State private var showingPresetEditor = false
    @State private var showPresetGrid = false

    var body: some View {
        HSplitView {
            // Left: Mixer or Preset Grid
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Main content
                if showPresetGrid {
                    PresetGridView()
                } else {
                    HStack(spacing: 0) {
                        // Channel strips
                        channelStripsView

                        Divider()

                        // Master section
                        masterSection
                    }
                }

                Divider()

                // Status bar
                statusBarView
            }

            // Right: Channel detail (when selected)
            if let selectedIndex = selectedChannelIndex,
               selectedIndex < audioEngine.channelStrips.count {
                ChannelDetailView(
                    channel: audioEngine.channelStrips[selectedIndex],
                    config: binding(for: selectedIndex)
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        HStack {
            // View toggle
            Picker("View", selection: $showPresetGrid) {
                Image(systemName: "slider.horizontal.3")
                    .help("Mixer")
                    .tag(false)
                Image(systemName: "square.grid.2x2")
                    .help("Presets")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            Divider()
                .frame(height: 20)

            // Session name
            Text(sessionStore.currentSession.name)
                .font(.headline)

            Spacer()

            // Current preset indicator
            if let index = sessionStore.currentPresetIndex,
               index < sessionStore.currentSession.presets.count {
                let preset = sessionStore.currentSession.presets[index]
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(preset.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(4)
            }

            Spacer()

            // Add channel button (only in mixer view)
            if !showPresetGrid {
                Button(action: { addChannel() }) {
                    Image(systemName: "plus")
                }
                .help("Add Channel")
            }

            // Engine toggle
            Button(action: toggleEngine) {
                Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                    .foregroundColor(audioEngine.isRunning ? .green : .secondary)
            }
            .help(audioEngine.isRunning ? "Stop Engine" : "Start Engine")
        }
        .padding()
    }

    // MARK: - Channel Strips

    private var channelStripsView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 1) {
                ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                    ChannelStripView(
                        channel: channel,
                        config: binding(for: index),
                        isSelected: selectedChannelIndex == index,
                        onSelect: { selectedChannelIndex = index },
                        onRemove: { removeChannel(at: index) }
                    )
                }

                // Add channel placeholder
                if audioEngine.channelStrips.isEmpty {
                    emptyStateView
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Channels")
                .font(.headline)

            Text("Click + to add a channel")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Add Channel") {
                addChannel()
            }
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

    private var masterSection: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.caption)
                .foregroundColor(.secondary)

            // Master fader
            VStack {
                // Level meter
                MeterView(level: audioEngine.peakLevel)
                    .frame(width: 20, height: 150)

                // Volume slider with MIDI Learn
                Slider(value: $audioEngine.masterVolume, in: 0...1)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isLearningMaster ? Color.orange : (hasMasterMapping ? Color.blue : Color.clear), lineWidth: 2)
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
                Text("\(Int(audioEngine.masterVolume * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }

            Spacer()

            // CPU load
            VStack(spacing: 2) {
                Text("CPU")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(Int(audioEngine.cpuUsage))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(audioEngine.cpuUsage > 80 ? .red : .primary)
            }
        }
        .frame(width: 80)
        .padding()
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack {
            // Engine status
            Circle()
                .fill(audioEngine.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(audioEngine.isRunning ? "Running" : "Stopped")
                .font(.caption)

            Divider()
                .frame(height: 12)

            // MIDI activity
            if let lastActivity = midiEngine.lastActivity,
               Date().timeIntervalSince(lastActivity) < 1.0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .stroke(Color.secondary, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
            Text("MIDI: \(midiEngine.connectedSources.count) sources")
                .font(.caption)

            // MIDI Learn indicator
            if let target = midiEngine.learningTarget {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Learning: \(target.displayName)")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button(action: { midiEngine.cancelMIDILearn() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Mappings count
            if !midiEngine.midiMappings.isEmpty {
                Text("\(midiEngine.midiMappings.count) mappings")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .frame(height: 12)
            }

            // BPM
            Text("\(midiEngine.currentBPM) BPM")
                .font(.caption)
                .monospacedDigit()

            Divider()
                .frame(height: 12)

            // Scale info
            Text("\(NoteName.from(midiValue: midiEngine.currentRootNote)?.displayName ?? "?") \(midiEngine.currentScaleType.rawValue)")
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
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

// MARK: - Channel Strip View

struct ChannelStripView: View {
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @EnvironmentObject var midiEngine: MacMIDIEngine
    var isSelected: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void

    @State private var showingPluginBrowser = false
    @State private var showingPluginUI = false

    /// Check if this channel is the current MIDI learn target
    private var isLearningVolume: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .channelVolume && target.channelId == channel.id
    }

    private var isLearningPan: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .channelPan && target.channelId == channel.id
    }

    private var isLearningMute: Bool {
        guard let target = midiEngine.learningTarget else { return false }
        return target.target == .channelMute && target.channelId == channel.id
    }

    /// Check if this channel has an existing mapping for volume
    private var hasVolumeMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .channelVolume && $0.targetChannelId == channel.id }
    }

    private var hasPanMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .channelPan && $0.targetChannelId == channel.id }
    }

    private var hasMuteMapping: Bool {
        midiEngine.midiMappings.contains { $0.target == .channelMute && $0.targetChannelId == channel.id }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Channel name
            Text(config.name)
                .font(.caption)
                .lineLimit(1)

            // Instrument slot
            Button(action: { showingPluginBrowser = true }) {
                VStack {
                    if let info = channel.instrumentInfo {
                        Text(info.name)
                            .font(.caption2)
                            .lineLimit(2)
                    } else {
                        Image(systemName: "plus.circle")
                        Text("Add Inst")
                            .font(.caption2)
                    }
                }
                .frame(width: 60, height: 40)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Level meter
            MeterView(level: channel.peakLevel)
                .frame(width: 20, height: 100)

            // Volume fader with MIDI Learn context menu
            faderSection

            // Volume value
            Text("\(Int(channel.volume * 100))")
                .font(.caption)
                .monospacedDigit()

            // Mute/Solo buttons with MIDI Learn context menus
            mutesoloSection

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(width: 80)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onTapGesture { onSelect() }
        .sheet(isPresented: $showingPluginBrowser) {
            PluginBrowserView(channel: channel, config: $config)
        }
    }

    // MARK: - Fader with MIDI Learn

    private var faderSection: some View {
        VStack {
            Slider(value: $channel.volume, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 30)
                .overlay(
                    // MIDI Learn indicator
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isLearningVolume ? Color.orange : (hasVolumeMapping ? Color.blue : Color.clear), lineWidth: 2)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isLearningVolume)
                )
        }
        .contextMenu {
            if isLearningVolume {
                Button("Cancel Learn") {
                    midiEngine.cancelMIDILearn()
                }
            } else {
                Button("MIDI Learn Volume") {
                    midiEngine.startMIDILearn(for: .channelVolume(channelId: channel.id, name: config.name))
                }

                Button("MIDI Learn Pan") {
                    midiEngine.startMIDILearn(for: .channelPan(channelId: channel.id, name: config.name))
                }

                if hasVolumeMapping || hasPanMapping {
                    Divider()

                    if hasVolumeMapping {
                        Button("Clear Volume Mapping") {
                            clearMapping(for: .channelVolume)
                        }
                    }

                    if hasPanMapping {
                        Button("Clear Pan Mapping") {
                            clearMapping(for: .channelPan)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mute/Solo with MIDI Learn

    private var mutesoloSection: some View {
        HStack(spacing: 4) {
            Button(action: { channel.isMuted.toggle() }) {
                Text("M")
                    .font(.caption2.bold())
                    .frame(width: 24, height: 20)
                    .background(channel.isMuted ? Color.red : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(isLearningMute ? Color.orange : (hasMuteMapping ? Color.blue : Color.clear), lineWidth: 1)
                    )
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)
            .contextMenu {
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
                            clearMapping(for: .channelMute)
                        }
                    }
                }
            }

            Button(action: { channel.isSoloed.toggle() }) {
                Text("S")
                    .font(.caption2.bold())
                    .frame(width: 24, height: 20)
                    .background(channel.isSoloed ? Color.yellow : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func clearMapping(for targetType: MIDIMappingTarget) {
        if let mapping = midiEngine.midiMappings.first(where: {
            $0.target == targetType && $0.targetChannelId == channel.id
        }) {
            midiEngine.removeMapping(mapping)
        }
    }
}

// MARK: - Meter View

struct MeterView: View {
    let level: Float

    private let segmentCount = 8
    private let greenThreshold = -12.0
    private let yellowThreshold = -6.0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                ForEach((0..<segmentCount).reversed(), id: \.self) { index in
                    let segmentDB = dBForSegment(index)
                    let isLit = Double(level) >= segmentDB

                    Rectangle()
                        .fill(colorForSegment(index, isLit: isLit))
                        .frame(height: geometry.size.height / CGFloat(segmentCount) - 2)
                }
            }
        }
    }

    private func dBForSegment(_ index: Int) -> Double {
        // Map segments to dB range: -60 to 0
        let range = 60.0
        return -range + (Double(index) / Double(segmentCount - 1)) * range
    }

    private func colorForSegment(_ index: Int, isLit: Bool) -> Color {
        let db = dBForSegment(index)

        if !isLit {
            return Color.gray.opacity(0.3)
        }

        if db > yellowThreshold {
            return .red
        } else if db > greenThreshold {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Plugin Browser View

struct PluginBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration

    @StateObject private var pluginManager = MacPluginManager.shared

    @State private var selectedTab = 0  // 0 = instruments, 1 = effects
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Plugin Browser")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            // Tabs
            Picker("Category", selection: $selectedTab) {
                Text("Instruments").tag(0)
                Text("Effects").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Search
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            // Plugin list
            List {
                ForEach(filteredPlugins) { plugin in
                    Button(action: { loadPlugin(plugin) }) {
                        VStack(alignment: .leading) {
                            Text(plugin.name)
                                .font(.body)
                            Text(plugin.manufacturerName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 500, idealHeight: 600)
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
        if selectedTab == 0 {
            // Load instrument
            channel.loadInstrument(plugin.audioComponentDescription) { success, error in
                if success {
                    channel.instrumentInfo = MacAUInfo(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        componentType: plugin.audioComponentDescription.componentType,
                        componentSubType: plugin.audioComponentDescription.componentSubType,
                        componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                    )

                    config.instrument = MacPluginConfiguration(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        audioComponentDescription: plugin.audioComponentDescription
                    )
                }
            }
        } else {
            // Add effect
            channel.addEffect(plugin.audioComponentDescription) { success, error in
                if success {
                    let info = MacAUInfo(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        componentType: plugin.audioComponentDescription.componentType,
                        componentSubType: plugin.audioComponentDescription.componentSubType,
                        componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                    )
                    channel.effectInfos.append(info)

                    config.effects.append(MacPluginConfiguration(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        audioComponentDescription: plugin.audioComponentDescription
                    ))
                }
            }
        }

        dismiss()
    }
}
