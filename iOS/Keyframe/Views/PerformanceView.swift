import SwiftUI
import UniformTypeIdentifiers

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
    static let blue = Color(red: 0.2, green: 0.5, blue: 0.9)
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
    @State private var audioEngine = AudioEngine.shared
    @State private var midiEngine = MIDIEngine.shared
    @State private var sessionStore = SessionStore.shared
    @State private var pluginManager = AUv3HostManager.shared
    
    @State private var viewMode: ViewMode = .perform
    @State private var selectedChannelIndex: Int?
    @State private var showingChannelDetail = false
    @State private var showingSettings = false
    @State private var showingNewPresetEditor = false
    @State private var editingPreset: PerformanceSong?
    @State private var isChannelsLocked = false
    @State private var isInitializing = true
    @AppStorage("performModeSplitRatio") private var splitRatio: Double = 0.6  // Presets take 60% by default
    @AppStorage("isPresetsOnlyMode") private var isPresetsOnlyMode = false  // Hide faders, show only presets
    
    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            if isInitializing || audioEngine.isRestoringPlugins {
                // Loading screen
                LoadingScreen(progress: audioEngine.restorationProgress)
            } else if viewMode == .perform {
                // Fullscreen perform mode - no header, no status bar
                performModeContent
            } else {
                VStack(spacing: 0) {
                    // Header (only in edit mode)
                    header

                    // Active Song Display (only in edit mode)
                    if let activeSong = sessionStore.currentSession.activeSong {
                        ActiveSongBanner(song: activeSong)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    // Edit mode content
                    editModeContent

                    // Status Bar (only in edit mode)
                    PerformanceStatusBar(audioEngine: audioEngine, midiEngine: midiEngine, bpm: midiEngine.currentBPM)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { setupEngines() }
        .sheet(isPresented: $showingChannelDetail) {
            if let index = selectedChannelIndex,
               index < audioEngine.channelStrips.count,
               index < sessionStore.currentSession.channels.count {
                ChannelDetailView(
                    channel: audioEngine.channelStrips[index],
                    config: binding(for: index),
                    onDelete: {
                        deleteChannel(at: index)
                    }
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            PerformanceSettingsView()
        }
        .sheet(item: $editingPreset) { preset in
            // Edit existing preset - item binding ensures correct preset is passed
            PerformanceSongEditorView(
                song: preset,
                isNew: false,
                channels: sessionStore.currentSession.channels
            )
        }
        .sheet(isPresented: $showingNewPresetEditor) {
            // New preset
            PerformanceSongEditorView(
                song: PerformanceSong(name: "New Preset"),
                isNew: true,
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
                .foregroundStyle(TEColors.black)
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
                            .foregroundStyle(viewMode == mode ? .white : TEColors.black)
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
                            .foregroundStyle(audioEngine.isRunning ? .white : TEColors.darkGray)
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
                            .foregroundStyle(TEColors.black)
                    )
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Perform Mode Content (Fullscreen: adjustable presets/faders split or presets-only)

    private var performModeContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                if isPresetsOnlyMode {
                    presetsOnlyContent
                } else {
                    splitViewContent(geometry: geometry)
                }

                // Control buttons (top-right)
                performModeButtons
            }
        }
    }

    // MARK: - Split View Content (Presets + Faders)

    private func splitViewContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: Song Presets as squares (no long-press edit in perform mode)
                SongGridView(
                    songs: sessionStore.currentSession.songs,
                    activeSongId: sessionStore.currentSession.activeSongId,
                    isEditMode: false,
                    onSelectSong: { song in selectSong(song) },
                    onEditSong: { _ in },
                    onAddSong: { }
                )
                .padding(.top, 44)  // Room for control buttons overlay
                .frame(width: geometry.size.width * CGFloat(splitRatio))
                .background(TEColors.cream)

                // Draggable Divider
                DraggableDivider(splitRatio: $splitRatio, totalWidth: geometry.size.width)

                // Right: Channel Faders (aligned to bottom)
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                                PerformChannelStrip(
                                    channel: channel,
                                    config: sessionStore.currentSession.channels[safe: index],
                                    isLocked: isChannelsLocked,
                                    onEdit: {
                                        selectedChannelIndex = index
                                        showingChannelDetail = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }

            // Minimal status bar
            MinimalStatusBar(audioEngine: audioEngine, midiEngine: midiEngine, bpm: midiEngine.currentBPM)
        }
    }

    // MARK: - Presets Only Content (Fullscreen presets, no faders)

    private var presetsOnlyContent: some View {
        VStack(spacing: 0) {
            SongGridView(
                songs: sessionStore.currentSession.songs,
                activeSongId: sessionStore.currentSession.activeSongId,
                isEditMode: false,
                onSelectSong: { song in selectSong(song) },
                onEditSong: { _ in },
                onAddSong: { }
            )
            .padding(.top, 44)  // Room for control buttons overlay
            .background(TEColors.cream)

            // Minimal status bar
            MinimalStatusBar(audioEngine: audioEngine, midiEngine: midiEngine, bpm: midiEngine.currentBPM)
        }
    }

    // MARK: - Perform Mode Buttons (top-right overlay)

    private var performModeButtons: some View {
        HStack(spacing: 6) {
            // Presets-only toggle
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isPresetsOnlyMode.toggle()
                }
            } label: {
                Image(systemName: isPresetsOnlyMode ? "slider.horizontal.3" : "square.grid.2x2")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TEColors.black)
                    .frame(width: 28, height: 28)
                    .background(TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }

            // Lock button (only visible when faders are shown)
            if !isPresetsOnlyMode {
                Button {
                    isChannelsLocked.toggle()
                } label: {
                    Image(systemName: isChannelsLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isChannelsLocked ? .white : TEColors.black)
                        .frame(width: 28, height: 28)
                        .background(isChannelsLocked ? TEColors.black : TEColors.cream.opacity(0.9))
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }
            }

            // Close button
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    viewMode = .edit
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TEColors.black)
                    .frame(width: 28, height: 28)
                    .background(TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
    }
    
    // MARK: - Edit Mode Content (Original layout with clickable channels)
    
    private var editModeContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
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
                                // Re-sync all channel configs to ensure existing settings aren't lost
                                syncChannelConfigs()
                                // Debug: Log state after adding channel
                                logChannelState("After adding channel")
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
                    isEditMode: true,
                    onSelectSong: { song in selectSong(song) },
                    onEditSong: { preset in
                        // Setting editingPreset triggers the sheet(item:) presentation
                        editingPreset = preset
                    },
                    onAddSong: {
                        showingNewPresetEditor = true
                    },
                    onMoveSong: { fromIndex, toIndex in
                        sessionStore.moveSong(from: fromIndex, to: toIndex)
                    }
                )
                .frame(minHeight: 300)  // Ensure grid has minimum height
            }
        }
    }
    
    // MARK: - Setup

    private func setupEngines() {
        midiEngine.setAudioEngine(audioEngine)

        // Initialize currentBPM from active song if it has one
        if let activeSong = sessionStore.currentSession.activeSong, let bpm = activeSong.bpm {
            midiEngine.currentBPM = bpm
        }

        // Restore instruments and effects from saved session
        audioEngine.restorePlugins(from: sessionStore.currentSession.channels) { [weak audioEngine, weak sessionStore, weak midiEngine] in
            guard let audioEngine = audioEngine,
                  let sessionStore = sessionStore,
                  let midiEngine = midiEngine else { return }

            DispatchQueue.main.async {
                // Sync MIDI settings AFTER channel strips are created
                // This ensures midiSourceName, midiChannel, etc. are applied
                self.syncChannelConfigs()

                if let activeSong = sessionStore.currentSession.activeSong {
                    midiEngine.applySongSettings(self.convertToLegacySong(activeSong))
                    // Set initial tempo for hosted plugins
                    if let bpm = activeSong.bpm {
                        midiEngine.currentBPM = bpm
                        audioEngine.setTempo(Double(bpm))
                    }
                }

                // Start the audio engine after plugins are loaded
                audioEngine.start()
                self.isInitializing = false
            }
        }

        // If no plugins to restore, the completion is called immediately
        // but we also need to handle the case where there are no saved plugins
        if sessionStore.currentSession.channels.allSatisfy({ $0.instrument == nil && $0.effects.isEmpty }) {
            if let activeSong = sessionStore.currentSession.activeSong {
                midiEngine.applySongSettings(convertToLegacySong(activeSong))
                if let bpm = activeSong.bpm {
                    audioEngine.setTempo(Double(bpm))
                }
            }
            audioEngine.start()
            isInitializing = false
        }

        // Set up MIDI song trigger callback
        midiEngine.onSongTrigger = { [weak sessionStore, weak midiEngine, weak audioEngine] (note: Int, channel: Int, sourceName: String?) in
            guard let sessionStore = sessionStore,
                  let midiEngine = midiEngine,
                  let audioEngine = audioEngine else { return }

            // Find a song that matches this note trigger
            for song in sessionStore.currentSession.songs {
                if let triggerNote = song.triggerNote, triggerNote == note {
                    // Check channel if specified (nil = any channel)
                    let channelMatches = song.triggerChannel == nil || song.triggerChannel == channel
                    // Check source if specified (nil = any source)
                    let sourceMatches = song.triggerSourceName == nil || song.triggerSourceName == sourceName

                    if channelMatches && sourceMatches {
                        DispatchQueue.main.async {
                            #if os(iOS)
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            #endif

                            sessionStore.setActiveSong(song)
                            let legacySong = Song(
                                name: song.name,
                                rootNote: song.rootNote,
                                scaleType: song.scaleType,
                                filterMode: song.filterMode,
                                preset: .empty,
                                bpm: song.bpm
                            )
                            midiEngine.applySongSettings(legacySong)
                            audioEngine.applyChannelStates(song.channelStates, configs: sessionStore.currentSession.channels)

                            // Set tempo for hosted plugins
                            if let bpm = song.bpm {
                                audioEngine.setTempo(Double(bpm))
                                // Send tap tempo to external devices (e.g., Helix)
                                midiEngine.sendTapTempo(bpm: bpm)
                            }

                            // Send external MIDI messages
                            if !song.externalMIDIMessages.isEmpty {
                                midiEngine.sendExternalMIDIMessages(song.externalMIDIMessages)
                            }
                        }
                        break
                    }
                }
            }
        }

        // Set up MIDI fader control callback
        midiEngine.onFaderControl = { [weak sessionStore, weak audioEngine] (cc: Int, value: Int, channel: Int, sourceName: String?) in
            guard let sessionStore = sessionStore,
                  let audioEngine = audioEngine else { return }

            // Find channels that have this CC mapped for fader control
            for (index, config) in sessionStore.currentSession.channels.enumerated() {
                if let controlCC = config.controlCC, controlCC == cc {
                    // Check channel if specified (nil = any channel)
                    let channelMatches = config.controlChannel == nil || config.controlChannel == channel
                    // Check source if specified (nil = any source)
                    let sourceMatches = config.controlSourceName == nil || config.controlSourceName == sourceName

                    if channelMatches && sourceMatches {
                        // Convert CC value (0-127) to volume (0.0-1.0)
                        let volume = Float(value) / 127.0

                        DispatchQueue.main.async {
                            if index < audioEngine.channelStrips.count {
                                audioEngine.channelStrips[index].volume = volume
                                // Also update the config to keep in sync
                                sessionStore.currentSession.channels[index].volume = volume
                            }
                        }
                    }
                }
            }
        }
    }

    private func syncChannelConfigs() {
        print("🔄 syncChannelConfigs: Syncing \(sessionStore.currentSession.channels.count) configs to \(audioEngine.channelStrips.count) strips")
        for (index, config) in sessionStore.currentSession.channels.enumerated() {
            if index < audioEngine.channelStrips.count {
                let strip = audioEngine.channelStrips[index]
                let inputDisplay = config.midiSourceName == "__none__" ? "NONE" : (config.midiSourceName ?? "ALL")
                print("  Channel \(index): input='\(inputDisplay)' midiCh=\(config.midiChannel)")
                strip.midiChannel = config.midiChannel
                strip.midiSourceName = config.midiSourceName
                strip.scaleFilterEnabled = config.scaleFilterEnabled
                strip.isChordPadTarget = config.isChordPadTarget
                strip.isSingleNoteTarget = config.isSingleNoteTarget
                strip.octaveTranspose = config.octaveTranspose
                strip.volume = config.volume
                strip.pan = config.pan
                strip.isMuted = config.isMuted
            }
        }
    }

    private func logChannelState(_ context: String) {
        print("📊 Channel State [\(context)]:")
        print("  Configs: \(sessionStore.currentSession.channels.count), Strips: \(audioEngine.channelStrips.count)")
        for (index, config) in sessionStore.currentSession.channels.enumerated() {
            let configInput = config.midiSourceName == "__none__" ? "NONE" : (config.midiSourceName ?? "ALL")
            let stripInfo: String
            if index < audioEngine.channelStrips.count {
                let strip = audioEngine.channelStrips[index]
                let stripInput = strip.midiSourceName == "__none__" ? "NONE" : (strip.midiSourceName ?? "ALL")
                stripInfo = "strip.input='\(stripInput)'"
            } else {
                stripInfo = "NO STRIP"
            }
            print("  [\(index)] config.input='\(configInput)' | \(stripInfo)")
        }
    }
    
    // MARK: - Song Selection
    
    private func selectSong(_ song: PerformanceSong) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        sessionStore.setActiveSong(song)
        midiEngine.applySongSettings(convertToLegacySong(song))
        audioEngine.applyChannelStates(song.channelStates, configs: sessionStore.currentSession.channels)

        // Set tempo for hosted plugins (arpeggiators, tempo-synced effects, etc.)
        if let bpm = song.bpm {
            midiEngine.currentBPM = bpm
            audioEngine.setTempo(Double(bpm))
            // Send tap tempo to external devices (e.g., Helix)
            midiEngine.sendTapTempo(bpm: bpm)
        }

        // Send external MIDI messages (does NOT affect internal app state)
        if !song.externalMIDIMessages.isEmpty {
            midiEngine.sendExternalMIDIMessages(song.externalMIDIMessages)
        }
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
    
    private func deleteChannel(at index: Int) {
        // Remove from audio engine
        audioEngine.removeChannel(at: index)

        // Remove from session config
        if index < sessionStore.currentSession.channels.count {
            sessionStore.currentSession.channels.remove(at: index)
            sessionStore.saveCurrentSession()
        }

        // Clear selection
        selectedChannelIndex = nil
    }

    private func binding(for index: Int) -> Binding<ChannelConfiguration> {
        Binding(
            get: { sessionStore.currentSession.channels[safe: index] ?? ChannelConfiguration() },
            set: { newValue in
                if index < sessionStore.currentSession.channels.count {
                    let oldValue = sessionStore.currentSession.channels[index]
                    if oldValue.midiSourceName != newValue.midiSourceName {
                        let oldDisplay = oldValue.midiSourceName == "__none__" ? "NONE" : (oldValue.midiSourceName ?? "ALL")
                        let newDisplay = newValue.midiSourceName == "__none__" ? "NONE" : (newValue.midiSourceName ?? "ALL")
                        print("✏️ Binding[\(index)] input: '\(oldDisplay)' → '\(newDisplay)'")
                    }
                    sessionStore.currentSession.channels[index] = newValue
                    sessionStore.saveCurrentSession()

                    if index < audioEngine.channelStrips.count {
                        let strip = audioEngine.channelStrips[index]
                        strip.midiChannel = newValue.midiChannel
                        strip.midiSourceName = newValue.midiSourceName
                        strip.scaleFilterEnabled = newValue.scaleFilterEnabled
                        strip.isChordPadTarget = newValue.isChordPadTarget
                        strip.octaveTranspose = newValue.octaveTranspose
                    }
                }
            }
        )
    }
}

