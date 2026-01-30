import SwiftUI

/// Settings view for the Performance Engine - TE Style
struct PerformanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audioEngine = AudioEngine.shared
    @State private var midiEngine = MIDIEngine.shared
    @State private var sessionStore = SessionStore.shared
    @State private var pluginManager = AUv3HostManager.shared
    @State private var appearanceManager = AppearanceManager.shared

    @State private var showingSaveAs = false
    @State private var newSessionName = ""
    @State private var showingResetChannelsConfirmation = false
    @State private var showingResetPresetsConfirmation = false
    @State private var showingChordMap = false
    @State private var showingBluetoothMIDI = false
    @State private var showingSessionList = false
    @State private var sessionToDelete: Session?
    @State private var toastMessage: String?
    
    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        audioSection
                        midiSection
                        midiOutputSection
                        scaleFilterSection
                        pluginsSection
                        appearanceSection
                        sessionSection
                        aboutSection
                    }
                    .padding(20)
                }
            }

            // Toast notification
            if let message = toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: message)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: toastMessage)
            }
        }
        .preferredColorScheme(appearanceManager.colorScheme)
        .sheet(isPresented: $showingSaveAs) {
            SaveSessionSheet(
                sessionName: $newSessionName,
                onSave: {
                    if !newSessionName.isEmpty {
                        let name = newSessionName
                        sessionStore.saveSessionAs(name)
                        newSessionName = ""
                        showingSaveAs = false
                        showToast("SAVED AS '\(name.uppercased())'")
                    }
                },
                onCancel: {
                    newSessionName = ""
                    showingSaveAs = false
                }
            )
            .presentationDetents([.height(220)])
        }
        .confirmationDialog("RESET CHANNELS", isPresented: $showingResetChannelsConfirmation, titleVisibility: .visible) {
            Button("Reset All Channels", role: .destructive) {
                resetChannels()
            }
        } message: {
            Text("This will remove all channels and their instruments. This cannot be undone.")
        }
        .confirmationDialog("RESET PRESETS", isPresented: $showingResetPresetsConfirmation, titleVisibility: .visible) {
            Button("Reset All Presets", role: .destructive) {
                resetPresets()
            }
        } message: {
            Text("This will remove all presets and create a single default preset. This cannot be undone.")
        }
        .sheet(isPresented: $showingChordMap) {
            ChordMapView()
        }
        .sheet(isPresented: $showingBluetoothMIDI) {
            BluetoothMIDIView()
        }
        .sheet(isPresented: $showingSessionList) {
            SessionListView(
                sessions: sessionStore.savedSessions,
                onLoad: { session in
                    loadSession(session)
                    showingSessionList = false
                },
                onDelete: { session in
                    sessionToDelete = session
                }
            )
        }
        .confirmationDialog("DELETE SESSION", isPresented: .init(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    sessionStore.deleteSession(session)
                    sessionToDelete = nil
                }
            }
        } message: {
            Text("Delete '\(sessionToDelete?.name ?? "")'? This cannot be undone.")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("SETTINGS")
                .font(TEFonts.display(20, weight: .black))
                .foregroundStyle(TEColors.black)
                .tracking(4)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(TEColors.black)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Audio Section
    
    private var audioSection: some View {
        TESettingsSection(title: "AUDIO") {
            VStack(spacing: 16) {
                TESettingsRow(label: "ENGINE") {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(audioEngine.isRunning ? TEColors.green : TEColors.red)
                            .frame(width: 8, height: 8)
                        Text(audioEngine.isRunning ? "RUN" : "OFF")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundStyle(TEColors.black)
                    }
                }
                
                TESettingsRow(label: "CHANNELS") {
                    Text("\(audioEngine.channelStrips.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("MASTER")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                        Spacer()
                        Text("\(Int(audioEngine.masterVolume * 100))")
                            .font(TEFonts.mono(14, weight: .bold))
                            .foregroundStyle(TEColors.black)
                    }
                    
                    TESlider(value: Binding(
                        get: { audioEngine.masterVolume },
                        set: { audioEngine.masterVolume = $0 }
                    ))
                }
            }
        }
    }
    
    // MARK: - MIDI Section
    
    private var midiSection: some View {
        TESettingsSection(title: "MIDI") {
            VStack(spacing: 16) {
                TESettingsRow(label: "SOURCES") {
                    Text("\(midiEngine.connectedSources.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }
                
                if !midiEngine.connectedSources.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(midiEngine.connectedSources) { source in
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(TEColors.green)
                                    .frame(width: 6, height: 6)
                                Text(source.name.uppercased())
                                    .font(TEFonts.mono(10, weight: .medium))
                                    .foregroundStyle(TEColors.darkGray)
                                Spacer()
                            }
                        }
                    }
                }
                
                if let lastMessage = midiEngine.lastReceivedMessage {
                    TESettingsRow(label: "LAST MSG") {
                        Text(lastMessage.uppercased())
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundStyle(TEColors.orange)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - MIDI Output Section

    private var midiOutputSection: some View {
        TESettingsSection(title: "MIDI OUTPUT") {
            VStack(spacing: 16) {
                // Network MIDI subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("NETWORK SESSION")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)

                    Text("Creates a WiFi MIDI session using your device name. Other devices on your network can connect to send MIDI here.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    TEToggle(label: "ENABLED", isOn: $midiEngine.isNetworkSessionEnabled)

                    if midiEngine.isNetworkSessionEnabled {
                        HStack {
                            Text("SESSION")
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundStyle(TEColors.midGray)

                            Spacer()

                            Text(midiEngine.networkSessionName.uppercased())
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundStyle(TEColors.orange)
                        }
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )

                // Bluetooth MIDI subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("BLUETOOTH DEVICES")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)

                    Text("Pair with Bluetooth MIDI devices (like WIDI). They'll appear as destinations below.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showingBluetoothMIDI = true
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("PAIR DEVICE")
                                .font(TEFonts.mono(11, weight: .bold))
                        }
                        .foregroundStyle(TEColors.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )

                // Divider
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Scan devices button
                Button {
                    midiEngine.refreshDestinations()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text("SCAN DESTINATIONS")
                            .font(TEFonts.mono(11, weight: .bold))
                    }
                    .foregroundStyle(TEColors.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
                }

                // Destination picker
                SettingsPicker(
                    label: "SEND TO",
                    selection: Binding(
                        get: { midiEngine.selectedDestinationEndpoint },
                        set: { midiEngine.selectedDestinationEndpoint = $0 }
                    ),
                    options: [(nil, "NONE")] + midiEngine.availableDestinations.map { ($0.endpoint, $0.name.uppercased()) },
                    displayValue: selectedDestinationLabel,
                    valueColor: midiEngine.selectedDestinationEndpoint == nil ? TEColors.midGray : TEColors.black
                )

                if midiEngine.availableDestinations.isEmpty {
                    Text("No destinations found. Enable Network Session or pair a Bluetooth device.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Channel picker
                SettingsPicker(
                    label: "CHANNEL",
                    selection: $midiEngine.externalMIDIChannel,
                    options: (1...16).map { ($0, "CH \($0)") },
                    displayValue: "CH \(midiEngine.externalMIDIChannel)"
                )

                // Divider
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Tempo sync subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("TEMPO SYNC")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)

                    Text("Sends tap tempo to external devices when selecting songs with BPM. Helix uses CC 64 by default.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    TEToggle(label: "ENABLED", isOn: $midiEngine.isExternalTempoSyncEnabled)

                    if midiEngine.isExternalTempoSyncEnabled {
                        SettingsPicker(
                            label: "TAP TEMPO CC",
                            selection: $midiEngine.tapTempoCC,
                            options: [64, 1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120].map { 
                                ($0, $0 == 64 ? "CC 64 (HELIX DEFAULT)" : "CC \($0)")
                            },
                            displayValue: "CC \(midiEngine.tapTempoCC)"
                        )
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )
            }
        }
    }

    private var selectedDestinationLabel: String {
        guard let endpoint = midiEngine.selectedDestinationEndpoint,
              let dest = midiEngine.availableDestinations.first(where: { $0.endpoint == endpoint }) else {
            return "NONE"
        }
        return dest.name.uppercased()
    }

    // MARK: - Scale Filter Section

    private var scaleFilterSection: some View {
        TESettingsSection(title: "SCALE FILTER") {
            VStack(spacing: 16) {
                TEToggle(label: "ENABLED", isOn: $midiEngine.isScaleFilterEnabled)

                TESettingsRow(label: "CURRENT KEY") {
                    Text("\(NoteName(rawValue: midiEngine.currentRootNote)?.displayName ?? "C") \(midiEngine.currentScaleType.rawValue.uppercased())")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.orange)
                }

                // ChordPad Controller (required - no "ANY" option)
                chordPadSourcePicker

                // Chord Zone Channel
                SettingsPicker(
                    label: "CHORD CH",
                    selection: $midiEngine.chordZoneChannel,
                    options: [(0, "ANY")] + (1...16).map { ($0, "CH \($0)") },
                    displayValue: midiEngine.chordZoneChannel == 0 ? "ANY" : "CH \(midiEngine.chordZoneChannel)"
                )

                // Single Note Zone Channel
                SettingsPicker(
                    label: "NOTE CH",
                    selection: $midiEngine.singleNoteZoneChannel,
                    options: [(0, "ANY")] + (1...16).map { ($0, "CH \($0)") },
                    displayValue: midiEngine.singleNoteZoneChannel == 0 ? "ANY" : "CH \(midiEngine.singleNoteZoneChannel)"
                )

                // ChordPad Map button
                Button {
                    showingChordMap = true
                } label: {
                    HStack {
                        Image(systemName: "pianokeys")
                            .font(.system(size: 12, weight: .bold))
                        Text("CHORD MAP")
                            .font(TEFonts.mono(11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(TEColors.orange)
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }
            }
        }
    }
    
    // MARK: - Plugins Section
    
    private var pluginsSection: some View {
        TESettingsSection(title: "PLUGINS") {
            VStack(spacing: 16) {
                TESettingsRow(label: "INSTRUMENTS") {
                    Text("\(pluginManager.availableInstruments.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }
                
                TESettingsRow(label: "EFFECTS") {
                    Text("\(pluginManager.availableEffects.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }
                
                Button {
                    pluginManager.scanForPlugins()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text("RESCAN")
                            .font(TEFonts.mono(11, weight: .bold))
                    }
                    .foregroundStyle(TEColors.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
                }
            }
        }
    }
    
    // MARK: - Appearance Section

    private var appearanceSection: some View {
        TESettingsSection(title: "APPEARANCE") {
            VStack(spacing: 16) {
                HStack {
                    Text("THEME")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)

                    Spacer()

                    HStack(spacing: 0) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Button {
                                appearanceManager.currentAppearance = appearance
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: appearance.icon)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(appearance.displayName)
                                        .font(TEFonts.mono(9, weight: .bold))
                                }
                                .foregroundStyle(appearanceManager.currentAppearance == appearance ? .white : TEColors.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(appearanceManager.currentAppearance == appearance ? TEColors.orange : TEColors.cream)
                            }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }

                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Orientation Lock
                VStack(spacing: 12) {
                    TEToggle(label: "LOCK ORIENTATION", isOn: $appearanceManager.isOrientationLocked)

                    if appearanceManager.isOrientationLocked {
                        HStack {
                            Text("LOCK TO")
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundStyle(TEColors.midGray)

                            Spacer()

                            HStack(spacing: 0) {
                                ForEach(LockedOrientation.allCases, id: \.self) { orientation in
                                    Button {
                                        appearanceManager.lockedOrientation = orientation
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: orientation.icon)
                                                .font(.system(size: 10, weight: .bold))
                                            Text(orientation.displayName)
                                                .font(TEFonts.mono(9, weight: .bold))
                                        }
                                        .foregroundStyle(appearanceManager.lockedOrientation == orientation ? .white : TEColors.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(appearanceManager.lockedOrientation == orientation ? TEColors.orange : TEColors.cream)
                                    }
                                }
                            }
                            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Session Section

    private var sessionSection: some View {
        TESettingsSection(title: "SESSION") {
            VStack(spacing: 16) {
                TESettingsRow(label: "CURRENT") {
                    Text(sessionStore.currentSession.name.uppercased())
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }

                TESettingsRow(label: "PRESETS") {
                    Text("\(sessionStore.currentSession.songs.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }

                TESettingsRow(label: "CHANNELS") {
                    Text("\(sessionStore.currentSession.channels.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }

                // Save button (updates existing saved session or prompts for new name)
                Button {
                    if sessionStore.updateSavedSession() {
                        showToast("SESSION SAVED")
                    } else {
                        showingSaveAs = true
                    }
                } label: {
                    Text("SAVE")
                        .font(TEFonts.mono(11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(TEColors.orange)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }

                HStack(spacing: 12) {
                    Button {
                        showingSaveAs = true
                    } label: {
                        Text("SAVE AS")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.black, lineWidth: 2)
                            )
                    }

                    Button {
                        showingSessionList = true
                    } label: {
                        Text("LOAD")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.black, lineWidth: 2)
                            )
                    }
                    .disabled(sessionStore.savedSessions.isEmpty)
                    .opacity(sessionStore.savedSessions.isEmpty ? 0.5 : 1)
                }

                HStack(spacing: 12) {
                    Button {
                        showingResetChannelsConfirmation = true
                    } label: {
                        Text("RESET CHANNELS")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.red, lineWidth: 2)
                            )
                    }

                    Button {
                        showingResetPresetsConfirmation = true
                    } label: {
                        Text("RESET PRESETS")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.red, lineWidth: 2)
                            )
                    }
                }
            }
        }
    }
    
    // MARK: - About Section

    private var aboutSection: some View {
        TESettingsSection(title: "ABOUT") {
            VStack(spacing: 8) {
                TESettingsRow(label: "VERSION") {
                    Text("1.0")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                }

                Text("KEYFRAME PERFORMANCE ENGINE")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Reset Functions

    private func resetChannels() {
        // Remove all channel strips from audio engine
        audioEngine.removeAllChannels()
        // Clear channels from session
        sessionStore.currentSession.channels.removeAll()
        sessionStore.saveCurrentSession()
    }

    private func resetPresets() {
        // Reset to single default preset
        let defaultPreset = PerformanceSong(name: "DEFAULT", rootNote: 0, scaleType: .major, bpm: 120, order: 0)
        sessionStore.currentSession.songs = [defaultPreset]
        sessionStore.currentSession.activeSongId = defaultPreset.id
        sessionStore.saveCurrentSession()
    }

    private func loadSession(_ session: Session) {
        // Clear current audio engine channels
        audioEngine.removeAllChannels()

        // Load the session into the store
        sessionStore.loadSession(session)

        // Capture references to the shared singletons (they're classes, safe to capture)
        let audioEngine = self.audioEngine
        let sessionStore = self.sessionStore
        let midiEngine = self.midiEngine
        let sessionName = session.name

        // Restore plugins from the loaded session
        audioEngine.restorePlugins(from: session.channels) {
            DispatchQueue.main.async {
                // Sync channel configs (MIDI routing, volume, etc.)
                for (index, config) in sessionStore.currentSession.channels.enumerated() {
                    if index < audioEngine.channelStrips.count {
                        let strip = audioEngine.channelStrips[index]
                        strip.midiChannel = config.midiChannel
                        strip.midiSourceName = config.midiSourceName
                        strip.scaleFilterEnabled = config.scaleFilterEnabled
                        strip.isChordPadTarget = config.isChordPadTarget
                        strip.octaveTranspose = config.octaveTranspose
                        strip.volume = config.volume
                        strip.pan = config.pan
                        strip.isMuted = config.isMuted
                    }
                }

                // Apply active song settings (scale, BPM)
                if let activeSong = sessionStore.currentSession.activeSong {
                    let legacySong = Song(
                        name: activeSong.name,
                        rootNote: activeSong.rootNote,
                        scaleType: activeSong.scaleType,
                        filterMode: activeSong.filterMode,
                        preset: .empty,
                        bpm: activeSong.bpm
                    )
                    midiEngine.applySongSettings(legacySong)

                    // Set tempo for hosted plugins
                    if let bpm = activeSong.bpm {
                        audioEngine.setTempo(Double(bpm))
                    }
                }

                // Start audio engine if not running
                if !audioEngine.isRunning {
                    audioEngine.start()
                }

                print("SessionStore: Loaded session '\(sessionName)' - plugins ready")
            }
        }

        // Show toast immediately (loading happens in background with progress indicator)
        showToast("LOADING '\(session.name.uppercased())'...")
    }

    private func showToast(_ message: String) {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation {
            toastMessage = message
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private func chordPadSourceLabel(isOffline: Bool) -> String {
        guard let sourceName = midiEngine.chordPadSourceName else {
            return "NONE"
        }
        if isOffline {
            return "\(sourceName.uppercased()) (OFFLINE)"
        }
        return sourceName.uppercased()
    }
    
    /// ChordPad source picker with offline device handling
    private var chordPadSourcePicker: some View {
        let connectedNames = Set(midiEngine.connectedSources.map { $0.name })
        let isOffline = midiEngine.chordPadSourceName != nil && !connectedNames.contains(midiEngine.chordPadSourceName!)
        
        // Build options list
        var options: [(key: String?, value: String)] = [(nil, "NONE (DISABLED)")]
        options += midiEngine.connectedSources.map { ($0.name as String?, $0.name.uppercased()) }
        // Show saved offline source as an option to keep it selected
        if let savedSource = midiEngine.chordPadSourceName, isOffline {
            options.append((savedSource, "\(savedSource.uppercased()) (OFFLINE)"))
        }
        
        return SettingsPicker(
            label: "CHORDPAD",
            selection: $midiEngine.chordPadSourceName,
            options: options,
            displayValue: chordPadSourceLabel(isOffline: isOffline),
            valueColor: midiEngine.chordPadSourceName == nil ? TEColors.midGray : (isOffline ? TEColors.orange : TEColors.black)
        )
    }
}

// MARK: - TE Settings Section

struct TESettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
        }
    }
}

// MARK: - TE Settings Row

struct TESettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack {
            Text(label)
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(TEColors.midGray)
            
            Spacer()
            
            content
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TEColors.green)

            Text(message)
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(TEColors.black)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Session List View

struct SessionListView: View {
    @Environment(\.dismiss) private var dismiss
    let sessions: [Session]
    let onLoad: (Session) -> Void
    let onDelete: (Session) -> Void

    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SAVED SESSIONS")
                        .font(TEFonts.display(16, weight: .black))
                        .foregroundStyle(TEColors.black)
                        .tracking(2)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("CLOSE")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.darkGray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(TEColors.warmWhite)

                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)

                if sessions.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(TEColors.midGray)
                        Text("NO SAVED SESSIONS")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundStyle(TEColors.midGray)
                        Text("Use 'Save As' to save your current session")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(sessions) { session in
                                SessionRow(
                                    session: session,
                                    onLoad: { onLoad(session) },
                                    onDelete: { onDelete(session) }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .preferredColorScheme(AppearanceManager.shared.colorScheme)
    }
}

struct SessionRow: View {
    let session: Session
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name.uppercased())
                    .font(TEFonts.mono(14, weight: .bold))
                    .foregroundStyle(TEColors.black)

                HStack(spacing: 12) {
                    Text("\(session.channels.count) CH")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)

                    Text("\(session.songs.count) PRESETS")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onLoad) {
                    Text("LOAD")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(TEColors.orange)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TEColors.red)
                        .padding(8)
                }
            }
        }
        .padding(16)
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
}

// MARK: - Save Session Sheet

struct SaveSessionSheet: View {
    @Binding var sessionName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                Text("SAVE SESSION")
                    .font(TEFonts.display(18, weight: .black))
                    .foregroundStyle(TEColors.black)
                    .tracking(2)

                // Text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("SESSION NAME")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundStyle(TEColors.midGray)

                    TextField("Enter name", text: $sessionName)
                        .font(TEFonts.mono(14, weight: .bold))
                        .foregroundStyle(TEColors.black)
                        .textInputAutocapitalization(.characters)
                        .padding(12)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                                .background(TEColors.warmWhite)
                        )
                }

                // Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(TEColors.darkGray)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.darkGray, lineWidth: 2)
                            )
                    }

                    Button(action: onSave) {
                        Text("SAVE")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(TEColors.orange)
                            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }
                    .disabled(sessionName.isEmpty)
                    .opacity(sessionName.isEmpty ? 0.5 : 1)
                }
            }
            .padding(20)
        }
        .preferredColorScheme(AppearanceManager.shared.colorScheme)
    }
}

// MARK: - Settings Picker (Sheet-based, faster than Menu on iOS 18)

struct SettingsPicker<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(key: T, value: String)]
    let displayValue: String
    var valueColor: Color = TEColors.black
    
    @State private var showingSheet = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(TEColors.midGray)
            
            Spacer()
            
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 8) {
                    Text(displayValue)
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                )
            }
        }
        .sheet(isPresented: $showingSheet) {
            SettingsPickerSheet(
                title: label,
                selection: $selection,
                options: options,
                isPresented: $showingSheet
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct SettingsPickerSheet<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(key: T, value: String)]
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.key) { index, option in
                        Button {
                            selection = option.key
                            isPresented = false
                        } label: {
                            HStack {
                                Text(option.value)
                                    .font(TEFonts.mono(14, weight: selection == option.key ? .bold : .medium))
                                    .foregroundStyle(TEColors.black)

                                Spacer()

                                if selection == option.key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(TEColors.orange)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(selection == option.key ? TEColors.orange.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < options.count - 1 {
                            Rectangle()
                                .fill(TEColors.lightGray.opacity(0.6))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(TEColors.cream)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") {
                        isPresented = false
                    }
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundStyle(TEColors.orange)
                }
            }
        }
        .preferredColorScheme(AppearanceManager.shared.colorScheme)
    }
}

// MARK: - Preview

#Preview {
    PerformanceSettingsView()
}
