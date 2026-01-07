import SwiftUI

/// Main performance view - the heart of the Keyframe Performance Engine
struct PerformanceView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var selectedChannelIndex: Int?
    @State private var showingChannelDetail = false
    @State private var showingPluginBrowser = false
    @State private var showingSettings = false
    @State private var showingSongEditor = false
    @State private var editingSong: PerformanceSong?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                
                VStack(spacing: 0) {
                    // Active Song Header
                    if let activeSong = sessionStore.currentSession.activeSong {
                        ActiveSongBanner(song: activeSong)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    // Channel Strips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                                ChannelStripView(
                                    channel: channel,
                                    config: sessionStore.currentSession.channels[safe: index],
                                    isSelected: selectedChannelIndex == index
                                ) {
                                    selectedChannelIndex = index
                                    showingChannelDetail = true
                                }
                            }
                            
                            // Add Channel Button
                            AddChannelButton {
                                if let _ = audioEngine.addChannel() {
                                    var newConfig = ChannelConfiguration(name: "Channel \(audioEngine.channelStrips.count)")
                                    sessionStore.currentSession.channels.append(newConfig)
                                    sessionStore.saveCurrentSession()
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(height: 200)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Song Grid
                    SongGridView(
                        songs: sessionStore.currentSession.songs,
                        activeSongId: sessionStore.currentSession.activeSongId,
                        onSelectSong: { song in
                            selectSong(song)
                        },
                        onEditSong: { song in
                            editingSong = song
                            showingSongEditor = true
                        },
                        onAddSong: {
                            editingSong = nil
                            showingSongEditor = true
                        }
                    )
                    
                    // Status Bar
                    PerformanceStatusBar(
                        audioEngine: audioEngine,
                        midiEngine: midiEngine
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("KEYFRAME")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if audioEngine.isRunning {
                            audioEngine.stop()
                        } else {
                            audioEngine.start()
                        }
                    } label: {
                        Image(systemName: audioEngine.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(audioEngine.isRunning ? .red : .green)
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
            setupEngines()
        }
        .sheet(isPresented: $showingChannelDetail) {
            if let index = selectedChannelIndex {
                ChannelDetailView(
                    channel: audioEngine.channelStrips[index],
                    config: binding(for: index)
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            PerformanceSettingsView()
        }
        .sheet(isPresented: $showingSongEditor) {
            PerformanceSongEditorView(
                song: editingSong ?? PerformanceSong(name: "New Song"),
                isNew: editingSong == nil,
                channels: sessionStore.currentSession.channels
            )
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.02, green: 0.02, blue: 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Setup
    
    private func setupEngines() {
        midiEngine.setAudioEngine(audioEngine)
        
        // Sync channel configs to channel strips
        syncChannelConfigs()
        
        // Apply current song settings if any
        if let activeSong = sessionStore.currentSession.activeSong {
            midiEngine.applySongSettings(convertToLegacySong(activeSong))
        }
        
        // Start audio engine
        audioEngine.start()
    }
    
    /// Sync ChannelConfiguration settings to ChannelStrip objects
    private func syncChannelConfigs() {
        for (index, config) in sessionStore.currentSession.channels.enumerated() {
            if index < audioEngine.channelStrips.count {
                let strip = audioEngine.channelStrips[index]
                strip.midiChannel = config.midiChannel
                strip.midiSourceName = config.midiSourceName
                strip.scaleFilterEnabled = config.scaleFilterEnabled
                strip.isNM2ChordChannel = config.isNM2ChordChannel
                strip.volume = config.volume
                strip.pan = config.pan
                strip.isMuted = config.isMuted
            }
        }
    }
    
    // MARK: - Song Selection
    
    private func selectSong(_ song: PerformanceSong) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Update session
        sessionStore.setActiveSong(song)
        
        // Apply to MIDI engine
        midiEngine.applySongSettings(convertToLegacySong(song))
        
        // Apply channel states directly, passing configs to match by index
        audioEngine.applyChannelStates(song.channelStates, configs: sessionStore.currentSession.channels)
        
        print("Selected song: \(song.name) with \(song.channelStates.count) channel presets")
    }
    
    private func convertToLegacySong(_ song: PerformanceSong) -> Song {
        Song(
            name: song.name,
            rootNote: song.rootNote,
            scaleType: song.scaleType,
            filterMode: song.filterMode,
            preset: MIDIPreset.empty,  // Performance engine doesn't use MIDI presets
            bpm: song.bpm
        )
    }
    
    private func binding(for index: Int) -> Binding<ChannelConfiguration> {
        Binding(
            get: {
                sessionStore.currentSession.channels[safe: index] ?? ChannelConfiguration()
            },
            set: { newValue in
                if index < sessionStore.currentSession.channels.count {
                    sessionStore.currentSession.channels[index] = newValue
                    sessionStore.saveCurrentSession()
                    
                    // Sync to channel strip
                    if index < audioEngine.channelStrips.count {
                        let strip = audioEngine.channelStrips[index]
                        strip.midiChannel = newValue.midiChannel
                        strip.midiSourceName = newValue.midiSourceName
                        strip.scaleFilterEnabled = newValue.scaleFilterEnabled
                        strip.isNM2ChordChannel = newValue.isNM2ChordChannel
                    }
                }
            }
        )
    }
}

// MARK: - Active Song Banner

struct ActiveSongBanner: View {
    let song: PerformanceSong
    
    var body: some View {
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
            
            // Key
            VStack(alignment: .trailing, spacing: 2) {
                Text("KEY")
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.7))
                Text(song.keyDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan)
            }
            
            // BPM
            if let bpm = song.bpm {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BPM")
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.7))
                    Text("\(bpm)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
            }
            
            // Mode
            VStack(alignment: .trailing, spacing: 2) {
                Text("MODE")
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.7))
                Text(song.filterMode.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(song.filterMode == .block ? .orange : .green)
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

// MARK: - Channel Strip View

struct ChannelStripView: View {
    @ObservedObject var channel: ChannelStrip
    let config: ChannelConfiguration?
    let isSelected: Bool
    let onTap: () -> Void
    
    private var channelColor: Color {
        Color(config?.color.uiColor ?? .systemCyan)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Channel name
                Text(config?.name ?? channel.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Meter
                MeterView(level: channel.peakLevel)
                    .frame(width: 8)
                
                // Volume
                Text("\(Int(channel.volume * 100))%")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospacedDigit()
                
                // Mute button
                Button {
                    channel.isMuted.toggle()
                } label: {
                    Text("M")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(channel.isMuted ? .black : .white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(channel.isMuted ? Color.red : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                
                // Instrument indicator
                Circle()
                    .fill(channel.isInstrumentLoaded ? channelColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 60)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.15 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(channelColor.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meter View

struct MeterView: View {
    let level: Float  // in dB
    
    private var normalizedLevel: CGFloat {
        // Convert dB to 0-1 range
        let minDb: Float = -60
        let maxDb: Float = 0
        let clamped = min(max(level, minDb), maxDb)
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }
    
    private var meterColor: Color {
        if level > -3 { return .red }
        if level > -12 { return .yellow }
        return .green
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                
                // Level
                RoundedRectangle(cornerRadius: 2)
                    .fill(meterColor)
                    .frame(height: geometry.size.height * normalizedLevel)
            }
        }
        .frame(height: 80)
    }
}

// MARK: - Add Channel Button

struct AddChannelButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.cyan.opacity(0.6))
                
                Text("Add")
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.6))
            }
            .frame(width: 60)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.cyan.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Song Grid View

struct SongGridView: View {
    let songs: [PerformanceSong]
    let activeSongId: UUID?
    let onSelectSong: (PerformanceSong) -> Void
    let onEditSong: (PerformanceSong) -> Void
    let onAddSong: () -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(songs) { song in
                    SongGridButton(
                        song: song,
                        isActive: song.id == activeSongId,
                        onTap: { onSelectSong(song) },
                        onLongPress: { onEditSong(song) }
                    )
                }
                
                // Add Song Button
                Button(action: onAddSong) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Add Song")
                            .font(.caption)
                    }
                    .foregroundColor(.cyan.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }
}

// MARK: - Song Grid Button

struct SongGridButton: View {
    let song: PerformanceSong
    let isActive: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    
    private var songColor: Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink, .red, .orange]
        return colors[song.rootNote % colors.count]
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(song.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isActive ? .black : .white)
                    .lineLimit(1)
                
                Text(song.keyShortName)
                    .font(.caption)
                    .foregroundColor(isActive ? .black.opacity(0.7) : songColor)
                
                if let bpm = song.bpm {
                    Text("\(bpm)")
                        .font(.caption2)
                        .foregroundColor(isActive ? .black.opacity(0.6) : .gray)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? songColor : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(songColor.opacity(isActive ? 0 : 0.5), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    onLongPress()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Performance Status Bar

struct PerformanceStatusBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var midiEngine: MIDIEngine
    
    var body: some View {
        HStack {
            // Audio status
            HStack(spacing: 6) {
                Circle()
                    .fill(audioEngine.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(audioEngine.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // MIDI activity
            HStack(spacing: 6) {
                Image(systemName: "pianokeys")
                    .font(.caption)
                    .foregroundColor(midiEngine.lastActivity != nil ? .cyan : .gray)
                
                Text("\(midiEngine.connectedSources.count) MIDI")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // CPU
            Text("CPU: \(Int(audioEngine.cpuUsage))%")
                .font(.caption)
                .foregroundColor(.gray)
                .monospacedDigit()
            
            Spacer()
            
            // Peak meter
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundColor(audioEngine.peakLevel > -3 ? .red : .cyan)
                
                Text(String(format: "%.0f dB", audioEngine.peakLevel))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
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

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    PerformanceView()
}
