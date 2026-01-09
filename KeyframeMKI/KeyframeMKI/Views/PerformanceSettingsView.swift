import SwiftUI

/// Settings view for the Performance Engine - TE Style
struct PerformanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var showingSaveAs = false
    @State private var newSessionName = ""
    @State private var showingResetConfirmation = false
    @State private var showingChordMap = false
    @State private var showingBluetoothMIDI = false
    
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
                        sessionSection
                        aboutSection
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
        .alert("SAVE SESSION", isPresented: $showingSaveAs) {
            TextField("Session Name", text: $newSessionName)
                .textInputAutocapitalization(.characters)
            Button("SAVE") {
                sessionStore.saveSessionAs(newSessionName)
                newSessionName = ""
            }
            Button("CANCEL", role: .cancel) {
                newSessionName = ""
            }
        } message: {
            Text("Enter a name for this session")
        }
        .confirmationDialog("RESET SESSION", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("RESET", role: .destructive) {
                sessionStore.loadSession(Session.defaultSession())
            }
        } message: {
            Text("This will reset to the default session. All changes will be lost.")
        }
        .sheet(isPresented: $showingChordMap) {
            ChordMapView()
        }
        .sheet(isPresented: $showingBluetoothMIDI) {
            BluetoothMIDIView()
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
    
    // MARK: - Session Section
    
    private var sessionSection: some View {
        TESettingsSection(title: "SESSION") {
            VStack(spacing: 16) {
                TESettingsRow(label: "CURRENT") {
                    Text(sessionStore.currentSession.name.uppercased())
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                }
                
                TESettingsRow(label: "SONGS") {
                    Text("\(sessionStore.currentSession.songs.count)")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
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
                        showingResetConfirmation = true
                    } label: {
                        Text("RESET")
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

// MARK: - Preview

#Preview {
    PerformanceSettingsView()
}