// MARK: - Perform Mode Channel Strip (Direct control)

struct PerformChannelStrip: View {
    @Bindable var channel: ChannelStrip
    let config: ChannelConfiguration?
    var isLocked: Bool = false
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Channel name + edit button
            HStack {
                Text(config?.name.prefix(4).uppercased() ?? "CH")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.black)

                Spacer()

                if !isLocked {
                    Button(action: onEdit) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TEColors.midGray)
                    }
                }
            }
            .frame(width: 60)

            // Vertical Fader
            VerticalFader(value: $channel.volume, isLocked: isLocked)
                .frame(width: 44, height: 160)

            // Volume value
            Text("\(Int(channel.volume * 100))")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(TEColors.black)

            // Mute button
            Button {
                if !isLocked {
                    channel.isMuted.toggle()
                }
            } label: {
                Text("M")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(channel.isMuted ? .white : TEColors.red)
                    .frame(width: 36, height: 28)
                    .background(channel.isMuted ? TEColors.red : TEColors.cream)
                    .overlay(Rectangle().strokeBorder(TEColors.red, lineWidth: 2))
            }
            .opacity(isLocked ? 0.5 : 1.0)

            // Level meter
            MeterView(level: channel.peakLevel)
                .frame(width: 36, height: 32)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.cream)
        )
    }
}

