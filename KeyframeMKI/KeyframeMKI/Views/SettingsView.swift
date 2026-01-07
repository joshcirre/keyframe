import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var songStore: SharedSongStore
    
    @State private var showingResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                MIDIStatusSection(midiService: midiService)
                ExternalMIDISection(midiService: midiService, songCount: songStore.songs.count)
                NM2Section(songStore: songStore)
                AUMSetupSection(nm2Channel: songStore.chordMapping.nm2Channel)
                DataSection(songCount: songStore.songs.count, showingReset: $showingResetConfirmation)
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset Songs", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { resetToSampleSongs() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all songs and restore the sample songs. This cannot be undone.")
            }
        }
    }
    
    private func resetToSampleSongs() {
        for song in songStore.songs {
            songStore.deleteSong(song)
        }
        for song in Song.sampleSongs {
            songStore.addSong(song)
        }
    }
}

// MARK: - MIDI Status Section

private struct MIDIStatusSection: View {
    @ObservedObject var midiService: MIDIService
    
    var body: some View {
        Section("MIDI Status") {
            HStack {
                Text("Virtual Source")
                Spacer()
                StatusIndicator(isActive: midiService.isInitialized)
            }
            
            if let error = midiService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button("Send Test Message") {
                midiService.sendTestMessage()
            }
        }
    }
}

private struct StatusIndicator: View {
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(isActive ? "Active" : "Error")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - External MIDI Section

private struct ExternalMIDISection: View {
    @ObservedObject var midiService: MIDIService
    let songCount: Int
    
    @State private var songSelectChannel: Int
    @State private var enableNoteSelection: Bool
    @State private var baseNote: Int
    
    init(midiService: MIDIService, songCount: Int) {
        self.midiService = midiService
        self.songCount = songCount
        _songSelectChannel = State(initialValue: Int(midiService.songSelectChannel) + 1)
        _enableNoteSelection = State(initialValue: midiService.enableNoteBasedSelection)
        _baseNote = State(initialValue: Int(midiService.songSelectBaseNote))
    }
    
    var body: some View {
        Section {
            HStack {
                Text("Virtual Input")
                Spacer()
                StatusIndicator(isActive: midiService.isListeningForInput)
            }
            
            Picker("Song Select Channel", selection: $songSelectChannel) {
                ForEach(1...16, id: \.self) { ch in
                    Text("Ch \(ch)").tag(ch)
                }
            }
            .onChange(of: songSelectChannel) { _, newValue in
                midiService.songSelectChannel = UInt8(newValue - 1)
            }
            
            Toggle("Note-Based Selection", isOn: $enableNoteSelection)
                .onChange(of: enableNoteSelection) { _, newValue in
                    midiService.enableNoteBasedSelection = newValue
                }
            
            if enableNoteSelection {
                Stepper("Base Note: \(baseNote) (\(noteNameFor(baseNote)))", value: $baseNote, in: 0...127)
                    .onChange(of: baseNote) { _, newValue in
                        midiService.songSelectBaseNote = UInt8(newValue)
                    }
            }
            
            if let lastReceived = midiService.lastReceivedMessage {
                HStack {
                    Text("Last Received")
                    Spacer()
                    Text(lastReceived)
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
        } header: {
            Text("External Song Selection")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect a MIDI controller to switch songs remotely.")
                Text("• Program Change 0–\(max(0, songCount - 1)) selects songs")
                if enableNoteSelection {
                    Text("• Note \(baseNote)–\(baseNote + max(0, songCount - 1)) selects songs")
                }
            }
            .font(.caption)
        }
    }
    
    private func noteNameFor(_ midiNote: Int) -> String {
        let noteNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let octave = (midiNote / 12) - 1
        let noteName = noteNames[midiNote % 12]
        return "\(noteName)\(octave)"
    }
}

// MARK: - NM2 Section

private struct NM2Section: View {
    @ObservedObject var songStore: SharedSongStore
    
    var body: some View {
        Section("NM2 Controller") {
            HStack {
                Text("MIDI Channel")
                Spacer()
                Text("Ch \(songStore.chordMapping.nm2Channel)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Mapped Buttons")
                Spacer()
                Text("\(songStore.chordMapping.mappedNotes.count) / 18")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - AUM Setup Section

private struct AUMSetupSection: View {
    let nm2Channel: Int
    
    var body: some View {
        Section("AUM Setup Guide") {
            VStack(alignment: .leading, spacing: 12) {
                SetupStepView(number: 1, title: "Open AUM", description: "Launch AUM and create your channel setup")
                SetupStepView(number: 2, title: "Add MIDI Source", description: "Go to MIDI Sources and add 'Keyframe MK I'")
                SetupStepView(number: 3, title: "Map CC to Controls", description: "Learn your song's CC numbers to channel faders/plugins")
                SetupStepView(number: 4, title: "Add Scale Filter", description: "Insert Scale Filter AUv3 on each MIDI track")
                SetupStepView(number: 5, title: "Set NM2 Channel", description: "Configure your NM2 to send on Ch \(nm2Channel)")
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Data Section

private struct DataSection: View {
    let songCount: Int
    @Binding var showingReset: Bool
    
    var body: some View {
        Section("Data") {
            HStack {
                Text("Songs")
                Spacer()
                Text("\(songCount)")
                    .foregroundColor(.secondary)
            }
            
            Button("Reset to Sample Songs", role: .destructive) {
                showingReset = true
            }
        }
    }
}

// MARK: - About Section

private struct AboutSection: View {
    var body: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            
            Link(destination: URL(string: "https://github.com")!) {
                HStack {
                    Text("Source Code")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Setup Step View

struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.cyan))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(MIDIService.shared)
        .environmentObject(SharedSongStore.shared)
}
