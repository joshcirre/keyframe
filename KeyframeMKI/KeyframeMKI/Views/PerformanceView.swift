import SwiftUI

// MARK: - Design System (Teenage Engineering Inspired)

enum TEColors {
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let warmWhite = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let orange = Color(red: 1.0, green: 0.45, blue: 0.0)
    static let black = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let darkGray = Color(red: 0.3, green: 0.3, blue: 0.3)
    static let midGray = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let lightGray = Color(red: 0.85, green: 0.83, blue: 0.80)
    static let red = Color(red: 0.9, green: 0.2, blue: 0.15)
    static let green = Color(red: 0.2, green: 0.75, blue: 0.3)
    static let yellow = Color(red: 0.95, green: 0.8, blue: 0.0)
}

enum TEFonts {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Main Performance View

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
        ZStack {
            TEColors.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Active Song Display
                if let activeSong = sessionStore.currentSession.activeSong {
                    ActiveSongBanner(song: activeSong)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
                
                // Channel Strips
                channelStripSection
                
                // Divider
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                    .padding(.horizontal, 20)
                
                // Song Grid
                SongGridView(
                    songs: sessionStore.currentSession.songs,
                    activeSongId: sessionStore.currentSession.activeSongId,
                    onSelectSong: { song in selectSong(song) },
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
                PerformanceStatusBar(audioEngine: audioEngine, midiEngine: midiEngine)
            }
        }
        .preferredColorScheme(.light)
        .onAppear { setupEngines() }
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
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 16) {
            // Logo/Title
            Text("KEYFRAME")
                .font(TEFonts.display(20, weight: .black))
                .foregroundColor(TEColors.black)
                .tracking(4)
            
            Text("MK I")
                .font(TEFonts.mono(12, weight: .medium))
                .foregroundColor(TEColors.midGray)
            
            Spacer()
            
            // Power button
            Button {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    audioEngine.start()
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .fill(audioEngine.isRunning ? TEColors.orange : TEColors.lightGray)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(audioEngine.isRunning ? .white : TEColors.darkGray)
                }
            }
            
            // Settings
            Button {
                showingSettings = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(TEColors.black, lineWidth: 2)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TEColors.black)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Channel Strips
    