// MARK: - Vertical Fader

struct VerticalFader: View {
    @Binding var value: Float
    var isLocked: Bool = false

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
                        guard !isLocked else { return }
                        let percent = 1.0 - Float(gesture.location.y / geometry.size.height)
                        value = min(max(percent, 0), 1)
                    }
            )
            .opacity(isLocked ? 0.6 : 1.0)
        }
    }
}

// MARK: - Edit Mode Channel Strip (Opens detail on tap)

struct EditChannelStripView: View {
    var channel: ChannelStrip
    let config: ChannelConfiguration?
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Channel number
                Text(config?.name.prefix(6).uppercased() ?? "CH")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.black)
                    .lineLimit(1)
                
                // Meter
                MeterView(level: channel.peakLevel, segments: 10)
                    .frame(width: 24, height: 50)

                // Volume display
                Text("\(Int(channel.volume * 100))")
                    .font(TEFonts.mono(14, weight: .bold))
                    .foregroundStyle(TEColors.black)
                
                // Mute indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(channel.isMuted ? TEColors.red : TEColors.lightGray)
                        .frame(width: 32, height: 20)
                    
                    Text("M")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundStyle(channel.isMuted ? .white : TEColors.darkGray)
                }
                
                // Effects loaded indicator
                Circle()
                    .fill(!channel.effects.isEmpty ? TEColors.orange : TEColors.lightGray)
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
                    .foregroundStyle(TEColors.midGray)
                
                Text(song.name.uppercased())
                    .font(TEFonts.display(20, weight: .black))
                    .foregroundStyle(TEColors.black)
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
                .foregroundStyle(TEColors.midGray)
            
            Text(value)
                .font(TEFonts.mono(14, weight: .bold))
                .foregroundStyle(highlight ? TEColors.orange : TEColors.black)
        }
        .frame(minWidth: 40)
    }
}

