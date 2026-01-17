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

    // iPad detection via size classes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var viewMode: ViewMode = .perform
    @State private var selectedChannelIndex: Int?
    @State private var showingChannelDetail = false
    @State private var showingSettings = false
    @State private var showingNewPresetEditor = false
    @State private var editingPreset: SetlistSong?
    @State private var isChannelsLocked = false
    @State private var isInitializing = true
    @AppStorage("isPresetsOnlyMode") private var isPresetsOnlyMode = false  // Fullscreen presets (no faders)
    @AppStorage("performModeSplitRatio") private var splitRatio: Double = 0.6  // Presets take 60% by default

    /// True when running on iPad (regular horizontal size class)
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    /// Adaptive spacing for iPad vs iPhone
    private var adaptiveSpacing: CGFloat {
        isIPad ? 16 : 12
    }

    /// Adaptive button size for iPad vs iPhone
    private var adaptiveButtonSize: CGFloat {
        isIPad ? 44 : 36
    }

    /// Adaptive font scale for iPad
    private var fontScale: CGFloat {
        isIPad ? 1.2 : 1.0
    }
    
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
            if let index = selectedChannelIndex, index < audioEngine.channelStrips.count {
                ChannelDetailView(
                    channel: audioEngine.channelStrips[index],
                    config: binding(for: index),
                    onDelete: {
                        deleteChannel(at: index)
                    }
                )
                .presentationDetents(isIPad ? [.large] : [.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingSettings) {
            PerformanceSettingsView()
                .presentationDetents(isIPad ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingPreset) { preset in
            // Edit existing preset - item binding ensures correct preset is passed
            PerformanceSongEditorView(
                song: preset,
                isNew: false,
                channels: sessionStore.currentSession.channels
            )
            .presentationDetents(isIPad ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingNewPresetEditor) {
            // New song with a default preset
            PerformanceSongEditorView(
                song: SetlistSong(
                    name: "NEW SONG",
                    presets: [SongPreset(name: "Default", order: 0, isActive: true)]
                ),
                isNew: true,
                channels: sessionStore.currentSession.channels
            )
            .presentationDetents(isIPad ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Header

    private var header: some View {
        HStack(spacing: adaptiveSpacing) {
            // Logo/Title
            Text("KEYFRAME")
                .font(TEFonts.display(18 * fontScale, weight: .black))
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
                            .font(TEFonts.mono(10 * fontScale, weight: .bold))
                            .foregroundColor(viewMode == mode ? .white : TEColors.black)
                            .padding(.horizontal, isIPad ? 18 : 14)
                            .padding(.vertical, isIPad ? 10 : 8)
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
                    .frame(width: adaptiveButtonSize, height: adaptiveButtonSize)
                    .overlay(
                        Image(systemName: "power")
                            .font(.system(size: 12 * fontScale, weight: .bold))
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
                    .frame(width: adaptiveButtonSize, height: adaptiveButtonSize)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14 * fontScale, weight: .bold))
                            .foregroundColor(TEColors.black)
                    )
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.horizontal, isIPad ? 24 : 16)
        .padding(.vertical, isIPad ? 16 : 12)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Perform Mode Content (Split view or fullscreen presets)

    private var performModeContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                if isPresetsOnlyMode {
                    // Fullscreen presets-only mode (for external MIDI triggering)
                    presetsOnlyContent
                } else {
                    // Split view: presets + faders
                    splitPerformContent(geometry: geometry)
                }

                // Control buttons (top-right)
                performModeButtons
            }
        }
    }

    // MARK: - Split Perform Content (Presets + Faders)

    private func splitPerformContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: Song Presets as squares (or Remote Presets in remote mode)
                Group {
                    if midiEngine.isRemoteMode && !midiEngine.remotePresets.isEmpty {
                        RemotePresetGridView(
                            presets: midiEngine.remotePresets,
                            selectedIndex: nil,  // TODO: track selected remote preset
                            onSelectPreset: { preset in selectRemotePreset(preset) }
                        )
                    } else {
                        SongGridView(
                            songs: sessionStore.currentSession.setlist,
                            activeSongId: sessionStore.currentSession.activeSongId,
                            isEditMode: false,
                            onSelectSong: { song in selectSong(song) },
                            onEditSong: { _ in },
                            onAddSong: { }
                        )
                    }
                }
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

            // Looper controls
            looperControlBar

            // Setlist navigation + status bar
            SetlistStatusBar(
                audioEngine: audioEngine,
                midiEngine: midiEngine,
                bpm: midiEngine.currentBPM,
                currentIndex: currentSongIndex,
                totalSongs: sessionStore.currentSession.setlist.count,
                currentSongName: sessionStore.currentSession.activeSong?.name,
                onPrevious: goToPreviousSong,
                onNext: goToNextSong,
                isIPad: isIPad
            )
        }
    }

    // MARK: - Presets-Only Content (Fullscreen grid for external MIDI)

    private var presetsOnlyContent: some View {
        VStack(spacing: 0) {
            // Fullscreen song grid (or Remote Presets in remote mode)
            Group {
                if midiEngine.isRemoteMode && !midiEngine.remotePresets.isEmpty {
                    RemotePresetGridView(
                        presets: midiEngine.remotePresets,
                        selectedIndex: nil,
                        onSelectPreset: { preset in selectRemotePreset(preset) }
                    )
                } else {
                    SongGridView(
                        songs: sessionStore.currentSession.setlist,
                        activeSongId: sessionStore.currentSession.activeSongId,
                        isEditMode: false,
                        onSelectSong: { song in selectSong(song) },
                        onEditSong: { _ in },
                        onAddSong: { }
                    )
                }
            }
            .padding(.top, 44)  // Room for control buttons overlay
            .background(TEColors.cream)

            // Looper controls
            looperControlBar

            // Setlist navigation + status bar
            SetlistStatusBar(
                audioEngine: audioEngine,
                midiEngine: midiEngine,
                bpm: midiEngine.currentBPM,
                currentIndex: currentSongIndex,
                totalSongs: sessionStore.currentSession.setlist.count,
                currentSongName: sessionStore.currentSession.activeSong?.name,
                onPrevious: goToPreviousSong,
                onNext: goToNextSong,
                isIPad: isIPad
            )
        }
    }

    // MARK: - Setlist Navigation (Perform Mode)

    /// Current song index in the setlist
    private var currentSongIndex: Int? {
        guard let activeId = sessionStore.currentSession.activeSongId else { return nil }
        return sessionStore.currentSession.setlist.firstIndex(where: { $0.id == activeId })
    }

    /// Navigate to previous song in setlist
    private func goToPreviousSong() {
        guard let currentIndex = currentSongIndex, currentIndex > 0 else { return }
        let previousSong = sessionStore.currentSession.setlist[currentIndex - 1]
        selectSong(previousSong)
    }

    /// Navigate to next song in setlist
    private func goToNextSong() {
        guard let currentIndex = currentSongIndex,
              currentIndex < sessionStore.currentSession.setlist.count - 1 else { return }
        let nextSong = sessionStore.currentSession.setlist[currentIndex + 1]
        selectSong(nextSong)
    }

    // MARK: - Looper Controls

    private var looperControlBar: some View {
        HStack(spacing: isIPad ? 12 : 8) {
            // Record/Stop button
            Button {
                audioEngine.looper?.toggle()
            } label: {
                let state = audioEngine.looper?.state ?? .empty
                HStack(spacing: 6) {
                    Circle()
                        .fill(state == .recording ? TEColors.red : (state == .playing ? TEColors.green : TEColors.midGray))
                        .frame(width: 10, height: 10)

                    Text(looperButtonLabel)
                        .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                        .foregroundColor(TEColors.black)
                }
                .padding(.horizontal, isIPad ? 16 : 12)
                .padding(.vertical, isIPad ? 10 : 8)
                .background(looperButtonBackground)
                .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }

            // Duration display
            if let looper = audioEngine.looper, looper.state != .empty {
                Text(looper.durationString)
                    .font(TEFonts.mono(isIPad ? 14 : 11, weight: .bold))
                    .foregroundColor(looper.state == .recording ? TEColors.red : TEColors.black)
            }

            // Clear button (only show when there's a loop)
            if let looper = audioEngine.looper, looper.state != .empty && looper.state != .recording {
                Button {
                    audioEngine.looper?.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: isIPad ? 14 : 11, weight: .bold))
                        .foregroundColor(TEColors.red)
                        .padding(isIPad ? 10 : 8)
                        .background(TEColors.cream.opacity(0.9))
                        .overlay(Rectangle().strokeBorder(TEColors.red, lineWidth: 2))
                }
            }

            Spacer()
        }
        .padding(.horizontal, isIPad ? 16 : 12)
        .padding(.vertical, isIPad ? 8 : 6)
        .background(TEColors.warmWhite)
    }

    private var looperButtonLabel: String {
        switch audioEngine.looper?.state ?? .empty {
        case .empty: return "REC"
        case .recording: return "STOP"
        case .playing: return "PAUSE"
        case .stopped: return "PLAY"
        }
    }

    private var looperButtonBackground: Color {
        switch audioEngine.looper?.state ?? .empty {
        case .empty: return TEColors.cream.opacity(0.9)
        case .recording: return TEColors.red.opacity(0.2)
        case .playing: return TEColors.green.opacity(0.2)
        case .stopped: return TEColors.orange.opacity(0.2)
        }
    }

    // MARK: - Perform Mode Buttons

    /// Adaptive perform button size (larger on iPad for easier touch)
    private var performButtonSize: CGFloat {
        isIPad ? 40 : 28
    }

    private var performModeButtons: some View {
        HStack(spacing: isIPad ? 10 : 6) {
            // Freeze toggle button (with hold indicator)
            Button {
                midiEngine.toggleFreeze()
            } label: {
                Image(systemName: midiEngine.isFreezeActive ? "pause.circle.fill" : "pause.circle")
                    .font(.system(size: isIPad ? 16 : 11, weight: .bold))
                    .foregroundColor(midiEngine.isFreezeActive ? .white : TEColors.black)
                    .frame(width: performButtonSize, height: performButtonSize)
                    .background(midiEngine.isFreezeActive ? TEColors.red : TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(midiEngine.isFreezeActive ? TEColors.red : TEColors.black, lineWidth: 2))
            }

            // Toggle presets-only mode
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isPresetsOnlyMode.toggle()
                }
            } label: {
                Image(systemName: isPresetsOnlyMode ? "slider.horizontal.3" : "square.grid.2x2")
                    .font(.system(size: isIPad ? 16 : 11, weight: .bold))
                    .foregroundColor(isPresetsOnlyMode ? .white : TEColors.black)
                    .frame(width: performButtonSize, height: performButtonSize)
                    .background(isPresetsOnlyMode ? TEColors.orange : TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }

            // Lock button (only show when not in presets-only mode)
            if !isPresetsOnlyMode {
                Button {
                    isChannelsLocked.toggle()
                } label: {
                    Image(systemName: isChannelsLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: isIPad ? 16 : 11, weight: .bold))
                        .foregroundColor(isChannelsLocked ? .white : TEColors.black)
                        .frame(width: performButtonSize, height: performButtonSize)
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
                    .font(.system(size: isIPad ? 18 : 12, weight: .bold))
                    .foregroundColor(TEColors.black)
                    .frame(width: performButtonSize, height: performButtonSize)
                    .background(TEColors.cream.opacity(0.9))
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.top, isIPad ? 12 : 8)
        .padding(.trailing, isIPad ? 12 : 8)
    }
    
    // MARK: - Edit Mode Content (Original layout with clickable channels)

    private var editModeContent: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            // iPad gets larger channel strips for easier interaction
            let channelStripHeight: CGFloat = isIPad
                ? (isLandscape ? 200 : 240)
                : (isLandscape ? 160 : 200)
            let presetGridMinHeight: CGFloat = isIPad
                ? (isLandscape ? 300 : 400)
                : (isLandscape ? 200 : 300)
            let channelSpacing: CGFloat = isIPad ? 16 : 12

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Channel Strips (clickable for editing)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: channelSpacing) {
                            ForEach(Array(audioEngine.channelStrips.enumerated()), id: \.element.id) { index, channel in
                                EditChannelStripView(
                                    channel: channel,
                                    config: sessionStore.currentSession.channels[safe: index],
                                    isSelected: selectedChannelIndex == index,
                                    isIPad: isIPad
                                ) {
                                    selectedChannelIndex = index
                                    showingChannelDetail = true
                                }
                            }

                            AddChannelButton(isIPad: isIPad) {
                                if let _ = audioEngine.addChannel() {
                                    let newConfig = ChannelConfiguration(name: "CH \(audioEngine.channelStrips.count)")
                                    sessionStore.currentSession.channels.append(newConfig)
                                    sessionStore.saveCurrentSession()
                                }
                            }
                        }
                        .padding(.horizontal, isIPad ? 28 : 20)
                        .padding(.vertical, isIPad ? 20 : 16)
                    }
                    .frame(height: channelStripHeight)

                    // Divider
                    Rectangle()
                        .fill(TEColors.black)
                        .frame(height: 2)
                        .padding(.horizontal, 20)

                    // Song Grid
                    SongGridView(
                        songs: sessionStore.currentSession.setlist,
                        activeSongId: sessionStore.currentSession.activeSongId,
                        isEditMode: true,
                        onSelectSong: { song in selectSong(song) },
                        onEditSong: { song in
                            // Setting editingPreset triggers the sheet(item:) presentation
                            editingPreset = song
                        },
                        onAddSong: {
                            showingNewPresetEditor = true
                        },
                        onMoveSong: { fromIndex, toIndex in
                            sessionStore.moveSong(from: fromIndex, to: toIndex)
                        }
                    )
                    .frame(minHeight: presetGridMinHeight)
                }
            }
        }
    }
    
    // MARK: - Setup

    private func setupEngines() {
        midiEngine.setAudioEngine(audioEngine)
        syncChannelConfigs()
        syncFreezeSettings()

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
                    midiEngine.currentBPM = bpm
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
            for song in sessionStore.currentSession.setlist {
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

                            // Set tempo for hosted plugins (only if preset has BPM)
                            if let bpm = song.bpm {
                                midiEngine.currentBPM = bpm
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
                            }
                        }
                    }
                }
            }
        }
    }

    private func syncChannelConfigs() {
        for (index, config) in sessionStore.currentSession.channels.enumerated() {
            if index < audioEngine.channelStrips.count {
                let strip = audioEngine.channelStrips[index]
                strip.midiChannel = config.midiChannel
                strip.midiSourceName = config.midiSourceName
                strip.scaleFilterEnabled = config.scaleFilterEnabled
                strip.isChordPadTarget = config.isChordPadTarget
                strip.volume = config.volume
                strip.pan = config.pan
                strip.isMuted = config.isMuted
            }
        }
    }

    private func syncFreezeSettings() {
        // Sync freeze configuration from session to MIDI engine
        midiEngine.freezeMode = sessionStore.currentSession.freezeMode
        midiEngine.freezeTriggerCC = sessionStore.currentSession.freezeTriggerCC
        midiEngine.freezeTriggerChannel = sessionStore.currentSession.freezeTriggerChannel
        midiEngine.freezeTriggerSourceName = sessionStore.currentSession.freezeTriggerSourceName
    }

    private func deleteChannel(at index: Int) {
        // Remove from audio engine
        audioEngine.removeChannel(at: index)
        // Remove from session
        sessionStore.deleteChannel(at: index)
        // Clear selection
        selectedChannelIndex = nil
    }
    
    // MARK: - Song Selection

    private func selectSong(_ song: SetlistSong) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Always update local UI state
        sessionStore.setActiveSong(song)

        // Always send external MIDI to Helix (even in remote mode)
        // iOS keeps direct control of Helix - no need to route through Mac
        if let bpm = song.bpm {
            midiEngine.currentBPM = bpm
            midiEngine.sendTapTempo(bpm: bpm)
        }
        if !song.externalMIDIMessages.isEmpty {
            midiEngine.sendExternalMIDIMessages(song.externalMIDIMessages)
        }

        // In remote mode, tell Mac to change synth preset (via Network MIDI)
        if midiEngine.isRemoteMode {
            if let index = sessionStore.currentSession.setlist.firstIndex(where: { $0.id == song.id }) {
                midiEngine.sendRemotePresetChange(presetIndex: index)
            }
            // Skip local audio engine - Mac handles synths
            return
        }

        // Local mode - apply audio engine changes locally
        midiEngine.applySongSettings(convertToLegacySong(song))
        audioEngine.applyChannelStates(song.channelStates, configs: sessionStore.currentSession.channels)
        if let bpm = song.bpm {
            audioEngine.setTempo(Double(bpm))
        }
    }

    private func convertToLegacySong(_ song: SetlistSong) -> Song {
        Song(
            name: song.name,
            rootNote: song.rootNote,
            scaleType: song.scaleType,
            filterMode: song.filterMode,
            preset: MIDIPreset.empty,
            bpm: song.bpm
        )
    }

    // MARK: - Remote Preset Selection (Remote Mode)

    private func selectRemotePreset(_ preset: RemotePreset) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Send tap tempo and external MIDI to Helix (direct)
        if let bpm = preset.bpm {
            midiEngine.currentBPM = bpm
            midiEngine.sendTapTempo(bpm: bpm)
        }
        if !preset.externalMIDIMessages.isEmpty {
            midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)
        }

        // Tell Mac to change synth preset
        midiEngine.sendRemotePresetChange(presetIndex: preset.index)
    }
    
    private func binding(for index: Int) -> Binding<ChannelConfiguration> {
        Binding(
            get: { sessionStore.currentSession.channels[safe: index] ?? ChannelConfiguration() },
            set: { newValue in
                guard index < sessionStore.currentSession.channels.count else { return }

                // Only update if the value actually changed (prevents excessive re-renders)
                let currentValue = sessionStore.currentSession.channels[index]
                guard newValue != currentValue else { return }

                sessionStore.currentSession.channels[index] = newValue
                sessionStore.saveCurrentSession()

                // Sync to audio engine strip
                if index < audioEngine.channelStrips.count {
                    let strip = audioEngine.channelStrips[index]
                    strip.midiChannel = newValue.midiChannel
                    strip.midiSourceName = newValue.midiSourceName
                    strip.scaleFilterEnabled = newValue.scaleFilterEnabled
                    strip.isChordPadTarget = newValue.isChordPadTarget
                }
            }
        )
    }
}

