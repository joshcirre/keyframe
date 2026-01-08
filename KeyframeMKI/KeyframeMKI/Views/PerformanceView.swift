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

// MARK: - View Mode

enum ViewMode: String, CaseIterable {
    case perform = "PERFORM"
    case edit = "EDIT"
}

// MARK: - Main Performance View

struct PerformanceView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var viewMode: ViewMode = .perform
    @State private var selectedChannelIndex: Int?
    @State private var showingChannelDetail = false
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
                        .padding(.top, 12)
                }
                
                // Main content based on mode
                if viewMode == .perform {
                    performModeContent
                } else {
                    editModeContent
                }
                
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
        HStack(spacing: 12) {
            // Logo/Title
            Text("KEYFRAME")
                .font(TEFonts.display(18, weight: .black))
                .foregroundColor(TEColors.black)
                .tracking(3)
            
            Spacer()
            
            // Mode Toggle
            HStack(spacing: 0) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(viewMode == mode ? .white : TEColors.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(viewMode == mode ? TEColors.orange : TEColors.cream)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            
            Spacer()
            
            // Power button
            Button {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    audioEngine.start()
                }
            } label: {
                Circle()
                    .fill(audioEngine.isRunning ? TEColors.orange : TEColors.lightGray)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(audioEngine.isRunning ? .white : TEColors.darkGray)
                    )
                    .overlay(Circle().strokeBorder(TEColors.black, lineWidth: 2))
            }
            
            // Settings
            Button {
                showingSettings = true
            } label: {
                Rectangle()
                    .fill(TEColors.cream)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TEColors.black)
                    )
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Perform Mode Content (Faders + Songs side by side)
    
    private var performModeContent: some View {
        HStack(spacing: 0) {
            // Left: Channel Faders
            VStack(spacing: 0) {
                Text("CHANNELS")
                    .font(TEFonts.mono(9, weight: .bold))
                    .foregroundColor(TEColors.midGray)
                    .tracking(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                            PerformChannelStrip(
                                channel: channel,
                                config: sessionStore.currentSession.channels[safe: index],
                                onEdit: {
                                    selectedChannelIndex = index
                                    showingChannelDetail = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.5)
            .background(TEColors.cream)
            
            // Divider
            Rectangle()
                .fill(TEColors.black)
                .frame(width: 2)
            
            // Right: Songs
            VStack(spacing: 0) {
                Text("SONGS")
                    .font(TEFonts.mono(9, weight: .bold))
                    .foregroundColor(TEColors.midGray)
                    .tracking(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
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
            }
            .background(TEColors.warmWhite)
        }
    }
    
    // MARK: - Edit Mode Content (Original layout with clickable channels)
    
    private var editModeContent: some View {
        VStack(spacing: 0) {
            // Channel Strips (clickable for editing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                        EditChannelStripView(
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
            .frame(height: 200)
            
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
        }
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

// MARK: - Perform Mode Channel Strip (Direct control)

struct PerformChannelStrip: View {
    @ObservedObject var channel: ChannelStrip
    let config: ChannelConfiguration?
    let onEdit: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            // Channel name + edit button
            HStack {
                Text(config?.name.prefix(4).uppercased() ?? "CH")
                    .font(TEFonts.mono(9, weight: .bold))
                    .foregroundColor(TEColors.black)
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TEColors.midGray)
                }
            }
            .frame(width: 56)
            
            // Vertical Fader
            VerticalFader(value: $channel.volume)
                .frame(width: 40, height: 120)
            
            // Volume value
            Text("\(Int(channel.volume * 100))")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundColor(TEColors.black)
            
            // Mute button
            Button {
                channel.isMuted.toggle()
            } label: {
                Text("M")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(channel.isMuted ? .white : TEColors.red)
                    .frame(width: 32, height: 28)
                    .background(channel.isMuted ? TEColors.red : TEColors.cream)
                    .overlay(Rectangle().strokeBorder(TEColors.red, lineWidth: 2))
            }
            
            // Meter
            MeterView(level: channel.peakLevel)
                .frame(width: 12, height: 40)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
}

// MARK: - Vertical Fader

struct VerticalFader: View {
    @Binding var value: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track
                Rectangle()
                    .fill(TEColors.lightGray)
                
                // Fill
                Rectangle()
                    .fill(TEColors.orange)
                    .frame(height: geometry.size.height * CGFloat(value))
                
                // Border
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                
                // Handle line
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 4)
                    .offset(y: -geometry.size.height * CGFloat(value) + 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percent = 1.0 - Float(gesture.location.y / geometry.size.height)
                        value = min(max(percent, 0), 1)
                    }
            )
        }
    }
}

// MARK: - Edit Mode Channel Strip (Opens detail on tap)

struct EditChannelStripView: View {
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

// MARK: - Active Song Banner

struct ActiveSongBanner: View {
    let song: PerformanceSong
    
    var body: some View {
        HStack(spacing: 0) {
            // Song name
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.midGray)
                
                Text(song.name.uppercased())
                    .font(TEFonts.display(20, weight: .black))
                    .foregroundColor(TEColors.black)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Data blocks
            HStack(spacing: 12) {
                DataBlock(label: "KEY", value: song.keyShortName.uppercased())
                
                if let bpm = song.bpm {
                    DataBlock(label: "BPM", value: "\(bpm)")
                }
                
                DataBlock(
                    label: "MODE",
                    value: song.filterMode == .snap ? "SNP" : "BLK",
                    highlight: song.filterMode == .block
                )
            }
        }
        .padding(12)
        .background(
            Rectangle()
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
                .font(TEFonts.mono(8, weight: .medium))
                .foregroundColor(TEColors.midGray)
            
            Text(value)
                .font(TEFonts.mono(14, weight: .bold))
                .foregroundColor(highlight ? TEColors.orange : TEColors.black)
        }
        .frame(minWidth: 40)
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
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 8)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
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
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                        Text("NEW")
                            .font(TEFonts.mono(9, weight: .bold))
                    }
                    .foregroundColor(TEColors.darkGray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(TEColors.darkGray, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
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
            VStack(spacing: 3) {
                Text(song.name.uppercased())
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(isActive ? .white : TEColors.black)
                    .lineLimit(1)
                
                Text(song.keyShortName.uppercased())
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(isActive ? .white.opacity(0.8) : TEColors.midGray)
                
                if let bpm = song.bpm {
                    Text("\(bpm)")
                        .font(TEFonts.mono(9, weight: .regular))
                        .foregroundColor(isActive ? .white.opacity(0.6) : TEColors.midGray)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
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
        .padding(.vertical, 10)
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