// MARK: - Meter View

struct MeterView: View {
    let level: Float
    var segments: Int = 8

    private var normalizedLevel: CGFloat {
        // Guard against NaN and infinite values
        guard level.isFinite else { return 0 }

        let minDb: Float = -60
        let maxDb: Float = 0
        let clamped = min(max(level, minDb), maxDb)
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 1
            let totalSpacing = spacing * CGFloat(segments - 1)
            // Guard against invalid frame dimensions when geometry is zero or too small
            let availableHeight = geometry.size.height - totalSpacing
            let segmentHeight = availableHeight > 0 ? availableHeight / CGFloat(segments) : 1

            ZStack(alignment: .bottom) {
                // Background
                VStack(spacing: spacing) {
                    ForEach(0..<segments, id: \.self) { _ in
                        Rectangle()
                            .fill(TEColors.lightGray)
                            .frame(height: segmentHeight)
                    }
                }

                // Active segments
                VStack(spacing: spacing) {
                    ForEach(0..<segments, id: \.self) { i in
                        let segmentLevel = CGFloat(segments - i) / CGFloat(segments)
                        let isActive = normalizedLevel >= segmentLevel
                        let color: Color = i < 1 ? TEColors.red : (i < 2 ? TEColors.yellow : TEColors.green)

                        Rectangle()
                            .fill(isActive ? color : Color.clear)
                            .frame(height: segmentHeight)
                    }
                }
            }
        }
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
                    .foregroundStyle(TEColors.darkGray)
                
