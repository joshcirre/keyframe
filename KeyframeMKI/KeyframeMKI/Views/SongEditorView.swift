import SwiftUI

struct SongEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var songStore: SharedSongStore
    
    @State var song: Song
    let isNewSong: Bool
    
    @State private var showingDeleteConfirmation = false
    @State private var showingAddControl = false
    @State private var editingControl: MIDIControl?
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section("Song Info") {
                    TextField("Song Name", text: $song.name)
                        .textInputAutocapitalization(.words)
                }
                
                // Key Section
                Section("Key") {
                    Picker("Root Note", selection: $song.rootNote) {
                        ForEach(NoteName.allCases) { note in
                            Text(note.displayName).tag(note.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Scale", selection: $song.scaleType) {
                        ForEach(ScaleType.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Preview of diatonic chords
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diatonic Chords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(zip(song.romanNumerals, song.diatonicChords).enumerated()), id: \.offset) { _, chord in
                                    VStack(spacing: 2) {
                                        Text(chord.0)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(chord.1)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.cyan.opacity(0.1))
                                    )
                                }
                            }
                        }
                    }
                }
                
                // Filter Mode Section
                Section("Scale Filter Mode") {
                    Picker("Mode", selection: $song.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.rawValue)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(song.filterMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // BPM Section
                Section {
                    Toggle("Send BPM", isOn: Binding(
                        get: { song.bpm != nil },
                        set: { enabled in
                            if enabled {
                                song.bpm = 120 // Default BPM
                            } else {
                                song.bpm = nil
                            }
                        }
                    ))
                    
                    if song.bpm != nil {
                        Stepper(
                            "BPM: \(song.bpm ?? 120)",
                            value: Binding(
                                get: { song.bpm ?? 120 },
                                set: { song.bpm = $0 }
                            ),
                            in: 40...240
                        )
                        
                        HStack {
                            Text("Common Tempos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            ForEach([80, 100, 120, 140], id: \.self) { tempo in
                                Button("\(tempo)") {
                                    song.bpm = tempo
                                }
                                .buttonStyle(.bordered)
                                .tint(song.bpm == tempo ? .purple : .gray)
                            }
                        }
                        
                        // BPM MIDI Settings
                        DisclosureGroup("MIDI Settings") {
                            Stepper("CC Number: \(song.bpmCC)", value: $song.bpmCC, in: 0...127)
                            
                            Picker("MIDI Channel", selection: $song.bpmChannel) {
                                ForEach(1...16, id: \.self) { ch in
                                    Text("Ch \(ch)").tag(ch)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tempo")
                } footer: {
                    Text("BPM is sent as a CC message when this song is selected. Value is clamped to 0-127 for MIDI.")
                }
                
                // MIDI Controls Section - Faders
                Section {
                    if song.preset.faders.isEmpty {
                        Text("No faders configured")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(song.preset.faders) { control in
                            MIDIControlRow(
                                control: binding(for: control),
                                onEdit: { editingControl = control },
                                onDelete: { song.preset.removeControl(id: control.id) }
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Faders")
                        Spacer()
                        Button {
                            showingAddControl = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                } footer: {
                    Text("Each fader sends a CC value (0-127) to AUM")
                }
                
                // MIDI Controls Section - Toggles (Plugin Bypass)
                Section {
                    if song.preset.toggles.isEmpty {
                        Text("No toggles configured")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(song.preset.toggles) { control in
                            MIDIToggleRow(
                                control: binding(for: control),
                                onEdit: { editingControl = control },
                                onDelete: { song.preset.removeControl(id: control.id) }
                            )
                        }
                    }
                } header: {
                    Text("Plugin Toggles")
                } footer: {
                    Text("Each toggle sends CC 0 (OFF) or 127 (ON)")
                }
                
                // Quick Add Section
                Section("Quick Add") {
                    Button {
                        addQuickFader()
                    } label: {
                        Label("Add Channel Fader", systemImage: "slider.horizontal.3")
                    }
                    
                    Button {
                        addQuickToggle()
                    } label: {
                        Label("Add Plugin Toggle", systemImage: "power.circle")
                    }
                }
                
                // Delete Section (only for existing songs)
                if !isNewSong {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Song")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNewSong ? "New Song" : "Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSong()
                    }
                    .fontWeight(.semibold)
                    .disabled(song.name.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddControl) {
                AddControlSheet(preset: $song.preset)
            }
            .sheet(item: $editingControl) { control in
                EditControlSheet(preset: $song.preset, control: control)
            }
            .confirmationDialog(
                "Delete Song",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    songStore.deleteSong(song)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete '\(song.name)'? This cannot be undone.")
            }
        }
    }
    
    private func saveSong() {
        if isNewSong {
            songStore.addSong(song)
        } else {
            songStore.updateSong(song)
        }
        dismiss()
    }
    
    private func binding(for control: MIDIControl) -> Binding<MIDIControl> {
        Binding(
            get: { song.preset.controls.first { $0.id == control.id } ?? control },
            set: { newValue in
                if let index = song.preset.controls.firstIndex(where: { $0.id == control.id }) {
                    song.preset.controls[index] = newValue
                }
            }
        )
    }
    
    private func addQuickFader() {
        let nextNumber = song.preset.faders.count + 1
        let nextCC = 70 + song.preset.faders.count
        let control = MIDIControl(
            name: "Channel \(nextNumber)",
            ccNumber: nextCC,
            value: 100,
            controlType: .fader
        )
        song.preset.addControl(control)
    }
    
    private func addQuickToggle() {
        let nextNumber = song.preset.toggles.count + 1
        let nextCC = 80 + song.preset.toggles.count
        let control = MIDIControl(
            name: "Plugin \(nextNumber)",
            ccNumber: nextCC,
            value: 0,
            controlType: .toggle
        )
        song.preset.addControl(control)
    }
}

// MARK: - MIDI Control Row (Fader)

struct MIDIControlRow: View {
    @Binding var control: MIDIControl
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("CC \(control.ccNumber) • Ch \(control.midiChannel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(control.percentage)%")
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                
                Menu {
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.gray)
                }
            }
            
            Slider(value: Binding(
                get: { Double(control.value) },
                set: { control.value = Int($0) }
            ), in: 0...127, step: 1)
            .tint(.cyan)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MIDI Toggle Row

struct MIDIToggleRow: View {
    @Binding var control: MIDIControl
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button {
                control.isOn.toggle()
            } label: {
                HStack {
                    Image(systemName: control.isOn ? "power.circle.fill" : "power.circle")
                        .foregroundColor(control.isOn ? .green : .gray)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(control.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("CC \(control.ccNumber) • Ch \(control.midiChannel)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(control.isOn ? "ON" : "OFF")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(control.isOn ? .green : .gray)
                }
            }
            .buttonStyle(.plain)
            
            Menu {
                Button { onEdit() } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Control Sheet

struct AddControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preset: MIDIPreset
    
    @State private var name: String = ""
    @State private var ccNumber: Int = 70
    @State private var midiChannel: Int = 1
    @State private var controlType: MIDIControl.ControlType = .fader
    @State private var value: Int = 100
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Control Info") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    Picker("Type", selection: $controlType) {
                        Text("Fader").tag(MIDIControl.ControlType.fader)
                        Text("Toggle").tag(MIDIControl.ControlType.toggle)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("MIDI Settings") {
                    Stepper("CC Number: \(ccNumber)", value: $ccNumber, in: 0...127)
                    
                    Picker("MIDI Channel", selection: $midiChannel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("Ch \(ch)").tag(ch)
                        }
                    }
                }
                
                Section("Initial Value") {
                    if controlType == .fader {
                        VStack {
                            Slider(value: Binding(
                                get: { Double(value) },
                                set: { value = Int($0) }
                            ), in: 0...127, step: 1)
                            .tint(.cyan)
                            
                            Text("\(Int(Double(value) / 127.0 * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Toggle("Start ON", isOn: Binding(
                            get: { value >= 64 },
                            set: { value = $0 ? 127 : 0 }
                        ))
                    }
                }
            }
            .navigationTitle("Add Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let control = MIDIControl(
                            name: name.isEmpty ? (controlType == .fader ? "Fader" : "Toggle") : name,
                            ccNumber: ccNumber,
                            midiChannel: midiChannel,
                            value: value,
                            controlType: controlType
                        )
                        preset.addControl(control)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Edit Control Sheet

struct EditControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preset: MIDIPreset
    let control: MIDIControl
    
    @State private var name: String = ""
    @State private var ccNumber: Int = 70
    @State private var midiChannel: Int = 1
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Control Info") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                
                Section("MIDI Settings") {
                    Stepper("CC Number: \(ccNumber)", value: $ccNumber, in: 0...127)
                    
                    Picker("MIDI Channel", selection: $midiChannel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("Ch \(ch)").tag(ch)
                        }
                    }
                }
            }
            .navigationTitle("Edit Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = preset.controls.firstIndex(where: { $0.id == control.id }) {
                            preset.controls[index].name = name
                            preset.controls[index].ccNumber = ccNumber
                            preset.controls[index].midiChannel = midiChannel
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = control.name
                ccNumber = control.ccNumber
                midiChannel = control.midiChannel
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    SongEditorView(song: Song.sampleSongs[0], isNewSong: false)
        .environmentObject(SharedSongStore.shared)
}
