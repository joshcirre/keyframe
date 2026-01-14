import SwiftUI

/// Grid view for selecting and managing presets (songs)
struct PresetGridView: View {
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var midiEngine: MacMIDIEngine

    @State private var showingNewPresetSheet = false
    @State private var editingPreset: MacPreset?
    @State private var presetToDelete: MacPreset?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Preset Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(sessionStore.currentSession.presets.enumerated()), id: \.element.id) { index, preset in
                        PresetCell(
                            preset: preset,
                            isSelected: sessionStore.currentPresetIndex == index,
                            presetIndex: index,
                            onSelect: { selectPreset(preset) },
                            onEdit: { editingPreset = preset },
                            onDelete: { presetToDelete = preset },
                            onLearnTrigger: { midiEngine.startPresetTriggerLearn(forPresetIndex: index, presetName: preset.name) }
                        )
                    }

                    // Add new preset button
                    addPresetButton
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingNewPresetSheet) {
            PresetEditorSheet(
                preset: nil,
                presetIndex: sessionStore.currentSession.presets.count,  // New preset will be at end
                onSave: { newPreset in
                    var session = sessionStore.currentSession
                    session.presets.append(newPreset)
                    sessionStore.currentSession = session
                    sessionStore.saveCurrentSession()
                }
            )
            .environmentObject(audioEngine)
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(
                preset: preset,
                presetIndex: sessionStore.currentSession.presets.firstIndex(where: { $0.id == preset.id }) ?? 0,
                onSave: { updatedPreset in
                    if let index = sessionStore.currentSession.presets.firstIndex(where: { $0.id == preset.id }) {
                        var session = sessionStore.currentSession
                        session.presets[index] = updatedPreset
                        sessionStore.currentSession = session
                        sessionStore.saveCurrentSession()
                    }
                }
            )
            .environmentObject(audioEngine)
        }
        .alert("Delete Preset?", isPresented: Binding(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                presetToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    deletePreset(preset)
                }
                presetToDelete = nil
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"?")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Presets")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            // Current preset info
            if let index = sessionStore.currentPresetIndex,
               index < sessionStore.currentSession.presets.count {
                let preset = sessionStore.currentSession.presets[index]
                HStack(spacing: 8) {
                    Text(preset.name)
                        .foregroundColor(.secondary)

                    if let bpm = preset.bpm {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(Int(bpm)) BPM")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    if let scale = preset.scale {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(preset.rootNote?.rawValue ?? "C") \(scale.displayName)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: { showingNewPresetSheet = true }) {
                Label("New Preset", systemImage: "plus")
            }
        }
        .padding()
    }

    // MARK: - Add Button

    private var addPresetButton: some View {
        Button(action: { showingNewPresetSheet = true }) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                Text("New Preset")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func selectPreset(_ preset: MacPreset) {
        guard let index = sessionStore.currentSession.presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }

        sessionStore.currentPresetIndex = index

        // Apply preset settings
        applyPreset(preset)
    }

    private func applyPreset(_ preset: MacPreset) {
        // Apply BPM if set
        if let bpm = preset.bpm {
            audioEngine.setTempo(bpm)
            midiEngine.currentBPM = Int(bpm)
            // Send tap tempo to external devices (Helix, etc.)
            midiEngine.sendTapTempo(bpm: Int(bpm))
        }

        // Apply scale/root if set
        if let scale = preset.scale, let rootNote = preset.rootNote {
            midiEngine.currentRootNote = rootNote.midiValue
            midiEngine.currentScaleType = scale
        }

        // Apply channel states
        for channelState in preset.channelStates {
            if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                channel.volume = channelState.volume
                channel.pan = channelState.pan
                channel.isMuted = channelState.isMuted
                channel.isSoloed = channelState.isSoloed
            }
        }

        // Send external MIDI messages to devices (Helix preset, etc.)
        midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)

        print("PresetGridView: Applied preset '\(preset.name)'")
    }

    private func deletePreset(_ preset: MacPreset) {
        sessionStore.currentSession.presets.removeAll { $0.id == preset.id }

        // Adjust current preset index if needed
        if let currentIndex = sessionStore.currentPresetIndex {
            if sessionStore.currentSession.presets.isEmpty {
                sessionStore.currentPresetIndex = nil
            } else if currentIndex >= sessionStore.currentSession.presets.count {
                sessionStore.currentPresetIndex = sessionStore.currentSession.presets.count - 1
            }
        }

        sessionStore.saveCurrentSession()
    }
}

// MARK: - Preset Cell

