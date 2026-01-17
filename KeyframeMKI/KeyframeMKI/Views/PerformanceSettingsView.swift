import SwiftUI

/// Settings view for the Performance Engine - TE Style
struct PerformanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared

    @State private var showingSaveAs = false
    @State private var newSessionName = ""
    @State private var showingResetChannelsConfirmation = false
    @State private var showingResetPresetsConfirmation = false
    @State private var showingChordMap = false
    @State private var showingBluetoothMIDI = false
    @State private var showingSessionList = false
    @State private var sessionToDelete: Session?
    @State private var toastMessage: String?

    /// Name of currently selected remote host, or placeholder
    private var remoteHostName: String {
        if let endpoint = midiEngine.remoteHostEndpoint,
           let dest = midiEngine.availableDestinations.first(where: { $0.endpoint == endpoint }) {
            return dest.name
        }
        return "Select Mac..."
    }

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
                        freezeSection
                        looperSection
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
                .foregroundColor(TEColors.black)
                .tracking(4)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(.white)
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
                            .foregroundColor(TEColors.black)
                    }
                }
                
                TESettingsRow(label: "CHANNELS") {
                    Text("\(audioEngine.channelStrips.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("MASTER")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                        Spacer()
                        Text("\(Int(audioEngine.masterVolume * 100))")
                            .font(TEFonts.mono(14, weight: .bold))
                            .foregroundColor(TEColors.black)
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
                        .foregroundColor(TEColors.black)
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
                                    .foregroundColor(TEColors.darkGray)
                                Spacer()
                            }
                        }
                    }
                }
                
                if let lastMessage = midiEngine.lastReceivedMessage {
                    TESettingsRow(label: "LAST MSG") {
                        Text(lastMessage.uppercased())
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundColor(TEColors.orange)
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
                        .foregroundColor(TEColors.darkGray)

                    Text("Creates a WiFi MIDI session using your device name. Other devices on your network can connect to send MIDI here.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    TEToggle(label: "ENABLED", isOn: $midiEngine.isNetworkSessionEnabled)

                    if midiEngine.isNetworkSessionEnabled {
                        HStack {
                            Text("SESSION")
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundColor(TEColors.midGray)

                            Spacer()

                            Text(midiEngine.networkSessionName.uppercased())
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(TEColors.orange)
                        }
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )

                // Remote Mode subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("REMOTE MODE")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Text("Connect to Keyframe Mac app via Network MIDI. Preset changes control Mac synths while Helix output goes direct.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    TEToggle(label: "REMOTE MODE", isOn: $midiEngine.isRemoteMode)

                    if midiEngine.isRemoteMode {
                        // Remote host picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MAC HOST")
                                .font(TEFonts.mono(9, weight: .bold))
                                .foregroundColor(TEColors.darkGray)

                            Menu {
                                Button("None") {
                                    midiEngine.remoteHostEndpoint = nil
                                }
                                ForEach(midiEngine.availableDestinations) { dest in
                                    Button(dest.name) {
                                        midiEngine.remoteHostEndpoint = dest.endpoint
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "macbook")
                                        .font(.system(size: 12))
                                    Text(remoteHostName)
                                        .font(TEFonts.mono(11, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                }
                                .padding(8)
                                .background(TEColors.cream)
                                .foregroundColor(midiEngine.remoteHostEndpoint != nil ? TEColors.orange : TEColors.midGray)
                            }
                        }

                        if midiEngine.remoteHostEndpoint != nil {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text("Connected to Mac")
                                    .font(TEFonts.mono(9, weight: .medium))
                                    .foregroundColor(.green)
                            }

                            // Pull presets button
                            Button {
                                midiEngine.pullPresetsFromMac()
                            } label: {
                                HStack {
                                    if midiEngine.isPullingPresets {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: TEColors.black))
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    Text(midiEngine.isPullingPresets ? "PULLING..." : "PULL PRESETS FROM MAC")
                                        .font(TEFonts.mono(11, weight: .bold))
                                }
                                .foregroundColor(TEColors.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Rectangle()
                                        .stroke(TEColors.black, lineWidth: 2)
                                )
                            }
                            .disabled(midiEngine.isPullingPresets)
                            .padding(.top, 8)

                            // Remote presets count
                            if !midiEngine.remotePresets.isEmpty {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 12))
                                    Text("\(midiEngine.remotePresets.count) presets from Mac")
                                        .font(TEFonts.mono(9, weight: .medium))
                                    Spacer()
                                }
                                .foregroundColor(TEColors.darkGray)
                                .padding(.top, 4)
                            }
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("Select Mac from Network MIDI")
                                    .font(TEFonts.mono(9, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(midiEngine.isRemoteMode ? TEColors.orange.opacity(0.1) : TEColors.cream)
                )

                // Bluetooth MIDI subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("BLUETOOTH DEVICES")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Text("Pair with Bluetooth MIDI devices (like WIDI). They'll appear as destinations below.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
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
                        .foregroundColor(TEColors.black)
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
                    .foregroundColor(TEColors.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
                }

                // Destination picker
                HStack {
                    Text("SEND TO")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    Menu {
                        Button("NONE") {
                            midiEngine.selectedDestinationEndpoint = nil
                        }
                        ForEach(midiEngine.availableDestinations) { dest in
                            Button(dest.name.uppercased()) {
                                midiEngine.selectedDestinationEndpoint = dest.endpoint
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(selectedDestinationLabel)
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(midiEngine.selectedDestinationEndpoint == nil ? TEColors.midGray : TEColors.black)
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TEColors.darkGray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                    }
                }

                if midiEngine.availableDestinations.isEmpty {
                    Text("No destinations found. Enable Network Session or pair a Bluetooth device.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Channel picker
                HStack {
                    Text("CHANNEL")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    Menu {
                        ForEach(1...16, id: \.self) { ch in
                            Button("CH \(ch)") {
                                midiEngine.externalMIDIChannel = ch
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("CH \(midiEngine.externalMIDIChannel)")
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(TEColors.black)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TEColors.darkGray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                    }
                }

                // Divider
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Tempo sync subsection
                VStack(alignment: .leading, spacing: 12) {
                    Text("TEMPO SYNC")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Text("Sends tap tempo to external devices when selecting songs with BPM. Helix uses CC 64 by default.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    TEToggle(label: "ENABLED", isOn: $midiEngine.isExternalTempoSyncEnabled)

                    if midiEngine.isExternalTempoSyncEnabled {
                        HStack {
                            Text("TAP TEMPO CC")
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundColor(TEColors.midGray)

                            Spacer()

                            Menu {
                                Button("CC 64 (HELIX DEFAULT)") {
                                    midiEngine.tapTempoCC = 64
                                }
                                ForEach([1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120], id: \.self) { cc in
                                    if cc != 64 {
                                        Button("CC \(cc)") {
                                            midiEngine.tapTempoCC = cc
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("CC \(midiEngine.tapTempoCC)")
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .foregroundColor(TEColors.black)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(TEColors.darkGray)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Rectangle()
                                        .strokeBorder(TEColors.black, lineWidth: 2)
                                )
                            }
                        }
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

    // MARK: - Freeze/Hold Section

    private var freezeSection: some View {
        TESettingsSection(title: "FREEZE/HOLD") {
            VStack(spacing: 16) {
                // Mode picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("MODE")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Text(freezeModeDescription)
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ForEach(FreezeMode.allCases, id: \.self) { mode in
                            Button {
                                sessionStore.currentSession.freezeMode = mode
                                midiEngine.freezeMode = mode
                                sessionStore.saveCurrentSession()
                            } label: {
                                Text(mode.rawValue.uppercased())
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundColor(sessionStore.currentSession.freezeMode == mode ? .white : TEColors.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        Rectangle()
                                            .fill(sessionStore.currentSession.freezeMode == mode ? TEColors.orange : TEColors.warmWhite)
                                    )
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(TEColors.black, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Trigger mapping
                VStack(alignment: .leading, spacing: 12) {
                    Text("TRIGGER MAPPING")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    // Current mapping display
                    HStack {
                        Text("CC")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)

                        Spacer()

                        Text(freezeTriggerLabel)
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(sessionStore.currentSession.freezeTriggerCC == nil ? TEColors.midGray : TEColors.orange)
                    }

                    // Learn button
                    Button {
                        if midiEngine.isFreezeLearnMode {
                            midiEngine.isFreezeLearnMode = false
                        } else {
                            midiEngine.isFreezeLearnMode = true
                            midiEngine.onFreezeLearn = { cc, channel, sourceName in
                                sessionStore.currentSession.freezeTriggerCC = cc
                                sessionStore.currentSession.freezeTriggerChannel = channel
                                sessionStore.currentSession.freezeTriggerSourceName = sourceName
                                midiEngine.freezeTriggerCC = cc
                                midiEngine.freezeTriggerChannel = channel
                                midiEngine.freezeTriggerSourceName = sourceName
                                sessionStore.saveCurrentSession()
                            }
                        }
                    } label: {
                        HStack {
                            if midiEngine.isFreezeLearnMode {
                                Circle()
                                    .fill(TEColors.red)
                                    .frame(width: 8, height: 8)
                                Text("WAITING FOR CC...")
                                    .font(TEFonts.mono(11, weight: .bold))
                            } else {
                                Image(systemName: "graduationcap")
                                    .font(.system(size: 12, weight: .bold))
                                Text("LEARN TRIGGER")
                                    .font(TEFonts.mono(11, weight: .bold))
                            }
                        }
                        .foregroundColor(midiEngine.isFreezeLearnMode ? .white : TEColors.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Rectangle()
                                .fill(midiEngine.isFreezeLearnMode ? TEColors.red : TEColors.cream)
                        )
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }

                    // Clear mapping button
                    if sessionStore.currentSession.freezeTriggerCC != nil {
                        Button {
                            sessionStore.currentSession.freezeTriggerCC = nil
                            sessionStore.currentSession.freezeTriggerChannel = nil
                            sessionStore.currentSession.freezeTriggerSourceName = nil
                            midiEngine.clearFreezeTrigger()
                            sessionStore.saveCurrentSession()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 12, weight: .bold))
                                Text("CLEAR MAPPING")
                                    .font(TEFonts.mono(11, weight: .bold))
                            }
                            .foregroundColor(TEColors.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.red, lineWidth: 2)
                            )
                        }
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )

                // Status indicator
                if midiEngine.isFreezeActive {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TEColors.red)
                        Text("FREEZE ACTIVE")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundColor(TEColors.red)
                        Spacer()
                    }
                }
            }
        }
    }

    private var freezeModeDescription: String {
        switch sessionStore.currentSession.freezeMode {
        case .sustain:
            return "Notes sustain while the trigger is held. Release to stop."
        case .toggle:
            return "Tap to freeze notes, tap again to release. Latching mode."
        }
    }

    private var freezeTriggerLabel: String {
        guard let cc = sessionStore.currentSession.freezeTriggerCC else {
            return "NOT MAPPED"
        }
        var label = "CC \(cc)"
        if let channel = sessionStore.currentSession.freezeTriggerChannel {
            label += " CH \(channel)"
        }
        if let source = sessionStore.currentSession.freezeTriggerSourceName {
            label += " (\(source))"
        }
        return label
    }

    // MARK: - Looper Section

    private var looperSection: some View {
        TESettingsSection(title: "LOOPER") {
            VStack(spacing: 16) {
                // Status display
                if let looper = audioEngine.looper {
                    TESettingsRow(label: "STATUS") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(looperStatusColor(looper.state))
                                .frame(width: 8, height: 8)
                            Text(looper.statusText)
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(TEColors.black)
                        }
                    }

                    if looper.state != .empty {
                        TESettingsRow(label: "DURATION") {
                            Text(looper.durationString)
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(looper.state == .recording ? TEColors.red : TEColors.black)
                        }
                    }
                }

                // Length mode picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("RECORDING LENGTH")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Text("Free mode records until you stop. Bar-based modes auto-stop at the specified length.")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                        .fixedSize(horizontal: false, vertical: true)

                    // Length mode buttons
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(LooperLengthMode.allCases, id: \.self) { mode in
                            Button {
                                audioEngine.looper?.lengthMode = mode
                            } label: {
                                Text(mode.rawValue.uppercased())
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundColor(audioEngine.looper?.lengthMode == mode ? .white : TEColors.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        Rectangle()
                                            .fill(audioEngine.looper?.lengthMode == mode ? TEColors.orange : TEColors.warmWhite)
                                    )
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(TEColors.black, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .fill(TEColors.cream)
                )

                // Clear button
                if let looper = audioEngine.looper, looper.state != .empty {
                    Button {
                        audioEngine.looper?.clear()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .bold))
                            Text("CLEAR LOOP")
                                .font(TEFonts.mono(11, weight: .bold))
                        }
                        .foregroundColor(TEColors.red)
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

    private func looperStatusColor(_ state: LooperState) -> Color {
        switch state {
        case .empty: return TEColors.midGray
        case .recording: return TEColors.red
        case .playing: return TEColors.green
        case .stopped: return TEColors.orange
        }
    }

    // MARK: - Scale Filter Section

    private var scaleFilterSection: some View {
        TESettingsSection(title: "SCALE FILTER") {
            VStack(spacing: 16) {
                TEToggle(label: "ENABLED", isOn: $midiEngine.isScaleFilterEnabled)

                TESettingsRow(label: "CURRENT KEY") {
                    Text("\(NoteName(rawValue: midiEngine.currentRootNote)?.displayName ?? "C") \(midiEngine.currentScaleType.rawValue.uppercased())")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.orange)
                }

                // ChordPad Controller (required - no "ANY" option)
                HStack {
                    Text("CHORDPAD")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    let connectedNames = Set(midiEngine.connectedSources.map { $0.name })
                    let isOffline = midiEngine.chordPadSourceName != nil && !connectedNames.contains(midiEngine.chordPadSourceName!)

                    Menu {
                        Button("NONE (DISABLED)") {
                            midiEngine.chordPadSourceName = nil
                        }
                        ForEach(midiEngine.connectedSources) { source in
                            Button(source.name.uppercased()) {
                                midiEngine.chordPadSourceName = source.name
                            }
                        }
                        // Show saved offline source as an option to keep it selected
                        if let savedSource = midiEngine.chordPadSourceName, isOffline {
                            Button("\(savedSource.uppercased()) (OFFLINE)") {
                                // Keep the same selection
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(chordPadSourceLabel(isOffline: isOffline))
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(midiEngine.chordPadSourceName == nil ? TEColors.midGray : (isOffline ? TEColors.orange : TEColors.black))
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TEColors.darkGray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                    }
                }

                // ChordPad Channel
                HStack {
                    Text("CHANNEL")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    Menu {
                        ForEach(1...16, id: \.self) { ch in
                            Button("CH \(ch)") {
                                midiEngine.chordPadChannel = ch
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("CH \(midiEngine.chordPadChannel)")
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(TEColors.black)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TEColors.darkGray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                    }
                }

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
                    .foregroundColor(.white)
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
                        .foregroundColor(TEColors.black)
                }
                
                TESettingsRow(label: "EFFECTS") {
                    Text("\(pluginManager.availableEffects.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
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
                    .foregroundColor(TEColors.black)
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
                // Theme picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("THEME")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    HStack(spacing: 8) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Button {
                                appearanceManager.currentAppearance = appearance
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: appearance.icon)
                                        .font(.system(size: 18, weight: .medium))
                                    Text(appearance.displayName)
                                        .font(TEFonts.mono(9, weight: .bold))
                                }
                                .foregroundColor(appearanceManager.currentAppearance == appearance ? .white : TEColors.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Rectangle()
                                        .fill(appearanceManager.currentAppearance == appearance ? TEColors.orange : TEColors.warmWhite)
                                )
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(TEColors.black, lineWidth: 2)
                                )
                            }
                        }
                    }
                }

                // Current mode indicator
                HStack {
                    Image(systemName: appearanceManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(appearanceManager.isDarkMode ? TEColors.orange : TEColors.orange)

                    Text(appearanceManager.isDarkMode ? "DARK MODE ACTIVE" : "LIGHT MODE ACTIVE")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(TEColors.darkGray)

                    Spacer()
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
                        .foregroundColor(TEColors.black)
                }

                TESettingsRow(label: "CHANNELS") {
                    Text("\(sessionStore.currentSession.channels.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }

                TESettingsRow(label: "PRESETS") {
                    Text("\(sessionStore.currentSession.songs.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }

                TESettingsRow(label: "SAVED") {
                    Text("\(sessionStore.savedSessions.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }

                // SAVE button (updates existing saved session)
                if sessionStore.isCurrentSessionSaved {
                    Button {
                        sessionStore.updateSavedSession()
                        showToast("SESSION SAVED")
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("SAVE")
                                .font(TEFonts.mono(11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(TEColors.orange)
                        .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        showingSaveAs = true
                    } label: {
                        Text("SAVE AS")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundColor(TEColors.black)
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
                            .foregroundColor(TEColors.black)
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
                            .foregroundColor(TEColors.red)
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
                            .foregroundColor(TEColors.red)
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

        // Reset tempo tracking so new session can send its tempo
        midiEngine.resetTempoTracking()

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

    // MARK: - About Section

    private var aboutSection: some View {
        TESettingsSection(title: "ABOUT") {
            VStack(spacing: 8) {
                TESettingsRow(label: "VERSION") {
                    Text("1.0")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }

                Text("KEYFRAME PERFORMANCE ENGINE")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.midGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(TEColors.green)

            Text(message)
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundColor(.white)
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

// MARK: - TE Settings Section

struct TESettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
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
                .foregroundColor(TEColors.midGray)
            
            Spacer()
            
            content
        }
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
                        .foregroundColor(TEColors.black)
                        .tracking(2)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("CLOSE")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundColor(TEColors.darkGray)
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
                            .foregroundColor(TEColors.midGray)
                        Text("NO SAVED SESSIONS")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(TEColors.midGray)
                        Text("Use 'Save As' to save your current session")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
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
                    .foregroundColor(TEColors.black)

                HStack(spacing: 12) {
                    Text("\(session.channels.count) CH")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Text("\(session.songs.count) PRESETS")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onLoad) {
                    Text("LOAD")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(TEColors.orange)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TEColors.red)
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
                    .foregroundColor(TEColors.black)
                    .tracking(2)

                // Text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("SESSION NAME")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(TEColors.midGray)

                    TextField("Enter name", text: $sessionName)
                        .font(TEFonts.mono(14, weight: .bold))
                        .foregroundColor(TEColors.black)
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
                            .foregroundColor(TEColors.darkGray)
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
                            .foregroundColor(.white)
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

// MARK: - Preview

#Preview {
    PerformanceSettingsView()
}