// MARK: - Perform Mode Channel Strip (Direct control)

struct PerformChannelStrip: View {
    @ObservedObject var channel: ChannelStrip
    let config: ChannelConfiguration?
    var isLocked: Bool = false
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Channel name + edit button
            HStack {
                Text(config?.name.prefix(4).uppercased() ?? "CH")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.black)

                Spacer()

                if !isLocked {
                    Button(action: onEdit) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(TEColors.midGray)
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
                .foregroundColor(TEColors.black)

            // Mute button
            Button {
                if !isLocked {
                    channel.isMuted.toggle()
                }
            } label: {
                Text("M")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(channel.isMuted ? .white : TEColors.red)
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
    @ObservedObject var channel: ChannelStrip
    let config: ChannelConfiguration?
    let isSelected: Bool
    var isIPad: Bool = false
    let onTap: () -> Void

    /// Adaptive sizing for iPad
    private var stripWidth: CGFloat { isIPad ? 80 : 64 }
    private var meterWidth: CGFloat { isIPad ? 32 : 24 }
    private var meterHeight: CGFloat { isIPad ? 70 : 50 }
    private var muteWidth: CGFloat { isIPad ? 44 : 32 }
    private var muteHeight: CGFloat { isIPad ? 28 : 20 }
    private var indicatorSize: CGFloat { isIPad ? 12 : 8 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: isIPad ? 10 : 8) {
                // Channel number
                Text(config?.name.prefix(6).uppercased() ?? "CH")
                    .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                    .foregroundColor(TEColors.black)
                    .lineLimit(1)

                // Meter
                MeterView(level: channel.peakLevel, segments: isIPad ? 12 : 10)
                    .frame(width: meterWidth, height: meterHeight)

                // Volume display
                Text("\(Int(channel.volume * 100))")
                    .font(TEFonts.mono(isIPad ? 18 : 14, weight: .bold))
                    .foregroundColor(TEColors.black)

                // Mute indicator
                ZStack {
                    RoundedRectangle(cornerRadius: isIPad ? 6 : 4)
                        .fill(channel.isMuted ? TEColors.red : TEColors.lightGray)
                        .frame(width: muteWidth, height: muteHeight)

                    Text("M")
                        .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                        .foregroundColor(channel.isMuted ? .white : TEColors.darkGray)
                }

                // Effects loaded indicator
                Circle()
                    .fill(!channel.effects.isEmpty ? TEColors.orange : TEColors.lightGray)
                    .frame(width: indicatorSize, height: indicatorSize)
            }
            .frame(width: stripWidth)
            .padding(.vertical, isIPad ? 16 : 12)
            .padding(.horizontal, isIPad ? 10 : 8)
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
    let song: SetlistSong
    
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
            let segmentHeight = (geometry.size.height - totalSpacing) / CGFloat(segments)

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
    var isIPad: Bool = false
    let action: () -> Void

    private var buttonWidth: CGFloat { isIPad ? 80 : 64 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: isIPad ? 10 : 8) {
                Image(systemName: "plus")
                    .font(.system(size: isIPad ? 30 : 24, weight: .bold))
                    .foregroundColor(TEColors.darkGray)

                Text("ADD")
                    .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                    .foregroundColor(TEColors.darkGray)
            }
            .frame(width: buttonWidth)
            .padding(.vertical, isIPad ? 16 : 12)
            .padding(.horizontal, isIPad ? 10 : 8)
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
    let songs: [SetlistSong]
    let activeSongId: UUID?
    let isEditMode: Bool
    let onSelectSong: (SetlistSong) -> Void
    let onEditSong: (SetlistSong) -> Void
    let onAddSong: () -> Void
    var onMoveSong: ((Int, Int) -> Void)?

    // iPad detection via size class
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isIPad: Bool { horizontalSizeClass == .regular }

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
                        HStack(spacing: isIPad ? 8 : 6) {
                            Image(systemName: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                                .font(.system(size: isIPad ? 14 : 11, weight: .bold))
                            Text(isReorderMode ? "DONE" : "REORDER")
                                .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                        }
                        .foregroundColor(isReorderMode ? .white : TEColors.darkGray)
                        .padding(.horizontal, isIPad ? 16 : 12)
                        .padding(.vertical, isIPad ? 10 : 6)
                        .background(isReorderMode ? TEColors.orange : TEColors.lightGray)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }

                    Button(action: onAddSong) {
                        HStack(spacing: isIPad ? 8 : 6) {
                            Image(systemName: "plus")
                                .font(.system(size: isIPad ? 14 : 11, weight: .bold))
                            Text("NEW")
                                .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                        }
                        .foregroundColor(TEColors.darkGray)
                        .padding(.horizontal, isIPad ? 16 : 12)
                        .padding(.vertical, isIPad ? 10 : 6)
                        .background(TEColors.lightGray)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }
                }
                .padding(.horizontal, isIPad ? 24 : 16)
                .padding(.vertical, isIPad ? 12 : 8)
            }

