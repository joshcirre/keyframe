import SwiftUI

struct ContentView: View {
    @EnvironmentObject var songStore: SharedSongStore
    @EnvironmentObject var midiService: MIDIService
    
    @State private var showingSettings = false
    @State private var showingSongEditor = false
    @State private var showingChordMap = false
    @State private var editingSong: Song?
    @State private var showingAddSong = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.12),
                        Color(red: 0.02, green: 0.02, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Active song header
                    if let activeSong = songStore.activeSong {
                        ActiveSongHeader(song: activeSong)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    // Song grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(songStore.songs) { song in
                                SongButton(
                                    song: song,
                                    isActive: songStore.activeSong?.id == song.id,
                                    onTap: {
                                        selectSong(song)
                                    },
                                    onLongPress: {
                                        editingSong = song
                                        showingSongEditor = true
                                    }
                                )
                            }
                            
                            // Add song button
                            AddSongButton {
                                showingAddSong = true
                            }
                        }
                        .padding()
                    }
                    
                    // Bottom status bar
                    StatusBar()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("KEYFRAME MK I")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingChordMap = true
                    } label: {
                        Image(systemName: "pianokeys")
                            .foregroundColor(.cyan)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.cyan)
                    }
                }
            }
            .toolbarBackground(Color(red: 0.05, green: 0.05, blue: 0.12), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            setupExternalMIDISelection()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(songStore)
                .environmentObject(midiService)
        }
        .sheet(isPresented: $showingSongEditor) {
            if let song = editingSong {
                SongEditorView(song: song, isNewSong: false)
                    .environmentObject(songStore)
                    .environmentObject(midiService)
            }
        }
        .sheet(isPresented: $showingAddSong) {
            SongEditorView(song: Song.newSong(), isNewSong: true)
                .environmentObject(songStore)
                .environmentObject(midiService)
        }
        .sheet(isPresented: $showingChordMap) {
            ChordMapView()
                .environmentObject(songStore)
                .environmentObject(midiService)
        }
    }
    
    // MARK: - External MIDI Song Selection
    
    private func setupExternalMIDISelection() {
        // Program Change selects song by index (PC 0 = first song, PC 1 = second, etc.)
        midiService.onSongSelect = { programNumber in
            guard programNumber >= 0 && programNumber < songStore.songs.count else { return }
            let song = songStore.songs[programNumber]
            selectSong(song)
        }
        
        // Note-based selection (Note 0 = first song, Note 1 = second, etc.)
        midiService.onSongSelectNote = { songIndex in
            guard songIndex >= 0 && songIndex < songStore.songs.count else { return }
            let song = songStore.songs[songIndex]
            selectSong(song)
        }
    }
    
    private func selectSong(_ song: Song) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Set active song
        songStore.setActiveSong(song)
        
        // Send MIDI preset (includes BPM)
        midiService.sendPreset(for: song)
    }
}

// MARK: - Active Song Header

struct ActiveSongHeader: View {
    let song: Song
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan.opacity(0.7))
                        .tracking(2)
                    
                    Text(song.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Key badge
                VStack(alignment: .trailing, spacing: 4) {
                    Text("KEY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan.opacity(0.7))
                        .tracking(2)
                    
                    Text(song.keyDisplayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                }
                
                // BPM indicator (if set)
                if song.bpm != nil {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("BPM")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan.opacity(0.7))
                            .tracking(2)
                        
                        Text(song.bpmDisplayString)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                }
                
                // Filter mode indicator
                VStack(alignment: .trailing, spacing: 4) {
                    Text("MODE")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan.opacity(0.7))
                        .tracking(2)
                    
                    HStack(spacing: 4) {
                        Image(systemName: song.filterMode == .block ? "nosign" : "arrow.trianglehead.turn.up.right.circle")
                            .font(.caption)
                        Text(song.filterMode.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(song.filterMode == .block ? .orange : .green)
                }
            }
            
            // Preset summary
            if !song.preset.controls.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Text(song.preset.summary)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(song.preset.controls.count) controls")
                        .font(.caption2)
                        .foregroundColor(.cyan.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Add Song Button

struct AddSongButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.cyan.opacity(0.6))
                
                Text("Add Song")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.cyan.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.cyan.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
            )
        }
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @EnvironmentObject var midiService: MIDIService
    
    var body: some View {
        HStack {
            // MIDI status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(midiService.isInitialized ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(midiService.isInitialized ? "MIDI Ready" : "MIDI Error")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // External input indicator
                if midiService.isListeningForInput {
                    Text("• EXT IN")
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Last received message (external input)
            if let lastReceived = midiService.lastReceivedMessage {
                Text("← \(lastReceived)")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.7))
            }
            
            // Last sent message
            if let lastMessage = midiService.lastSentMessage {
                Text("→ \(lastMessage)")
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SharedSongStore.shared)
        .environmentObject(MIDIService.shared)
}
