import SwiftUI
import CoreMIDI
import CoreAudio

// MARK: - Settings Navigation

/// Settings category for sidebar navigation
enum SettingsCategory: String, CaseIterable, Identifiable {
    case midi = "MIDI"
    case audio = "Audio"
    case network = "Network"
    case mappings = "Mappings"
    case triggers = "Triggers"
    case appearance = "Appearance"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .midi: return "pianokeys"
        case .audio: return "speaker.wave.3"
        case .network: return "network"
        case .mappings: return "slider.horizontal.below.rectangle"
        case .triggers: return "bolt.circle"
        case .appearance: return "paintbrush"
        }
    }

    var description: String {
        switch self {
        case .midi: return "MIDI input/output and devices"
        case .audio: return "Audio output and engine"
        case .network: return "Network MIDI for iOS remote"
        case .mappings: return "MIDI CC mappings"
        case .triggers: return "Preset trigger mappings"
        case .appearance: return "Visual style and theme"
        }
    }
}

// MARK: - Main Settings View

/// Settings/Preferences window for the macOS app
/// Uses NavigationSplitView for proper macOS sidebar navigation
struct SettingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var audioEngine: MacAudioEngine

    @State private var selectedCategory: SettingsCategory = .midi

    var body: some View {
        NavigationSplitView {
            // Sidebar with categories
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(.body)
                        Text(category.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: category.icon)
                        .foregroundColor(.accentColor)
                }
                .tag(category)
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Detail view for selected category
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: selectedCategory.icon)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text(selectedCategory.rawValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding()

                    Divider()

                    // Content
                    settingsContent(for: selectedCategory)
                        .padding()
                }
            }
            .frame(minWidth: 450, idealWidth: 500)
        }
        .frame(minWidth: 650, idealWidth: 700, minHeight: 500, idealHeight: 600)
    }

    @ViewBuilder
    private func settingsContent(for category: SettingsCategory) -> some View {
        switch category {
        case .midi:
            MIDISettingsContent()
                .environmentObject(midiEngine)
        case .audio:
            AudioSettingsContent()
                .environmentObject(audioEngine)
        case .network:
            NetworkSettingsContent()
                .environmentObject(midiEngine)
        case .mappings:
            MIDIMappingsContent()
                .environmentObject(midiEngine)
        case .triggers:
            PresetTriggerMappingsContent()
                .environmentObject(midiEngine)
        case .appearance:
            AppearanceSettingsContent()
        }
    }
}

// MARK: - MIDI Settings Content