struct PresetCell: View {
    let preset: MacPreset
    let isSelected: Bool
    let presetIndex: Int
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onLearnTrigger: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                // Preset name
                Text(preset.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Info row
                HStack {
                    if let bpm = preset.bpm {
                        Text("\(Int(bpm))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    if let scale = preset.scale, let root = preset.rootNote {
                        Text("\(root.rawValue) \(scale.shortName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Preset")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Preset")
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: onSelect) {
                Label("Select", systemImage: "checkmark.circle")
            }

            Divider()

            Button(action: onLearnTrigger) {
                Label("Learn MIDI Trigger", systemImage: "bolt.circle")
            }

            Divider()

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preset Editor Sheet

struct PresetEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioEngine: MacAudioEngine

    let preset: MacPreset?
    let presetIndex: Int  // Index in preset list (for Helix defaults)
    let onSave: (MacPreset) -> Void

    @State private var name: String = ""
    @State private var bpm: Double = 120
    @State private var useBpm: Bool = true
    @State private var rootNote: NoteName = .c
    @State private var scale: ScaleType = .major
    @State private var useScale: Bool = false
    @State private var captureChannelStates: Bool = true
    @State private var externalMIDIMessages: [ExternalMIDIMessage] = []
    @State private var showingMIDIEditor = false
    @State private var showingHelixPicker = false

    // Current preset index for Helix defaults
    private var currentPresetIndex: Int {
        presetIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text(preset == nil ? "New Preset" : "Edit Preset")
                    .font(.headline)

                Spacer()

                Button("Save") { savePreset() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basic Info") {
                    TextField("Preset Name", text: $name)
                }

                Section("Tempo") {
                    Toggle("Set BPM", isOn: $useBpm)
                    if useBpm {
                        HStack {
                            Slider(value: $bpm, in: 40...240, step: 1)
                            TextField("", value: $bpm, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            Text("BPM")
                        }
                    }
                }

                Section("Scale Filter") {
                    Toggle("Set Scale", isOn: $useScale)
                    if useScale {
                        Picker("Root Note", selection: $rootNote) {
                            ForEach(NoteName.allCases, id: \.self) { note in
                                Text(note.rawValue).tag(note)
                            }
                        }
                        Picker("Scale", selection: $scale) {
                            ForEach(ScaleType.allCases, id: \.self) { scaleType in
                                Text(scaleType.displayName).tag(scaleType)
                            }
                        }
                    }
                }

                Section("Channel States") {
                    Toggle("Capture Current Channel States", isOn: $captureChannelStates)
                    Text("Saves volume, pan, mute, and solo settings for all channels")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("External MIDI") {
                    if externalMIDIMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No MIDI messages configured")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            // Helix quick setup if no messages yet
                            HStack {
                                Image(systemName: "guitars")
                                    .foregroundColor(.orange)
                                Text("Helix Quick Setup:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            Button(action: { applyHelixDefaults() }) {
                                Label("Use Helix Defaults (Preset \(currentPresetIndex + 1))", systemImage: "wand.and.stars")
                            }
                            .help("Adds CC32 (User 1), PC \(currentPresetIndex), CC69 (Snap 1)")
                        }
                    } else {
                        ForEach(externalMIDIMessages) { message in
                            HStack {
                                Text(message.displayDescription)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(action: { removeMessage(message) }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: { showingMIDIEditor = true }) {
                            Label("Add MIDI Message", systemImage: "plus")
                        }

                        Button(action: { showingHelixPicker = true }) {
                            Label("Add Helix Preset", systemImage: "guitars")
                        }
                        .help("Add Helix setlist/preset/snapshot messages")

                        if !externalMIDIMessages.isEmpty {
                            Button(action: { applyHelixDefaults() }) {
                                Label("Helix Defaults", systemImage: "wand.and.stars")
                            }
                            .help("Replace with Helix defaults for preset \(currentPresetIndex + 1)")
                        }
                    }

                    Text("MIDI messages sent to external devices (Helix, etc.) when this preset is selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .onAppear {
            if let preset = preset {
                name = preset.name
                externalMIDIMessages = preset.externalMIDIMessages
                if let presetBpm = preset.bpm {
                    bpm = presetBpm
                    useBpm = true
                } else {
                    useBpm = false
                }
                if let presetScale = preset.scale, let presetRoot = preset.rootNote {
                    scale = presetScale
                    rootNote = presetRoot
                    useScale = true
                } else {
                    useScale = false
                }
            }
        }
        .sheet(isPresented: $showingMIDIEditor) {
            ExternalMIDIMessageEditorSheet { newMessage in
                externalMIDIMessages.append(newMessage)
            }
        }
        .sheet(isPresented: $showingHelixPicker) {
            HelixPresetPickerSheet { helixMessages in
                externalMIDIMessages.append(contentsOf: helixMessages)
            }
        }
    }

    private func removeMessage(_ message: ExternalMIDIMessage) {
        externalMIDIMessages.removeAll { $0.id == message.id }
    }

    private func applyHelixDefaults() {
        externalMIDIMessages = ExternalMIDIMessage.helixDefaults(forPresetIndex: currentPresetIndex)
    }

    private func savePreset() {
        var channelStates: [MacChannelState] = []

        if captureChannelStates {
            for channel in audioEngine.channelStrips {
                channelStates.append(MacChannelState(
                    channelId: channel.id,
                    volume: channel.volume,
                    pan: channel.pan,
                    isMuted: channel.isMuted,
                    isSoloed: channel.isSoloed
                ))
            }
        } else if let existingPreset = preset {
            channelStates = existingPreset.channelStates
        }

        let newPreset = MacPreset(
            id: preset?.id ?? UUID(),
            name: name,
            rootNote: useScale ? rootNote : nil,
            scale: useScale ? scale : nil,
            bpm: useBpm ? bpm : nil,
            channelStates: channelStates,
            externalMIDIMessages: externalMIDIMessages
        )

        onSave(newPreset)
        dismiss()
    }
}

// MARK: - External MIDI Message Editor Sheet

struct ExternalMIDIMessageEditorSheet: View {
    @Environment(\.dismiss) var dismiss

    let onSave: (ExternalMIDIMessage) -> Void

    @State private var messageType: MIDIMessageType = .programChange
    @State private var data1: Int = 0
    @State private var data2: Int = 127

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Add MIDI Message")
                    .font(.headline)

                Spacer()

                Button("Add") { addMessage() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                Section("Message Type") {
                    Picker("Type", selection: $messageType) {
                        Text("Program Change").tag(MIDIMessageType.programChange)
                        Text("Control Change").tag(MIDIMessageType.controlChange)
                        Text("Note On").tag(MIDIMessageType.noteOn)
                        Text("Note Off").tag(MIDIMessageType.noteOff)
                    }
                }

                Section(messageType.data1Label) {
                    HStack {
                        Stepper("\(data1)", value: $data1, in: 0...127)
                        Slider(value: Binding(
                            get: { Double(data1) },
                            set: { data1 = Int($0) }
                        ), in: 0...127, step: 1)
                    }
                }

                if !messageType.data2Label.isEmpty {
                    Section(messageType.data2Label) {
                        HStack {
                            Stepper("\(data2)", value: $data2, in: 0...127)
                            Slider(value: Binding(
                                get: { Double(data2) },
                                set: { data2 = Int($0) }
                            ), in: 0...127, step: 1)
                        }
                    }
                }

                Section("Preview") {
                    Text(previewDescription)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 350, height: 350)
    }

    private var previewDescription: String {
        ExternalMIDIMessage(type: messageType, data1: data1, data2: data2).displayDescription
    }

    private func addMessage() {
        let message = ExternalMIDIMessage(type: messageType, data1: data1, data2: data2)
        onSave(message)
        dismiss()
    }
}

// MARK: - Helix Preset Picker Sheet

struct HelixPresetPickerSheet: View {
    @Environment(\.dismiss) var dismiss

    let onSave: ([ExternalMIDIMessage]) -> Void

    @State private var setlist: Int = 0
    @State private var preset: Int = 0
    @State private var snapshot: Int = 0
    @State private var includeSetlist: Bool = true
    @State private var includeSnapshot: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Helix Preset")
                    .font(.headline)

                Spacer()

                Button("Add") { addHelixPreset() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                Section("Setlist / Bank") {
                    Toggle("Include Setlist Change", isOn: $includeSetlist)

                    if includeSetlist {
                        Picker("Setlist", selection: $setlist) {
                            ForEach(HelixSetlist.allCases, id: \.rawValue) { s in
                                Text(s.displayName).tag(s.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("CC32 = \(setlist)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Preset") {
                    HStack {
                        Text("Preset Number")
                        Spacer()
                        TextField("", value: $preset, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $preset, in: 0...127)
                            .labelsHidden()
                    }

                    Slider(value: Binding(
                        get: { Double(preset) },
                        set: { preset = Int($0) }
                    ), in: 0...127, step: 1)

                    Text("PC = \(preset) (display: \(preset + 1))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Snapshot") {
                    Toggle("Include Snapshot Change", isOn: $includeSnapshot)

                    if includeSnapshot {
                        Picker("Snapshot", selection: $snapshot) {
                            ForEach(0..<8, id: \.self) { s in
                                Text("Snapshot \(s + 1)").tag(s)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("CC69 = \(snapshot)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(previewMessages, id: \.displayDescription) { msg in
                            Text(msg.displayDescription)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 480)
    }

    private var previewMessages: [ExternalMIDIMessage] {
        var messages: [ExternalMIDIMessage] = []
        if includeSetlist {
            messages.append(.helixSetlist(setlist))
        }
        messages.append(.helixPreset(preset))
        if includeSnapshot {
            messages.append(.helixSnapshot(snapshot))
        }
        return messages
    }

    private func addHelixPreset() {
        onSave(previewMessages)
        dismiss()
    }
}

// MARK: - ScaleType Extension

extension ScaleType {
    var shortName: String {
        switch self {
        case .major: return "Maj"
        case .minor: return "Min"
        case .harmonicMinor: return "HMin"
        case .melodicMinor: return "Mel"
        case .dorian: return "Dor"
        case .phrygian: return "Phr"
        case .lydian: return "Lyd"
        case .mixolydian: return "Mix"
        case .locrian: return "Loc"
        case .pentatonicMajor: return "PntM"
        case .pentatonicMinor: return "Pntm"
        case .blues: return "Blu"
        case .chromatic: return "Chr"
        }
    }
}