    private var channelStripSection: some View {
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
                
                AddChannelButton {
                    if let _ = audioEngine.addChannel() {
                        let newConfig = ChannelConfiguration(name: "CH \(audioEngine.channelStrips.count)")
                        sessionStore.currentSession.channels.append(newConfig)
                        sessionStore.saveCurrentSession()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(height: 220)
    }
    
    // MARK: - Setup
    
    private func setupEngines() {
        midiEngine.setAudioEngine(audioEngine)
        syncChannelConfigs()
        
        if let activeSong = sessionStore.currentSession.activeSong {
            midiEngine.applySongSettings(convertToLegacySong(activeSong))
        }
        
        audioEngine.start()
    }
    
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
        
        sessionStore.setActiveSong(song)
        midiEngine.applySongSettings(convertToLegacySong(song))
        audioEngine.applyChannelStates(song.channelStates, configs: sessionStore.currentSession.channels)
    }
    
    private func convertToLegacySong(_ song: PerformanceSong) -> Song {
        Song(
            name: song.name,
            rootNote: song.rootNote,
            scaleType: song.scaleType,
            filterMode: song.filterMode,
            preset: MIDIPreset.empty,
            bpm: song.bpm
        )
    }
    
    private func binding(for index: Int) -> Binding<ChannelConfiguration> {
        Binding(
            get: { sessionStore.currentSession.channels[safe: index] ?? ChannelConfiguration() },
            set: { newValue in
                if index < sessionStore.currentSession.channels.count {
                    sessionStore.currentSession.channels[index] = newValue
                    sessionStore.saveCurrentSession()
                    
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
        HStack(spacing: 0) {
            // Song name
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.midGray)
                
                Text(song.name.uppercased())
                    .font(TEFonts.display(24, weight: .black))
                    .foregroundColor(TEColors.black)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Data blocks
            HStack(spacing: 16) {
                DataBlock(label: "KEY", value: song.keyShortName.uppercased())
                
                if let bpm = song.bpm {
                    DataBlock(label: "BPM", value: "\(bpm)")
                }
                
                DataBlock(
                    label: "MODE",
                    value: song.filterMode == .snap ? "SNAP" : "BLOCK",
                    highlight: song.filterMode == .block
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
}

struct DataBlock: View {
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(TEFonts.mono(9, weight: .medium))
                .foregroundColor(TEColors.midGray)
            
            Text(value)
                .font(TEFonts.mono(16, weight: .bold))
                .foregroundColor(highlight ? TEColors.orange : TEColors.black)
        }
        .frame(minWidth: 50)
    }
}

// MARK: - Channel Strip View

struct ChannelStripView: View {
    @ObservedObject var channel: ChannelStrip
    let config: ChannelConfiguration?
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Channel number
                Text(config?.name.prefix(6).uppercased() ?? "CH")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.black)
                    .lineLimit(1)
                
                // Meter
                MeterView(level: channel.peakLevel)
                    .frame(width: 24)
                
                // Volume display
                Text("\(Int(channel.volume * 100))")
                    .font(TEFonts.mono(14, weight: .bold))
                    .foregroundColor(TEColors.black)
                
                // Mute indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(channel.isMuted ? TEColors.red : TEColors.lightGray)
                        .frame(width: 32, height: 20)
                    
                    Text("M")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(channel.isMuted ? .white : TEColors.darkGray)
                }
                
                // Instrument loaded indicator
                Circle()
                    .fill(channel.isInstrumentLoaded ? TEColors.orange : TEColors.lightGray)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 64)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(TEColors.black, lineWidth: isSelected ? 3 : 2)
                    .background(isSelected ? TEColors.warmWhite : TEColors.cream)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meter View

struct MeterView: View {
    let level: Float
    
    private var normalizedLevel: CGFloat {
        let minDb: Float = -60
        let maxDb: Float = 0
        let clamped = min(max(level, minDb), maxDb)
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background segments
                VStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        Rectangle()
                            .fill(TEColors.lightGray)
                            .frame(height: (geometry.size.height - 22) / 12)
                    }
                }
                
                // Active segments
                VStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        let segmentLevel = CGFloat(12 - i) / 12.0
                        let isActive = normalizedLevel >= segmentLevel
                        let color: Color = i < 2 ? TEColors.red : (i < 4 ? TEColors.yellow : TEColors.green)
                        
                        Rectangle()
                            .fill(isActive ? color : Color.clear)
                            .frame(height: (geometry.size.height - 22) / 12)
                    }
                }
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
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TEColors.darkGray)
                
                Text("ADD")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.darkGray)
            }
            .frame(width: 64)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(TEColors.darkGray, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
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
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
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
                
                // Add button
                Button(action: onAddSong) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                        Text("NEW")
                            .font(TEFonts.mono(10, weight: .bold))
                    }
                    .foregroundColor(TEColors.darkGray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(TEColors.darkGray, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
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
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(song.name.uppercased())
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(isActive ? .white : TEColors.black)
                    .lineLimit(1)
                
                Text(song.keyShortName.uppercased())
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(isActive ? .white.opacity(0.8) : TEColors.midGray)
                
                if let bpm = song.bpm {
                    Text("\(bpm)")
                        .font(TEFonts.mono(10, weight: .regular))
                        .foregroundColor(isActive ? .white.opacity(0.6) : TEColors.midGray)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(isActive ? TEColors.orange : TEColors.warmWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(TEColors.black, lineWidth: isActive ? 3 : 2)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
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
        HStack(spacing: 20) {
            // Engine status
            HStack(spacing: 6) {
                Circle()
                    .fill(audioEngine.isRunning ? TEColors.green : TEColors.red)
                    .frame(width: 8, height: 8)
                
                Text(audioEngine.isRunning ? "RUN" : "OFF")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.black)
            }
            
            // MIDI
            HStack(spacing: 6) {
                Rectangle()
                    .fill(midiEngine.lastActivity != nil ? TEColors.orange : TEColors.lightGray)
                    .frame(width: 8, height: 8)
                
                Text("MIDI \(midiEngine.connectedSources.count)")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.darkGray)
            }
            
            Spacer()
            
            // CPU
            Text("CPU \(Int(audioEngine.cpuUsage))%")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(TEColors.darkGray)
            
            // Peak
            Text(String(format: "%.0fdB", audioEngine.peakLevel))
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(audioEngine.peakLevel > -3 ? TEColors.red : TEColors.darkGray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(TEColors.lightGray)
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    PerformanceView()
}