struct MIDISettingsContent: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Quick Actions
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Quick Actions")
                            .font(.headline)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: openMIDISetup) {
                            Label("Open Audio MIDI Setup", systemImage: "gear")
                        }
                        .help("Opens macOS Audio MIDI Setup to configure MIDI devices")

                        Button(action: { midiEngine.connectToAllSources() }) {
                            Label("Refresh Devices", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .padding(4)
            }

            // MIDI Sources
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("MIDI Sources")
                            .font(.headline)
                        Spacer()
                        Text("\(midiEngine.connectedSources.count) connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if midiEngine.connectedSources.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("No MIDI sources detected. Connect a MIDI device or enable Network MIDI.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(midiEngine.connectedSources) { source in
                                HStack(spacing: 8) {
                                    Image(systemName: source.isConnected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(source.isConnected ? .green : .secondary)
                                    Text(source.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }

            // MIDI Output
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MIDI Output")
                        .font(.headline)

                    // Helix detection
                    if let helix = midiEngine.detectedHelix {
                        HStack(spacing: 8) {
                            Image(systemName: "guitars.fill")
                                .foregroundColor(.green)
                            Text("Helix Detected: \(helix.name)")
                                .foregroundColor(.green)
                            Spacer()
                            if !midiEngine.isConnectedToHelix {
                                Button("Connect") {
                                    midiEngine.connectToHelix()
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Destination")
                                .gridColumnAlignment(.trailing)
                            Picker("", selection: $midiEngine.selectedDestinationEndpoint) {
                                Text("None").tag(nil as MIDIEndpointRef?)
                                ForEach(midiEngine.availableDestinations) { dest in
                                    HStack {
                                        if dest.name.lowercased().contains("helix") || dest.name.lowercased().contains("hx ") {
                                            Image(systemName: "guitars")
                                        }
                                        Text(dest.name)
                                    }
                                    .tag(dest.endpoint as MIDIEndpointRef?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 250)
                        }

                        GridRow {
                            Text("Channel")
                            Picker("", selection: $midiEngine.externalMIDIChannel) {
                                ForEach(1...16, id: \.self) { ch in
                                    Text("Channel \(ch)").tag(ch)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 150)
                        }

                        GridRow {
                            Text("Auto-connect")
                            Toggle("Automatically connect to Helix when detected", isOn: $midiEngine.autoConnectHelix)
                                .toggleStyle(.checkbox)
                        }
                    }

                    Button(action: { midiEngine.refreshDestinations() }) {
                        Label("Refresh Destinations", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(4)
            }

            // External Tempo Sync
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("External Tempo Sync")
                        .font(.headline)

                    Toggle("Enable Tap Tempo CC", isOn: $midiEngine.isExternalTempoSyncEnabled)
                        .toggleStyle(.checkbox)

                    if midiEngine.isExternalTempoSyncEnabled {
                        HStack {
                            Text("CC Number:")
                            Stepper(value: $midiEngine.tapTempoCC, in: 0...127) {
                                Text("\(midiEngine.tapTempoCC)")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }
                        }

                        Text("Sends tap tempo CC to sync external devices (like Helix) with preset BPM.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            // External Preset Trigger
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("External Preset Trigger")
                        .font(.headline)

                    Toggle("Enable Program Change preset selection", isOn: $midiEngine.isExternalPresetTriggerEnabled)
                        .toggleStyle(.checkbox)

                    if midiEngine.isExternalPresetTriggerEnabled {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Channel")
                                    .gridColumnAlignment(.trailing)
                                Picker("", selection: $midiEngine.externalPresetTriggerChannel) {
                                    ForEach(1...15, id: \.self) { ch in
                                        Text("Channel \(ch)").tag(ch)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 150)
                            }

                            GridRow {
                                Text("Source")
                                Picker("", selection: $midiEngine.externalPresetTriggerSource) {
                                    Text("Any Source").tag(nil as String?)
                                    ForEach(midiEngine.connectedSources) { source in
                                        Text(source.name).tag(source.name as String?)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 200)
                            }
                        }

                        Text("Program Change on this channel selects Keyframe presets and triggers external MIDI. Channel 16 is reserved for iOS remote.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            // ChordPad
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChordPad")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Source")
                                .gridColumnAlignment(.trailing)
                            Picker("", selection: $midiEngine.chordPadSourceName) {
                                Text("Disabled").tag(nil as String?)
                                ForEach(midiEngine.connectedSources) { source in
                                    Text(source.name).tag(source.name as String?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        }

                        GridRow {
                            Text("Channel")
                            Picker("", selection: $midiEngine.chordPadChannel) {
                                ForEach(1...16, id: \.self) { ch in
                                    Text("Channel \(ch)").tag(ch)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 150)
                        }
                    }
                }
                .padding(4)
            }

            Spacer()
        }
    }

    private func openMIDISetup() {
        // Open Audio MIDI Setup.app
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.audio.AudioMIDISetup") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error {
                    print("Failed to open Audio MIDI Setup: \(error)")
                }
            }
        }
    }
}

// MARK: - Audio Settings Content

struct AudioSettingsContent: View {
    @EnvironmentObject var audioEngine: MacAudioEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Engine Status
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Engine Status")
                            .font(.headline)
                        Spacer()
                        Circle()
                            .fill(audioEngine.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(audioEngine.isRunning ? "Running" : "Stopped")
                            .foregroundColor(audioEngine.isRunning ? .green : .red)
                    }

                    HStack(spacing: 16) {
                        Button(audioEngine.isRunning ? "Stop Engine" : "Start Engine") {
                            if audioEngine.isRunning {
                                audioEngine.stop()
                            } else {
                                audioEngine.start()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Panic (All Notes Off)") {
                            audioEngine.panicAllNotesOff()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("CPU Load")
                                .foregroundColor(.secondary)
                            Text("\(Int(audioEngine.cpuUsage))%")
                                .monospacedDigit()
                                .foregroundColor(audioEngine.cpuUsage > 80 ? .red : .primary)
                        }

                        GridRow {
                            Text("Peak Level")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f dB", audioEngine.peakLevel))
                                .monospacedDigit()
                        }

                        GridRow {
                            Text("Active Channels")
                                .foregroundColor(.secondary)
                            Text("\(audioEngine.channelStrips.count)")
                                .monospacedDigit()
                        }
                    }
                }
                .padding(4)
            }

            // Output Device
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Output Device")
                            .font(.headline)
                        Spacer()
                        Button(action: { audioEngine.refreshOutputDevices() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }

                    Picker("Audio Output", selection: $audioEngine.selectedOutputDeviceID) {
                        Text("System Default").tag(nil as AudioDeviceID?)
                        ForEach(audioEngine.availableOutputDevices) { device in
                            Text(device.name).tag(device.id as AudioDeviceID?)
                        }
                    }
                    .labelsHidden()

                    if let deviceID = audioEngine.selectedOutputDeviceID,
                       let device = audioEngine.availableOutputDevices.first(where: { $0.id == deviceID }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Using: \(device.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(4)
            }

            // Tempo
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tempo")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("Host Tempo")
                                .foregroundColor(.secondary)
                            HStack {
                                Text("\(Int(audioEngine.currentTempo))")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                Text("BPM")
                                    .foregroundColor(.secondary)
                            }
                        }

                        GridRow {
                            Text("Transport")
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: audioEngine.isTransportPlaying ? "play.fill" : "stop.fill")
                                    .foregroundColor(audioEngine.isTransportPlaying ? .green : .secondary)
                                Text(audioEngine.isTransportPlaying ? "Playing" : "Stopped")
                            }
                        }
                    }
                }
                .padding(4)
            }

            Spacer()
        }
    }
}

// MARK: - Network Settings Content

struct NetworkSettingsContent: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Network MIDI
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Network MIDI")
                            .font(.headline)
                        Spacer()
                        if midiEngine.isNetworkSessionEnabled {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Toggle("Enable Network MIDI Session", isOn: $midiEngine.isNetworkSessionEnabled)
                        .toggleStyle(.checkbox)

                    if midiEngine.isNetworkSessionEnabled {
                        HStack {
                            Text("Session Name:")
                                .foregroundColor(.secondary)
                            Text(midiEngine.networkSessionName)
                                .fontWeight(.medium)
                        }

                        Text("iOS devices can connect to this Mac via Network MIDI to send remote control commands.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            // iOS Remote Control Protocol
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("iOS Remote Control Protocol")
                        .font(.headline)

                    Text("When an iOS device running Keyframe connects via Network MIDI:")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        protocolRow(message: "Program Change on Ch 16", action: "Select preset by index")
                        protocolRow(message: "CC 1-99 on Ch 16", action: "Set channel volume")
                        protocolRow(message: "CC 101-199 on Ch 16", action: "Toggle channel mute")
                        protocolRow(message: "CC 120 value 1 on Ch 16", action: "Request session sync")
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
                .padding(4)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func protocolRow(message: String, action: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.accentColor)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
            Text("→")
                .foregroundColor(.secondary)
            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MIDI Mappings Content

struct MIDIMappingsContent: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @State private var selectedMapping: MIDICCMapping?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                if midiEngine.learningTarget != nil {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Learning...")
                            .foregroundColor(.orange)
                        Button("Cancel") {
                            midiEngine.cancelMIDILearn()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Spacer()

                Button("Clear All") {
                    clearAllMappings()
                }
                .disabled(midiEngine.midiMappings.isEmpty)
            }

            // Mappings list
            if midiEngine.midiMappings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No MIDI Mappings")
                        .font(.headline)
                    Text("Right-click a fader or control in the mixer to learn a MIDI CC mapping.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(midiEngine.midiMappings) { mapping in
                        MappingRow(mapping: mapping) {
                            midiEngine.removeMapping(mapping)
                        }
                    }
                }
            }

            Spacer()

            // Footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Mappings are saved with your session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(midiEngine.midiMappings.count) mapping(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func clearAllMappings() {
        let alert = NSAlert()
        alert.messageText = "Clear All MIDI Mappings?"
        alert.informativeText = "This will remove all \(midiEngine.midiMappings.count) MIDI CC mappings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            midiEngine.midiMappings.removeAll()
            MacSessionStore.shared.clearMIDIMappings()
        }
    }
}