            // Grid content
            GeometryReader { geometry in
                let itemCount = songs.count
                // iPad gets larger spacing for touch-friendliness
                let spacing: CGFloat = isIPad ? 10 : 6
                let padding: CGFloat = isIPad ? 10 : 6
                let availableWidth = geometry.size.width - (padding * 2)
                let availableHeight = geometry.size.height - (padding * 2)

                // Calculate optimal grid dimensions (iPad prefers more columns to utilize width)
                let (columns, rows) = calculateGrid(itemCount: max(1, itemCount), availableWidth: availableWidth, availableHeight: availableHeight, isIPad: isIPad)

                // Calculate item sizes to fill the space exactly
                let totalHorizontalSpacing = spacing * CGFloat(columns - 1)
                let totalVerticalSpacing = spacing * CGFloat(rows - 1)
                let itemWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(columns)
                let itemHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

                let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)

                // Find index of active song to determine "next up"
                let activeIndex = songs.firstIndex(where: { $0.id == activeSongId })
                let nextIndex = activeIndex.map { $0 + 1 < songs.count ? $0 + 1 : nil } ?? nil

                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongGridButton(
                            song: song,
                            isActive: song.id == activeSongId,
                            isNextUp: nextIndex == index,
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
    /// iPad uses minimum cell size constraints for better touch targets
    private func calculateGrid(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat, isIPad: Bool = false) -> (columns: Int, rows: Int) {
        guard itemCount > 0 else { return (1, 1) }

        // iPad has minimum cell size for touch-friendliness (at least 100pt)
        let minCellSize: CGFloat = isIPad ? 100 : 60
        let maxPossibleColumns = max(1, Int(availableWidth / minCellSize))
        let maxPossibleRows = max(1, Int(availableHeight / minCellSize))

        // Try different column counts and find the one that fills space best
        var bestColumns = 1
        var bestScore: CGFloat = 0

        let maxCols = min(itemCount, maxPossibleColumns)
        for cols in 1...max(1, maxCols) {
            let rows = Int(ceil(Double(itemCount) / Double(cols)))

            // Skip if this would make cells too small
            if rows > maxPossibleRows {
                continue
            }

            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)

            // Score based on how square the cells are and how well they fill space
            let cellAspect = cellWidth / cellHeight
            // iPad prefers wider cells (1.8:1) for horizontal screens
            let preferredAspect: CGFloat = isIPad ? 1.8 : 1.5
            let aspectScore = 1.0 / (abs(cellAspect - preferredAspect) + 0.1)
            let fillScore = CGFloat(itemCount) / CGFloat(cols * rows)  // How much of grid is used

            // iPad bonus for more columns (better use of wide screen)
            let columnBonus: CGFloat = isIPad ? (CGFloat(cols) * 0.05) : 0

            let score = aspectScore * fillScore + columnBonus

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
    let song: SetlistSong
    let songs: [SetlistSong]
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
    let song: SetlistSong
    let isActive: Bool
    var isNextUp: Bool = false  // Highlight next song in setlist
    var isDragging: Bool = false
    var isReorderMode: Bool = false
    var isLargeText: Bool = false  // Use large dynamic text (for perform mode)
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false

    /// Background color based on state
    private var backgroundColor: Color {
        if isActive {
            return TEColors.orange
        } else if isNextUp {
            return TEColors.cream.opacity(0.95)  // Subtle highlight for next
        } else {
            return TEColors.warmWhite
        }
    }

    /// Text color based on state
    private var textColor: Color {
        isActive ? .white : TEColors.black
    }

    /// Secondary text color
    private var secondaryTextColor: Color {
        isActive ? .white.opacity(0.7) : TEColors.midGray
    }

    var body: some View {
        GeometryReader { geometry in
            // Calculate font sizes - large dynamic sizing for perform mode, fixed for edit mode
            let minDimension = min(geometry.size.width, geometry.size.height)
            let nameFontSize: CGFloat = isLargeText
                ? max(16, min(minDimension * 0.28, 42))  // 28% of cell, clamped 16-42
                : 14
            let songNameFontSize: CGFloat = isLargeText ? max(10, nameFontSize * 0.45) : 10
            let keyFontSize: CGFloat = isLargeText ? max(10, nameFontSize * 0.4) : 9

            Button(action: onTap) {
                ZStack {
                    VStack(spacing: isLargeText ? minDimension * 0.02 : 3) {
                        Spacer(minLength: 2)

                        // Preset name (main)
                        Text(song.name.uppercased())
                            .font(TEFonts.mono(nameFontSize, weight: isLargeText ? .black : .bold))
                            .foregroundColor(textColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(isLargeText ? 0.5 : 1.0)

                        // Artist name (if set)
                        if let artist = song.artist, !artist.isEmpty {
                            Text(artist.uppercased())
                                .font(TEFonts.mono(songNameFontSize, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .lineLimit(1)
                        }

                        // Key/Scale info (show in perform mode for quick reference)
                        if isLargeText {
                            Text(song.keyShortName.uppercased())
                                .font(TEFonts.mono(keyFontSize, weight: .bold))
                                .foregroundColor(isActive ? .white.opacity(0.85) : TEColors.orange)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 2)
                    }
                    .padding(.horizontal, isLargeText ? 6 : 4)

                    // Corner indicators
                    VStack {
                        HStack(alignment: .top) {
                            // Top-left: BPM indicator (orange dot)
                            if song.bpm != nil {
                                Circle()
                                    .fill(isActive ? .white : TEColors.orange)
                                    .frame(width: isLargeText ? 10 : 7, height: isLargeText ? 10 : 7)
                                    .padding(5)
                            }

                            Spacer()

                            // Top-right: External MIDI indicator (bolt) or drag handle
                            if isReorderMode {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: isLargeText ? 14 : 11, weight: .bold))
                                    .foregroundColor(secondaryTextColor)
                                    .padding(5)
                            } else if !song.externalMIDIMessages.isEmpty {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: isLargeText ? 12 : 9, weight: .bold))
                                    .foregroundColor(isActive ? .white.opacity(0.8) : TEColors.orange)
                                    .padding(5)
                            }
                        }
                        Spacer()
                    }

                    // "Next" indicator (bottom edge glow for next song)
                    if isNextUp && !isActive {
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(TEColors.orange.opacity(0.4))
                                .frame(height: 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(
                            isDragging ? TEColors.orange : (isReorderMode ? TEColors.darkGray : (isNextUp ? TEColors.orange.opacity(0.5) : TEColors.black)),
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
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var midiEngine: MIDIEngine
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
                    .foregroundColor(TEColors.black)
            }

            // BPM display
            HStack(spacing: 4) {
                Text("\(bpm)")
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundColor(TEColors.black)
                Text("BPM")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.midGray)
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

            // DSP Load
            Text("DSP \(Int(audioEngine.cpuUsage))%")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(audioEngine.cpuUsage > 80 ? TEColors.red : TEColors.darkGray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(TEColors.lightGray)
    }
}

// MARK: - Minimal Status Bar (for perform mode)

struct MinimalStatusBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var midiEngine: MIDIEngine
    var bpm: Int = 90

    var body: some View {
        HStack(spacing: 16) {
            // BPM display
            HStack(spacing: 4) {
                Text("\(bpm)")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(TEColors.black)
                Text("BPM")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.midGray)
            }

            // MIDI count
            HStack(spacing: 4) {
                Rectangle()
                    .fill(midiEngine.lastActivity != nil ? TEColors.orange : TEColors.midGray)
                    .frame(width: 6, height: 6)

                Text("MIDI \(midiEngine.connectedSources.count)")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.darkGray)
            }

            Spacer()

            // DSP Load
            Text("DSP \(Int(audioEngine.cpuUsage))%")
                .font(TEFonts.mono(9, weight: .medium))
                .foregroundColor(audioEngine.cpuUsage > 80 ? TEColors.red : TEColors.darkGray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(TEColors.lightGray.opacity(0.6))
    }
}

// MARK: - Setlist Status Bar (Navigation + Status)

struct SetlistStatusBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var midiEngine: MIDIEngine
    var bpm: Int = 90
    let currentIndex: Int?
    let totalSongs: Int
    let currentSongName: String?
    let onPrevious: () -> Void
    let onNext: () -> Void
    var isIPad: Bool = false

    private var canGoPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var canGoNext: Bool {
        guard let index = currentIndex else { return false }
        return index < totalSongs - 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Previous button
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: isIPad ? 18 : 14, weight: .bold))
                    .foregroundColor(canGoPrevious ? TEColors.black : TEColors.lightGray)
                    .frame(width: isIPad ? 50 : 40, height: isIPad ? 44 : 36)
            }
            .disabled(!canGoPrevious)

            Rectangle()
                .fill(TEColors.black.opacity(0.3))
                .frame(width: 1)

            // Song position + name
            VStack(spacing: 1) {
                if let index = currentIndex {
                    Text("\(index + 1)/\(totalSongs)")
                        .font(TEFonts.mono(isIPad ? 10 : 8, weight: .bold))
                        .foregroundColor(TEColors.orange)
                }
                if let name = currentSongName {
                    Text(name.uppercased())
                        .font(TEFonts.mono(isIPad ? 12 : 9, weight: .bold))
                        .foregroundColor(TEColors.black)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: isIPad ? 120 : 80)
            .padding(.horizontal, isIPad ? 12 : 8)

            Rectangle()
                .fill(TEColors.black.opacity(0.3))
                .frame(width: 1)

            // Next button
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: isIPad ? 18 : 14, weight: .bold))
                    .foregroundColor(canGoNext ? TEColors.black : TEColors.lightGray)
                    .frame(width: isIPad ? 50 : 40, height: isIPad ? 44 : 36)
            }
            .disabled(!canGoNext)

            // Spacer to push status to right
            Spacer()

            // Status indicators (compact)
            HStack(spacing: isIPad ? 16 : 10) {
                // BPM
                HStack(spacing: 3) {
                    Text("\(bpm)")
                        .font(TEFonts.mono(isIPad ? 12 : 10, weight: .bold))
                        .foregroundColor(TEColors.black)
                    Text("BPM")
                        .font(TEFonts.mono(isIPad ? 9 : 7, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                }

                // MIDI indicator
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(midiEngine.lastActivity != nil ? TEColors.orange : TEColors.midGray)
                        .frame(width: 6, height: 6)
                    Text("\(midiEngine.connectedSources.count)")
                        .font(TEFonts.mono(isIPad ? 10 : 8, weight: .medium))
                        .foregroundColor(TEColors.darkGray)
                }

                // DSP
                Text("\(Int(audioEngine.cpuUsage))%")
                    .font(TEFonts.mono(isIPad ? 10 : 8, weight: .medium))
                    .foregroundColor(audioEngine.cpuUsage > 80 ? TEColors.red : TEColors.darkGray)
            }
            .padding(.trailing, isIPad ? 16 : 10)
        }
        .frame(height: isIPad ? 44 : 36)
        .background(TEColors.lightGray.opacity(0.8))
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
                        .foregroundColor(TEColors.cream)
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
                        .foregroundColor(TEColors.midGray)
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

// MARK: - Remote Preset Grid View (for Remote Mode)

struct RemotePresetGridView: View {
    let presets: [RemotePreset]
    let selectedIndex: Int?
    let onSelectPreset: (RemotePreset) -> Void

    var body: some View {
        GeometryReader { geometry in
            let itemCount = presets.count
            let spacing: CGFloat = 6
            let padding: CGFloat = 6
            let availableWidth = geometry.size.width - (padding * 2)
            let availableHeight = geometry.size.height - (padding * 2)

            let (columns, rows) = calculateGrid(itemCount: max(1, itemCount), availableWidth: availableWidth, availableHeight: availableHeight)

            let totalHorizontalSpacing = spacing * CGFloat(columns - 1)
            let totalVerticalSpacing = spacing * CGFloat(rows - 1)
            let itemWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(columns)
            let itemHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

            let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(presets) { preset in
                        RemotePresetButton(
                            preset: preset,
                            isActive: selectedIndex == preset.index,
                            width: itemWidth,
                            height: itemHeight,
                            onTap: { onSelectPreset(preset) }
                        )
                    }
                }
                .padding(padding)
            }
        }
    }