                Text("ADD")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.darkGray)
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
    let isEditMode: Bool
    let onSelectSong: (PerformanceSong) -> Void
    let onEditSong: (PerformanceSong) -> Void
    let onAddSong: () -> Void
    var onMoveSong: ((Int, Int) -> Void)?

    @State private var draggingSongId: UUID?
    @State private var isReorderMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Reorder toolbar (edit mode only)
            if isEditMode {
                HStack {
                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isReorderMode.toggle()
                            if !isReorderMode {
                                draggingSongId = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                                .font(.system(size: 11, weight: .bold))
                            Text(isReorderMode ? "DONE" : "REORDER")
                                .font(TEFonts.mono(10, weight: .bold))
                        }
                        .foregroundStyle(isReorderMode ? .white : TEColors.darkGray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isReorderMode ? TEColors.orange : TEColors.lightGray)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }

                    Button(action: onAddSong) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("NEW")
                                .font(TEFonts.mono(10, weight: .bold))
                        }
                        .foregroundStyle(TEColors.darkGray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TEColors.lightGray)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Grid content
            GeometryReader { geometry in
                let itemCount = songs.count
                let spacing: CGFloat = 6  // Minimal spacing between items
                let padding: CGFloat = 6  // Minimal outer margin
                let availableWidth = max(1, geometry.size.width - (padding * 2))
                let availableHeight = max(1, geometry.size.height - (padding * 2))

                // Calculate optimal grid dimensions
                let (columns, rows) = calculateGrid(itemCount: max(1, itemCount), availableWidth: availableWidth, availableHeight: availableHeight)

                // Calculate item sizes to fill the space exactly (guard against zero/negative)
                let totalHorizontalSpacing = spacing * CGFloat(max(0, columns - 1))
                let totalVerticalSpacing = spacing * CGFloat(max(0, rows - 1))
                let itemWidth = max(1, (availableWidth - totalHorizontalSpacing) / CGFloat(max(1, columns)))
                let itemHeight = max(1, (availableHeight - totalVerticalSpacing) / CGFloat(max(1, rows)))

                let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)

                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongGridButton(
                            song: song,
                            isActive: song.id == activeSongId,
                            isDragging: draggingSongId == song.id,
                            isReorderMode: isReorderMode,
                            isLargeText: !isEditMode,  // Large text only in perform mode
                            onTap: {
                                if !isReorderMode {
                                    onSelectSong(song)
                                }
                            },
                            onLongPress: {
                                if !isReorderMode {
                                    onEditSong(song)
                                }
                            }
                        )
                        .frame(height: itemHeight)
                        .onDrag {
                            if isReorderMode {
                                draggingSongId = song.id
                                return NSItemProvider(object: song.id.uuidString as NSString)
                            }
                            return NSItemProvider()
                        }
                        .onDrop(of: [.text], delegate: SongDropDelegate(
                            song: song,
                            songs: songs,
                            draggingSongId: $draggingSongId,
                            isReorderMode: isReorderMode,
                            onMoveSong: onMoveSong
                        ))
                    }
                }
                .padding(padding)
            }
        }
    }

    /// Calculate optimal grid layout to fill available space
    private func calculateGrid(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> (columns: Int, rows: Int) {
        guard itemCount > 0 else { return (1, 1) }

        let aspectRatio = availableWidth / availableHeight

        // Try different column counts and find the one that fills space best
        var bestColumns = 1
        var bestScore: CGFloat = 0

        for cols in 1...max(1, itemCount) {
            let rows = Int(ceil(Double(itemCount) / Double(cols)))
            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)

            // Score based on how square the cells are and how well they fill space
            let cellAspect = cellWidth / cellHeight
            let aspectScore = 1.0 / (abs(cellAspect - 1.5) + 0.1)  // Prefer slightly wide cells (1.5:1)
            let fillScore = CGFloat(itemCount) / CGFloat(cols * rows)  // How much of grid is used

            let score = aspectScore * fillScore

            if score > bestScore {
                bestScore = score
                bestColumns = cols
            }
        }

        let bestRows = Int(ceil(Double(itemCount) / Double(bestColumns)))
        return (bestColumns, bestRows)
    }
}