// MARK: - Mapping Row

struct MappingRow: View {
    let mapping: MIDICCMapping
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Target icon
            targetIcon
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName)
                    .font(.body)

                HStack(spacing: 8) {
                    Text("CC \(mapping.cc)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)

                    if let ch = mapping.channel {
                        Text("Ch \(ch)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Any Ch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let source = mapping.sourceName {
                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var targetIcon: some View {
        switch mapping.target {
        case .channelVolume:
            Image(systemName: "speaker.wave.2")
                .foregroundColor(.green)
        case .channelPan:
            Image(systemName: "arrow.left.arrow.right")
                .foregroundColor(.blue)
        case .channelMute:
            Image(systemName: "speaker.slash")
                .foregroundColor(.red)
        case .masterVolume:
            Image(systemName: "speaker.wave.3")
                .foregroundColor(.purple)
        case .pluginParameter:
            Image(systemName: "dial.min")
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Preset Trigger Mappings Content

struct PresetTriggerMappingsContent: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @ObservedObject private var sessionStore = MacSessionStore.shared
    @State private var selectedMapping: PresetTriggerMapping?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                if let target = midiEngine.presetTriggerLearnTarget {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Learning '\(target.presetName)'...")
                            .foregroundColor(.orange)
                        Button("Cancel") {
                            midiEngine.cancelPresetTriggerLearn()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Spacer()

                Button("Clear All") {
                    clearAllMappings()
                }
                .disabled(midiEngine.presetTriggerMappings.isEmpty)
            }

            // Mappings list
            if midiEngine.presetTriggerMappings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Preset Triggers")
                        .font(.headline)
                    Text("MIDI Learn a preset to trigger it with a Program Change, Control Change, or Note.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to add a trigger:")
                            .font(.callout)
                            .fontWeight(.medium)
                        Text("1. Right-click a preset in the Preset Grid")
                        Text("2. Select \"Learn MIDI Trigger\"")
                        Text("3. Send a MIDI message (PC, CC, or Note)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(midiEngine.presetTriggerMappings) { mapping in
                        PresetTriggerRow(mapping: mapping) {
                            midiEngine.removePresetTriggerMapping(mapping)
                        }
                    }
                }
            }

            Spacer()

            // Quick Learn section
            if !sessionStore.currentSession.presets.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Learn")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(sessionStore.currentSession.presets.enumerated()), id: \.element.id) { index, preset in
                                    Button(action: {
                                        midiEngine.startPresetTriggerLearn(forPresetIndex: index, presetName: preset.name)
                                    }) {
                                        Text(preset.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(midiEngine.presetTriggerLearnTarget != nil)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }

            // Footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Triggers work with PC, CC (value ≥64), or Note On. Saved with session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(midiEngine.presetTriggerMappings.count) trigger(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func clearAllMappings() {
        let alert = NSAlert()
        alert.messageText = "Clear All Preset Triggers?"
        alert.informativeText = "This will remove all \(midiEngine.presetTriggerMappings.count) preset trigger mappings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            midiEngine.presetTriggerMappings.removeAll()
            MacSessionStore.shared.clearPresetTriggerMappings()
        }
    }
}

// MARK: - Preset Trigger Row

struct PresetTriggerRow: View {
    let mapping: PresetTriggerMapping
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Trigger type icon
            Image(systemName: triggerTypeIcon)
                .foregroundColor(triggerTypeColor)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(mapping.triggerDescription)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(triggerTypeColor.opacity(0.2))
                        .cornerRadius(4)

                    if let source = mapping.sourceName {
                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Any Source")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text("→ Preset \(mapping.presetIndex + 1)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var triggerTypeIcon: String {
        switch mapping.triggerType {
        case .programChange:
            return "number.circle"
        case .controlChange:
            return "dial.min"
        case .noteOn:
            return "pianokeys"
        }
    }

    private var triggerTypeColor: Color {
        switch mapping.triggerType {
        case .programChange:
            return .purple
        case .controlChange:
            return .blue
        case .noteOn:
            return .green
        }
    }
}

// MARK: - Appearance Settings Content

struct AppearanceSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Visual Style")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.title)
                            .foregroundColor(TEColors.orange)
                        VStack(alignment: .leading) {
                            Text("Keyframe Theme")
                                .font(.body.bold())
                            Text("Teenage Engineering-inspired brutalist design with cream background, orange accents, and sharp corners.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.orange)
                        Text("Light Mode")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            Spacer()
        }
    }
}

// MARK: - Legacy View Aliases (for compatibility)

typealias MIDISettingsView = MIDISettingsContent
typealias AudioSettingsView = AudioSettingsContent
typealias NetworkSettingsView = NetworkSettingsContent
typealias MIDIMappingsView = MIDIMappingsContent
typealias PresetTriggerMappingsView = PresetTriggerMappingsContent
typealias MappingRowView = MappingRow
typealias PresetTriggerMappingRowView = PresetTriggerRow
