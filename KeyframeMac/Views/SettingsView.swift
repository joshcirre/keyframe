import SwiftUI
import CoreMIDI
import CoreAudio

/// Settings/Preferences window for the macOS app
struct SettingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var audioEngine: MacAudioEngine

    var body: some View {
        TabView {
            // MIDI Settings
            MIDISettingsView()
                .environmentObject(midiEngine)
                .tabItem {
                    Label("MIDI", systemImage: "pianokeys")
                }

            // MIDI Mappings
            MIDIMappingsView()
                .environmentObject(midiEngine)
                .tabItem {
                    Label("Mappings", systemImage: "slider.horizontal.below.rectangle")
                }

            // Audio Settings
            AudioSettingsView()
                .environmentObject(audioEngine)
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.3")
                }

            // Network/Remote
            NetworkSettingsView()
                .environmentObject(midiEngine)
                .tabItem {
                    Label("Network", systemImage: "network")
                }

            // Appearance
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            // Preset Triggers
            PresetTriggerMappingsView()
                .environmentObject(midiEngine)
                .tabItem {
                    Label("Triggers", systemImage: "bolt.circle")
                }
        }
        .frame(width: 550, height: 500)
    }
}

// MARK: - MIDI Settings

struct MIDISettingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine

    var body: some View {
        Form {
            Section("MIDI Sources") {
                if midiEngine.connectedSources.isEmpty {
                    Text("No MIDI sources connected")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(midiEngine.connectedSources) { source in
                        HStack {
                            Image(systemName: source.isConnected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(source.isConnected ? .green : .secondary)
                            Text(source.name)
                        }
                    }
                }

                Button("Refresh Sources") {
                    midiEngine.connectToAllSources()
                }
            }

            Section("MIDI Output") {
                // Helix detection status
                if let helix = midiEngine.detectedHelix {
                    HStack {
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
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Picker("Destination", selection: $midiEngine.selectedDestinationEndpoint) {
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

                Picker("Channel", selection: $midiEngine.externalMIDIChannel) {
                    ForEach(1...16, id: \.self) { ch in
                        Text("Ch \(ch)").tag(ch)
                    }
                }

                Toggle("Auto-connect to Helix", isOn: $midiEngine.autoConnectHelix)
                    .help("Automatically select Helix as MIDI destination when detected")

                Button("Refresh Destinations") {
                    midiEngine.refreshDestinations()
                }
            }

            Section("External Tempo Sync") {
                Toggle("Enable Tap Tempo Sync", isOn: $midiEngine.isExternalTempoSyncEnabled)

                if midiEngine.isExternalTempoSyncEnabled {
                    Stepper("CC Number: \(midiEngine.tapTempoCC)", value: $midiEngine.tapTempoCC, in: 0...127)
                }
            }

            Section("External Preset Trigger") {
                Toggle("Enable Preset Trigger", isOn: $midiEngine.isExternalPresetTriggerEnabled)

                if midiEngine.isExternalPresetTriggerEnabled {
                    Picker("Trigger Channel", selection: $midiEngine.externalPresetTriggerChannel) {
                        ForEach(1...15, id: \.self) { ch in
                            Text("Ch \(ch)").tag(ch)
                        }
                    }
                    .help("Channel 16 is reserved for iOS remote control")

                    Picker("Source Filter", selection: $midiEngine.externalPresetTriggerSource) {
                        Text("Any Source").tag(nil as String?)
                        ForEach(midiEngine.connectedSources) { source in
                            Text(source.name).tag(source.name as String?)
                        }
                    }

                    Text("Program Change messages on this channel will select Keyframe presets and trigger external MIDI messages (Helix, etc.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("ChordPad") {
                Picker("Source", selection: $midiEngine.chordPadSourceName) {
                    Text("Disabled").tag(nil as String?)
                    ForEach(midiEngine.connectedSources) { source in
                        Text(source.name).tag(source.name as String?)
                    }
                }

                Picker("Channel", selection: $midiEngine.chordPadChannel) {
                    ForEach(1...16, id: \.self) { ch in
                        Text("Ch \(ch)").tag(ch)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Audio Settings

struct AudioSettingsView: View {
    @EnvironmentObject var audioEngine: MacAudioEngine

    var body: some View {
        Form {
            Section("Output Device") {
                Picker("Audio Output", selection: $audioEngine.selectedOutputDeviceID) {
                    Text("System Default").tag(nil as AudioDeviceID?)
                    ForEach(audioEngine.availableOutputDevices) { device in
                        Text(device.name).tag(device.id as AudioDeviceID?)
                    }
                }

                Button("Refresh Devices") {
                    audioEngine.refreshOutputDevices()
                }

                if let deviceID = audioEngine.selectedOutputDeviceID,
                   let device = audioEngine.availableOutputDevices.first(where: { $0.id == deviceID }) {
                    Text("Selected: \(device.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Engine Status") {
                HStack {
                    Circle()
                        .fill(audioEngine.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(audioEngine.isRunning ? "Running" : "Stopped")

                    Spacer()

                    Button(audioEngine.isRunning ? "Stop" : "Start") {
                        if audioEngine.isRunning {
                            audioEngine.stop()
                        } else {
                            audioEngine.start()
                        }
                    }
                }

                LabeledContent("CPU Load") {
                    Text("\(Int(audioEngine.cpuUsage))%")
                        .monospacedDigit()
                        .foregroundColor(audioEngine.cpuUsage > 80 ? .red : .primary)
                }

                LabeledContent("Peak Level") {
                    Text(String(format: "%.1f dB", audioEngine.peakLevel))
                        .monospacedDigit()
                }
            }

            Section("Tempo") {
                HStack {
                    Text("Host Tempo")
                    Spacer()
                    TextField("BPM", value: .constant(audioEngine.currentTempo), format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("BPM")
                }

                Toggle("Transport Playing", isOn: .constant(audioEngine.isTransportPlaying))
                    .disabled(true)
            }

            Section("Channels") {
                LabeledContent("Active Channels") {
                    Text("\(audioEngine.channelStrips.count)")
                }

                Button("Panic (All Notes Off)") {
                    audioEngine.panicAllNotesOff()
                }
            }
        }
        .padding()
    }
}

// MARK: - Network Settings

struct NetworkSettingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine

    var body: some View {
        Form {
            Section("Network MIDI") {
                Toggle("Enable Network MIDI Session", isOn: $midiEngine.isNetworkSessionEnabled)

                if midiEngine.isNetworkSessionEnabled {
                    LabeledContent("Session Name") {
                        Text(midiEngine.networkSessionName)
                            .foregroundColor(.secondary)
                    }

                    Text("iOS devices can connect to this Mac via Network MIDI to send remote commands.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("iOS Remote Control") {
                Text("When an iOS device connects:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• Program Change on Ch 16 → Select preset")
                    Text("• CC 1-99 on Ch 16 → Channel volume")
                    Text("• CC 101-199 on Ch 16 → Channel mute")
                    Text("• CC 120 value 1 on Ch 16 → Request session sync")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - MIDI Mappings Settings

struct MIDIMappingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @State private var selectedMapping: MIDICCMapping?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MIDI CC Mappings")
                    .font(.headline)

                Spacer()

                // Learning indicator
                if midiEngine.learningTarget != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Learning...")
                            .foregroundColor(.orange)
                        Button("Cancel") {
                            midiEngine.cancelMIDILearn()
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }

                Button(action: clearAllMappings) {
                    Text("Clear All")
                }
                .disabled(midiEngine.midiMappings.isEmpty)
            }
            .padding()

            Divider()

            // Mappings list
            if midiEngine.midiMappings.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No MIDI Mappings")
                        .font(.headline)
                    Text("Right-click a fader or control in the mixer to learn a MIDI CC mapping.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(midiEngine.midiMappings, selection: $selectedMapping) { mapping in
                    MappingRowView(mapping: mapping) {
                        midiEngine.removeMapping(mapping)
                    }
                }
            }

            Divider()

            // Footer with info
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func clearAllMappings() {
        // Show confirmation
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

// MARK: - Mapping Row View

struct MappingRowView: View {
    let mapping: MIDICCMapping
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // CC info
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName)
                    .font(.body)

                HStack(spacing: 8) {
                    // CC number
                    Text("CC \(mapping.cc)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)

                    // Channel
                    if let ch = mapping.channel {
                        Text("Ch \(ch)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Any Ch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Source
                    if let source = mapping.sourceName {
                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Target type icon
            targetIcon

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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

// MARK: - Preset Trigger Mappings View

struct PresetTriggerMappingsView: View {
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @ObservedObject private var sessionStore = MacSessionStore.shared
    @State private var selectedMapping: PresetTriggerMapping?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preset Trigger Mappings")
                    .font(.headline)

                Spacer()

                // Learning indicator
                if midiEngine.presetTriggerLearnTarget != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Learning '\(midiEngine.presetTriggerLearnTarget!.presetName)'...")
                            .foregroundColor(.orange)
                        Button("Cancel") {
                            midiEngine.cancelPresetTriggerLearn()
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }

                Button(action: clearAllMappings) {
                    Text("Clear All")
                }
                .disabled(midiEngine.presetTriggerMappings.isEmpty)
            }
            .padding()

            Divider()

            // Mappings list
            if midiEngine.presetTriggerMappings.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Preset Triggers")
                        .font(.headline)
                    Text("MIDI Learn a preset to trigger it with a Program Change, Control Change, or Note.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Divider()
                        .padding(.vertical, 8)

                    Text("How to add a trigger:")
                        .font(.caption)
                        .fontWeight(.medium)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Right-click a preset in the Preset Grid")
                        Text("2. Select \"Learn MIDI Trigger\"")
                        Text("3. Send a MIDI message (PC, CC, or Note)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(midiEngine.presetTriggerMappings, selection: $selectedMapping) { mapping in
                    PresetTriggerMappingRowView(mapping: mapping) {
                        midiEngine.removePresetTriggerMapping(mapping)
                    }
                }
            }

            Divider()

            // Footer with preset list for learning
            VStack(spacing: 8) {
                HStack {
                    Text("Quick Learn:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

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
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Info footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Mappings are saved with your session. Triggers work with PC, CC (value ≥64), or Note On.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(midiEngine.presetTriggerMappings.count) trigger(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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

// MARK: - Preset Trigger Mapping Row

struct PresetTriggerMappingRowView: View {
    let mapping: PresetTriggerMapping
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // Trigger info
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName)
                    .font(.body)

                HStack(spacing: 8) {
                    // Trigger type badge
                    HStack(spacing: 2) {
                        Image(systemName: triggerTypeIcon)
                        Text(mapping.triggerDescription)
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(triggerTypeColor.opacity(0.2))
                    .cornerRadius(4)

                    // Source
                    if let source = mapping.sourceName {
                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Any Source")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Preset index
            Text("→ Preset \(mapping.presetIndex + 1)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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