// MARK: - Song Drop Delegate

struct SongDropDelegate: DropDelegate {
    let song: PerformanceSong
    let songs: [PerformanceSong]
    @Binding var draggingSongId: UUID?
    let isReorderMode: Bool

    var onMoveSong: ((Int, Int) -> Void)?

    func performDrop(info: DropInfo) -> Bool {
        draggingSongId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard isReorderMode,
              let draggingId = draggingSongId,
              draggingId != song.id,
              let fromIndex = songs.firstIndex(where: { $0.id == draggingId }),
              let toIndex = songs.firstIndex(where: { $0.id == song.id }) else {
            return
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        onMoveSong?(fromIndex, toIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isReorderMode else { return DropProposal(operation: .cancel) }
        return DropProposal(operation: .move)
    }
}

// MARK: - Song Grid Button

struct SongGridButton: View {
    let song: PerformanceSong
    let isActive: Bool
    var isDragging: Bool = false
    var isReorderMode: Bool = false
    var isLargeText: Bool = false  // Use large dynamic text (for perform mode)
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        GeometryReader { geometry in
            // Calculate font sizes - large dynamic sizing for perform mode, fixed for edit mode
            // Guard against zero dimensions during initial layout
            let minDimension = max(1, min(geometry.size.width, geometry.size.height))
            let nameFontSize: CGFloat = isLargeText
                ? max(16, min(minDimension * 0.35, 48))  // 35% of cell, clamped 16-48
                : 14
            let songNameFontSize: CGFloat = isLargeText ? max(12, nameFontSize * 0.5) : 11

            Button(action: onTap) {
                ZStack {
                    VStack(spacing: isLargeText ? minDimension * 0.03 : 4) {
                        Spacer(minLength: 4)

                        // Preset name (main)
                        Text(song.name.uppercased())
                            .font(TEFonts.mono(nameFontSize, weight: isLargeText ? .black : .bold))
                            .foregroundStyle(isActive ? .white : TEColors.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(isLargeText ? 0.5 : 1.0)

                        // Song name (if set)
                        if let songName = song.songName, !songName.isEmpty {
                            Text(songName.uppercased())
                                .font(TEFonts.mono(songNameFontSize, weight: .medium))
                                .foregroundStyle(isActive ? .white.opacity(0.7) : TEColors.midGray)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, isLargeText ? 8 : 4)

                    // BPM indicator (top-left orange dot if BPM is set)
                    if song.bpm != nil {
                        VStack {
                            HStack {
                                Circle()
                                    .fill(TEColors.orange)
                                    .frame(width: isLargeText ? 10 : 8, height: isLargeText ? 10 : 8)
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }

                    // Drag handle indicator in reorder mode
                    if isReorderMode {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isActive ? .white.opacity(0.7) : TEColors.midGray)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(isActive ? TEColors.orange : TEColors.warmWhite)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(
                            isDragging ? TEColors.orange : (isReorderMode ? TEColors.darkGray : TEColors.black),
                            lineWidth: isDragging ? 4 : (isActive ? 3 : 2)
                        )
                )
                .overlay(
                    // Dashed border in reorder mode
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(TEColors.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .opacity(isReorderMode && !isDragging ? 1 : 0)
                )
                .scaleEffect(isPressed && !isReorderMode ? 0.96 : 1.0)
                .opacity(isDragging ? 0.6 : 1.0)
                .animation(.easeOut(duration: 0.1), value: isPressed)
                .animation(.easeOut(duration: 0.15), value: isDragging)
                .animation(.easeOut(duration: 0.15), value: isReorderMode)
            }
            .buttonStyle(.plain)
            .disabled(isReorderMode)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !isReorderMode else { return }
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    onLongPress()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isReorderMode { isPressed = true }
                }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Performance Status Bar

struct PerformanceStatusBar: View {
    var audioEngine: AudioEngine
    var midiEngine: MIDIEngine
    var bpm: Int = 90

    var body: some View {
        HStack(spacing: 20) {
            // Engine status
            HStack(spacing: 6) {
                Circle()
                    .fill(audioEngine.isRunning ? TEColors.green : TEColors.red)
                    .frame(width: 8, height: 8)

                Text(audioEngine.isRunning ? "RUN" : "OFF")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.black)
            }

            // MIDI
            HStack(spacing: 6) {
                Rectangle()
                    .fill(midiEngine.lastActivity != nil ? TEColors.orange : TEColors.lightGray)
                    .frame(width: 8, height: 8)

                Text("MIDI \(midiEngine.connectedSources.count)")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.darkGray)
            }

            // BPM
            Text("\(bpm) BPM")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.orange)

            Spacer()

            // DSP Load
            Text("DSP \(Int(audioEngine.cpuUsage))%")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(audioEngine.cpuUsage > 80 ? TEColors.red : TEColors.darkGray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(TEColors.lightGray)
    }
}

// MARK: - Minimal Status Bar (for perform mode)

struct MinimalStatusBar: View {
    var audioEngine: AudioEngine
    var midiEngine: MIDIEngine
    var bpm: Int = 90

    var body: some View {
        HStack(spacing: 16) {
            // MIDI count
            HStack(spacing: 4) {
                Rectangle()
                    .fill(midiEngine.lastActivity != nil ? TEColors.orange : TEColors.midGray)
                    .frame(width: 6, height: 6)

                Text("MIDI \(midiEngine.connectedSources.count)")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundStyle(TEColors.darkGray)
            }

            // BPM
            Text("\(bpm) BPM")
                .font(TEFonts.mono(9, weight: .bold))
                .foregroundStyle(TEColors.orange)

            Spacer()

            // DSP Load
            Text("DSP \(Int(audioEngine.cpuUsage))%")
                .font(TEFonts.mono(9, weight: .medium))
                .foregroundStyle(audioEngine.cpuUsage > 80 ? TEColors.red : TEColors.darkGray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(TEColors.lightGray.opacity(0.6))
    }
}

// MARK: - Draggable Divider

struct DraggableDivider: View {
    @Binding var splitRatio: Double
    let totalWidth: CGFloat

    @State private var isDragging = false
    @State private var dragStartRatio: Double = 0

    private let minRatio: Double = 0.3
    private let maxRatio: Double = 0.8

    var body: some View {
        Rectangle()
            .fill(isDragging ? TEColors.orange : TEColors.black)
            .frame(width: isDragging ? 8 : 4)
            .contentShape(Rectangle().inset(by: -30))  // Larger hit target for touch
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            // Capture the starting ratio when drag begins
                            isDragging = true
                            dragStartRatio = splitRatio
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                        // Use translation from drag start, not absolute location
                        let deltaRatio = Double(value.translation.width / totalWidth)
                        let proposedRatio = dragStartRatio + deltaRatio
                        splitRatio = min(max(proposedRatio, minRatio), maxRatio)
                    }
                    .onEnded { _ in
                        isDragging = false
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
            )
            .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - Loading Screen

struct LoadingScreen: View {
    let progress: String

    @State private var dotCount = 0
    @State private var logoScale: CGFloat = 0.8

    var body: some View {
        ZStack {
            TEColors.black.ignoresSafeArea()

            VStack(spacing: 32) {
                // Logo
                VStack(spacing: 8) {
                    Text("KEYFRAME")
                        .font(TEFonts.display(32, weight: .black))
                        .foregroundStyle(TEColors.cream)
                        .tracking(6)
                        .scaleEffect(logoScale)

                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: 120, height: 4)
                }

                // Loading indicator
                VStack(spacing: 16) {
                    // Animated dots
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index <= dotCount ? TEColors.orange : TEColors.darkGray)
                                .frame(width: 10, height: 10)
                        }
                    }

                    // Progress text
                    Text(progress.isEmpty ? "INITIALIZING" : progress.uppercased())
                        .font(TEFonts.mono(11, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .lineLimit(1)
                        .frame(maxWidth: 280)
                }
            }
        }
        .onAppear {
            // Animate logo scale
            withAnimation(.easeOut(duration: 0.5)) {
                logoScale = 1.0
            }

            // Animate loading dots
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
                withAnimation(.easeInOut(duration: 0.2)) {
                    dotCount = (dotCount + 1) % 4
                }
            }
        }
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