    private func calculateGrid(itemCount: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> (columns: Int, rows: Int) {
        guard itemCount > 0 else { return (1, 1) }

        let aspectRatio = availableWidth / availableHeight
        var bestColumns = 1
        var bestRows = 1
        var bestFit: CGFloat = .infinity

        for cols in 1...max(1, itemCount) {
            let rows = Int(ceil(Double(itemCount) / Double(cols)))
            let gridAspect = CGFloat(cols) / CGFloat(rows)
            let fit = abs(gridAspect - aspectRatio)

            if fit < bestFit {
                bestFit = fit
                bestColumns = cols
                bestRows = rows
            }
        }

        return (bestColumns, bestRows)
    }
}

struct RemotePresetButton: View {
    let preset: RemotePreset
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        let minDimension = min(width, height)
        let isLargeText = minDimension > 100
        let nameFontSize: CGFloat = isLargeText
            ? min(minDimension * 0.18, 36)
            : 14

        Button(action: onTap) {
            ZStack {
                VStack(spacing: isLargeText ? minDimension * 0.03 : 4) {
                    Spacer(minLength: 4)

                    // Preset name
                    Text(preset.name.uppercased())
                        .font(TEFonts.mono(nameFontSize, weight: isLargeText ? .black : .bold))
                        .foregroundColor(isActive ? .white : TEColors.black)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)

                    // Key display
                    if let key = preset.keyDisplayName {
                        Text(key.uppercased())
                            .font(TEFonts.mono(isLargeText ? 12 : 10, weight: .medium))
                            .foregroundColor(isActive ? .white.opacity(0.7) : TEColors.midGray)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, isLargeText ? 8 : 4)

                // BPM indicator
                if preset.bpm != nil {
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

                // External MIDI indicator (has Helix messages)
                if !preset.externalMIDIMessages.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "bolt.fill")
                                .font(.system(size: isLargeText ? 12 : 10, weight: .bold))
                                .foregroundColor(isActive ? .white.opacity(0.7) : TEColors.orange)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: width, height: height)
            .background(isActive ? TEColors.orange : TEColors.warmWhite)
            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: isActive ? 3 : 2))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Preview

#Preview {
    PerformanceView()
}
