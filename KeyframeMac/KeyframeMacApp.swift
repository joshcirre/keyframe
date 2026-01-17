import SwiftUI
import UniformTypeIdentifiers
import AppKit

@main
struct KeyframeMacApp: App {

    // Engine singletons
    @StateObject private var audioEngine = MacAudioEngine.shared
    @StateObject private var midiEngine = MacMIDIEngine.shared
    @StateObject private var sessionStore = MacSessionStore.shared
    @StateObject private var pluginManager = MacPluginManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var discovery = KeyframeDiscovery.shared

    // App delegate for handling app termination
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // File dialog state
    @State private var isShowingOpenPanel = false
    @State private var isShowingSavePanel = false

    // Setlist window state
    @State private var showingSetlistWindow = false

    init() {
        // Connect MIDI engine to audio engine and session store for MIDI routing
        MacMIDIEngine.shared.setAudioEngine(MacAudioEngine.shared)
        MacMIDIEngine.shared.setSessionStore(MacSessionStore.shared)

        // Set up preset change broadcast to iOS (legacy)
        MacSessionStore.shared.onPresetChanged = { presetIndex in
            // Broadcast via TCP to connected iOS devices
            KeyframeDiscovery.shared.broadcastActivePreset(presetIndex)
        }

        // Set up section change broadcast to iOS (new song→section model)
        MacSessionStore.shared.onSectionChanged = { globalIndex in
            // Broadcast via TCP to connected iOS devices
            KeyframeDiscovery.shared.broadcastActivePreset(globalIndex)
        }

        // Set up master volume broadcast to iOS (when Mac user changes volume)
        MacAudioEngine.shared.onMasterVolumeChanged = { volume in
            // Only broadcast if not suppressed (to prevent infinite loops)
            if !MacSessionStore.shared.suppressBroadcast {
                KeyframeDiscovery.shared.broadcastMasterVolume(volume)
                // Also save to session
                MacSessionStore.shared.currentSession.masterVolume = volume
            }
        }

        // Set up AU state sync callback - captures instrument/effect presets before saving
        MacSessionStore.shared.onSyncAUState = {
            let audioEngine = MacAudioEngine.shared
            let sessionStore = MacSessionStore.shared

            for (index, channel) in audioEngine.channelStrips.enumerated() {
                guard index < sessionStore.currentSession.channels.count else { continue }

                // Capture instrument state
                if let instrumentState = channel.saveInstrumentState() {
                    sessionStore.currentSession.channels[index].instrument?.presetData = instrumentState
                }

                // Capture effect states
                for effectIndex in 0..<channel.effects.count {
                    if effectIndex < sessionStore.currentSession.channels[index].effects.count,
                       let effectState = channel.saveEffectState(at: effectIndex) {
                        sessionStore.currentSession.channels[index].effects[effectIndex].presetData = effectState
                    }
                }
            }
        }

        // Set up external MIDI controller preset trigger handler
        MacMIDIEngine.shared.onExternalPresetTrigger = { presetIndex in
            DispatchQueue.main.async {
                let sessionStore = MacSessionStore.shared
                let audioEngine = MacAudioEngine.shared
                let midiEngine = MacMIDIEngine.shared

                if presetIndex < sessionStore.currentSession.presets.count {
                    // Smooth note-off: release all active notes before switching
                    midiEngine.releaseAllActiveNotes()

                    sessionStore.currentPresetIndex = presetIndex
                    let preset = sessionStore.currentSession.presets[presetIndex]

                    // Apply preset settings
                    if let bpm = preset.bpm {
                        audioEngine.setTempo(bpm)
                        midiEngine.currentBPM = Int(bpm)
                        midiEngine.sendTapTempo(bpm: Int(bpm))
                    }

                    if let scale = preset.scale, let rootNote = preset.rootNote {
                        midiEngine.currentRootNote = rootNote.midiValue
                        midiEngine.currentScaleType = scale
                    }

                    // Apply channel states
                    for channelState in preset.channelStates {
                        if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                            channel.volume = channelState.volume
                            channel.pan = channelState.pan
                            channel.isMuted = channelState.isMuted
                            channel.isSoloed = channelState.isSoloed
                        }
                    }

                    // Send external MIDI messages (to Helix, etc.)
                    midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)

                    print("KeyframeMacApp: External MIDI controller selected preset '\(preset.name)' (index \(presetIndex))")
                }
            }
        }

        // Set up remote preset change handler (iOS remote control)
        MacMIDIEngine.shared.onRemotePresetChange = { presetIndex in
            DispatchQueue.main.async {
                let sessionStore = MacSessionStore.shared
                let audioEngine = MacAudioEngine.shared
                let midiEngine = MacMIDIEngine.shared

                if presetIndex < sessionStore.currentSession.presets.count {
                    // Smooth note-off: release all active notes before switching
                    midiEngine.releaseAllActiveNotes()

                    // Suppress broadcast since this change came from iOS
                    sessionStore.suppressBroadcast = true
                    sessionStore.currentPresetIndex = presetIndex
                    sessionStore.suppressBroadcast = false

                    let preset = sessionStore.currentSession.presets[presetIndex]

                    // Apply preset settings
                    if let bpm = preset.bpm {
                        audioEngine.setTempo(bpm)
                        midiEngine.currentBPM = Int(bpm)
                        // Send tap tempo to external devices (Helix, etc.)
                        midiEngine.sendTapTempo(bpm: Int(bpm))
                    }

                    if let scale = preset.scale, let rootNote = preset.rootNote {
                        midiEngine.currentRootNote = rootNote.midiValue
                        midiEngine.currentScaleType = scale
                    }

                    // Apply channel states
                    for channelState in preset.channelStates {
                        if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                            channel.volume = channelState.volume
                            channel.pan = channelState.pan
                            channel.isMuted = channelState.isMuted
                            channel.isSoloed = channelState.isSoloed
                        }
                    }

                    // Send external MIDI messages
                    midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)

                    print("KeyframeMacApp: iOS remote selected preset '\(preset.name)' (index \(presetIndex))")
                }
            }
        }

        // Set up KeyframeDiscovery callbacks for iOS remote control
        // iOS sends a global section index - convert to song/section
        KeyframeDiscovery.shared.onPresetSelected = { globalIndex in
            DispatchQueue.main.async {
                let sessionStore = MacSessionStore.shared
                let audioEngine = MacAudioEngine.shared
                let midiEngine = MacMIDIEngine.shared

                // Convert global index to song/section indices
                guard let (songIndex, sectionIndex) = KeyframeDiscovery.shared.findSongAndSection(at: globalIndex) else {
                    print("KeyframeMacApp: Invalid section index \(globalIndex)")
                    return
                }

                let songs = sessionStore.currentSession.songs
                guard songIndex < songs.count else { return }
                let song = songs[songIndex]
                guard sectionIndex < song.sections.count else { return }
                let section = song.sections[sectionIndex]

                // Smooth note-off: release all active notes before switching
                midiEngine.releaseAllActiveNotes()

                // Suppress broadcast since this change came from iOS
                sessionStore.suppressBroadcast = true
                sessionStore.currentSongId = song.id
                sessionStore.currentSectionIndex = sectionIndex
                sessionStore.suppressBroadcast = false

                // Apply song-level settings (BPM, key)
                if let bpm = song.bpm {
                    audioEngine.setTempo(bpm)
                    midiEngine.currentBPM = Int(bpm)
                    midiEngine.sendTapTempo(bpm: Int(bpm))
                }

                if let scale = song.scale, let rootNote = song.rootNote {
                    midiEngine.currentRootNote = rootNote.midiValue
                    midiEngine.currentScaleType = scale
                }

                // Apply section-level settings (channel states, external MIDI)
                let spilloverEnabled = sessionStore.currentSession.spilloverEnabled
                for channelState in section.channelStates {
                    if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                        channel.applyStateWithSpillover(
                            volume: channelState.volume,
                            pan: channelState.pan,
                            mute: channelState.isMuted,
                            spilloverEnabled: spilloverEnabled
                        )
                        channel.isSoloed = channelState.isSoloed
                    }
                }

                // Send section's external MIDI messages
                midiEngine.sendExternalMIDIMessages(section.externalMIDIMessages)
                // Also send song-level external MIDI messages
                midiEngine.sendExternalMIDIMessages(song.externalMIDIMessages)

                print("KeyframeMacApp: iOS remote selected '\(song.name) > \(section.name)' (global index \(globalIndex))")
            }
        }

        KeyframeDiscovery.shared.onMasterVolumeChanged = { volume in
            DispatchQueue.main.async {
                // Suppress broadcast to prevent loops (iOS sent this, don't broadcast back)
                MacSessionStore.shared.suppressBroadcast = true
                MacAudioEngine.shared.masterVolume = volume
                MacSessionStore.shared.currentSession.masterVolume = volume
                MacSessionStore.shared.suppressBroadcast = false
            }
        }

        // Scan for plugins at launch
        MacPluginManager.shared.scanForPlugins()
    }

    var body: some Scene {
        WindowGroup {
            MixerView()
                .environmentObject(audioEngine)
                .environmentObject(midiEngine)
                .environmentObject(sessionStore)
                .environmentObject(pluginManager)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    restoreSession()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 700)
        .commands {
            // File menu - replace default new item
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    newSession()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Open...") {
                    openSession()
                }
                .keyboardShortcut("o", modifiers: .command)

                // Recent documents submenu
                Menu("Open Recent") {
                    ForEach(sessionStore.recentDocuments, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            _ = sessionStore.loadFromFile(url)
                            restoreSession()
                        }
                    }

                    if !sessionStore.recentDocuments.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            sessionStore.clearRecentDocuments()
                        }
                    }
                }
                .disabled(sessionStore.recentDocuments.isEmpty)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    saveSession()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!sessionStore.isDocumentDirty && sessionStore.currentFileURL != nil)

                Button("Save As...") {
                    saveSessionAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // Playback menu
            CommandMenu("Playback") {
                Button(audioEngine.isRunning ? "Stop Engine" : "Start Engine") {
                    if audioEngine.isRunning {
                        audioEngine.stop()
                    } else {
                        audioEngine.start()
                    }
                }
                .keyboardShortcut(" ", modifiers: [])

                Divider()

                Button("Panic (All Notes Off)") {
                    audioEngine.panicAllNotesOff()
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            // MIDI menu
            CommandMenu("MIDI") {
                Button("Panic All Notes Off") {
                    audioEngine.panicAllNotesOff()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Toggle("Scale Filter", isOn: Binding(
                    get: { midiEngine.isScaleFilterEnabled },
                    set: { midiEngine.isScaleFilterEnabled = $0 }
                ))
                .keyboardShortcut("f", modifiers: .command)
            }

            // Setlist menu
            CommandMenu("Setlist") {
                Button("Open Setlist View") {
                    showingSetlistWindow = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Next Song") {
                    nextSetlistSong()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(sessionStore.currentSession.activeSetlist == nil)

                Button("Previous Song") {
                    previousSetlistSong()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(sessionStore.currentSession.activeSetlist == nil)

                Divider()

                // Active setlist picker
                if sessionStore.currentSession.setlists.isEmpty {
                    Text("No Setlists")
                        .foregroundColor(.secondary)
                } else {
                    Menu("Select Setlist") {
                        Button("None") {
                            sessionStore.setActiveSetlist(nil)
                        }

                        Divider()

                        ForEach(sessionStore.currentSession.setlists) { setlist in
                            Button(setlist.name) {
                                sessionStore.setActiveSetlist(setlist)
                            }
                        }
                    }
                }
            }

            // View menu additions
            CommandMenu("View") {
                Button("Show Setlist") {
                    showingSetlistWindow = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }

        }

        // Setlist performance window
        Window("Setlist", id: "setlist") {
            SetlistView()
                .environmentObject(sessionStore)
                .environmentObject(audioEngine)
                .environmentObject(midiEngine)
                .frame(minWidth: 600, minHeight: 500)
        }
        .defaultSize(width: 800, height: 600)
        .keyboardShortcut("l", modifiers: .command)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(midiEngine)
                .environmentObject(audioEngine)
        }
    }

    // MARK: - Setlist Navigation

    private func nextSetlistSong() {
        if let preset = sessionStore.nextSetlistEntry() {
            activatePreset(preset)
        }
    }

    private func previousSetlistSong() {
        if let preset = sessionStore.previousSetlistEntry() {
            activatePreset(preset)
        }
    }

    private func activatePreset(_ preset: MacPreset) {
        // Apply scale settings
        if let scale = preset.scale, let rootNote = preset.rootNote {
            midiEngine.currentRootNote = rootNote.midiValue
            midiEngine.currentScaleType = scale
        }

        // Apply BPM
        if let bpm = preset.bpm {
            audioEngine.setTempo(bpm)
            midiEngine.currentBPM = Int(bpm)
            midiEngine.sendTapTempo(bpm: Int(bpm))
        }

        // Apply channel states with spillover support
        let spilloverEnabled = sessionStore.currentSession.spilloverEnabled
        for channelState in preset.channelStates {
            if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                channel.applyStateWithSpillover(
                    volume: channelState.volume,
                    pan: channelState.pan,
                    mute: channelState.isMuted,
                    spilloverEnabled: spilloverEnabled
                )
                channel.isSoloed = channelState.isSoloed
            }
        }

        // Send external MIDI messages
        midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)

        // Handle backing track
        if let backingTrack = preset.backingTrack, backingTrack.autoStart {
            audioEngine.loadAndPlayBackingTrack(backingTrack)
        } else {
            audioEngine.stopBackingTrack()
        }

        print("KeyframeMacApp: Activated preset '\(preset.name)'")
    }

    // MARK: - Session Restoration

    private func restoreSession() {
        let session = sessionStore.currentSession

        // Count total plugins for progress tracking
        var totalPlugins = 0
        for config in session.channels {
            if config.instrument != nil { totalPlugins += 1 }
            totalPlugins += config.effects.count
        }

        // Set loading state
        if totalPlugins > 0 {
            audioEngine.setRestorationState(true, progress: "Loading plugins...")
        }

        var loadedCount = 0
        let pluginLoadQueue = DispatchQueue(label: "com.keyframe.pluginLoad")

        let markPluginLoaded: (String) -> Void = { [weak audioEngine] name in
            pluginLoadQueue.sync { loadedCount += 1 }
            let current = pluginLoadQueue.sync { loadedCount }

            DispatchQueue.main.async {
                if current < totalPlugins {
                    audioEngine?.setRestorationState(true, progress: "Loaded \(current)/\(totalPlugins): \(name)")
                } else {
                    audioEngine?.setRestorationState(false, progress: "")
                }
            }
        }

        // Recreate channel strips from session
        for (index, config) in session.channels.enumerated() {
            guard index >= audioEngine.channelStrips.count else { continue }

            if let channel = audioEngine.addChannel() {
                // Apply channel configuration
                channel.midiChannel = config.midiChannel
                channel.midiSourceName = config.midiSourceName
                channel.scaleFilterEnabled = config.scaleFilterEnabled
                channel.isChordPadTarget = config.isChordPadTarget
                channel.volume = config.volume
                channel.pan = config.pan
                channel.isMuted = config.isMuted

                // Load instrument if configured
                if let instrument = config.instrument {
                    audioEngine.setRestorationState(true, progress: "Loading \(instrument.name)...")

                    channel.loadInstrument(instrument.audioComponentDescription) { success, error in
                        if success {
                            channel.instrumentInfo = MacAUInfo(
                                name: instrument.name,
                                manufacturerName: instrument.manufacturerName,
                                componentType: instrument.audioComponentDescription.componentType,
                                componentSubType: instrument.audioComponentDescription.componentSubType,
                                componentManufacturer: instrument.audioComponentDescription.componentManufacturer
                            )

                            // Restore preset data if available
                            if let presetData = instrument.presetData {
                                channel.restoreInstrumentState(presetData)
                            }
                        }
                        markPluginLoaded(instrument.name)
                    }
                }

                // Load effects
                for effect in config.effects {
                    channel.addEffect(effect.audioComponentDescription) { success, error in
                        if success {
                            channel.effectInfos.append(MacAUInfo(
                                name: effect.name,
                                manufacturerName: effect.manufacturerName,
                                componentType: effect.audioComponentDescription.componentType,
                                componentSubType: effect.audioComponentDescription.componentSubType,
                                componentManufacturer: effect.audioComponentDescription.componentManufacturer
                            ))

                            if let presetData = effect.presetData {
                                let effectIndex = channel.effectInfos.count - 1
                                channel.restoreEffectState(presetData, at: effectIndex)
                            }
                        }
                        markPluginLoaded(effect.name)
                    }
                }
            }
        }

        // Apply master volume
        audioEngine.masterVolume = session.masterVolume

        // Load MIDI mappings
        midiEngine.loadMappings(from: session)

        // Start audio engine
        audioEngine.start()

        // Clear loading state if no plugins
        if totalPlugins == 0 {
            audioEngine.setRestorationState(false, progress: "")
        }

        print("KeyframeMacApp: Session '\(session.name)' restored with \(session.channels.count) channels, \(session.midiMappings.count) mappings")
    }

    // MARK: - File Operations

    private func newSession() {
        // Check for unsaved changes first
        if sessionStore.isDocumentDirty {
            guard promptToSaveChanges(action: "create a new session") else { return }
        }

        sessionStore.newSession()
        // Clear existing channels
        while !audioEngine.channelStrips.isEmpty {
            audioEngine.removeChannel(at: 0)
        }
        print("KeyframeMacApp: Created new session")
    }

    private func openSession() {
        // Check for unsaved changes first
        if sessionStore.isDocumentDirty {
            guard promptToSaveChanges(action: "open another session") else { return }
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.keyframeSession, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Keyframe session to open"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if self.sessionStore.loadFromFile(url) {
                    // Clear existing channels
                    while !self.audioEngine.channelStrips.isEmpty {
                        self.audioEngine.removeChannel(at: 0)
                    }
                    self.restoreSession()
                }
            }
        }
    }

    /// Prompts user to save unsaved changes. Returns true if the action should continue, false to cancel.
    private func promptToSaveChanges(action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to your session?"
        alert.informativeText = "Your changes will be lost if you \(action) without saving."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Save first
            if let url = sessionStore.currentFileURL {
                sessionStore.saveToFile(url)
                return true
            } else {
                // Show Save As panel
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.keyframeSession]
                panel.nameFieldStringValue = sessionStore.currentSession.name.isEmpty
                    ? "Untitled Session"
                    : sessionStore.currentSession.name

                if panel.runModal() == .OK, let url = panel.url {
                    if sessionStore.currentSession.name == "Untitled Session" {
                        sessionStore.currentSession.name = url.deletingPathExtension().lastPathComponent
                    }
                    sessionStore.saveToFile(url)
                    return true
                } else {
                    return false  // Cancelled save, cancel action
                }
            }

        case .alertSecondButtonReturn:
            // Don't save, continue with action
            return true

        default:
            // Cancel
            return false
        }
    }

    private func saveSession() {
        // Sync AU state to session before saving
        syncAUStateToSession()

        if let url = sessionStore.currentFileURL {
            // Save to existing file
            sessionStore.saveToFile(url)
        } else {
            // No file yet, show Save As
            saveSessionAs()
        }
    }

    private func saveSessionAs() {
        // Sync AU state to session before saving
        syncAUStateToSession()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.keyframeSession]
        panel.nameFieldStringValue = sessionStore.currentSession.name.isEmpty
            ? "Untitled Session"
            : sessionStore.currentSession.name
        panel.message = "Save your Keyframe session"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Update session name from filename if default
                if sessionStore.currentSession.name == "Untitled Session" {
                    sessionStore.currentSession.name = url.deletingPathExtension().lastPathComponent
                }
                sessionStore.saveToFile(url)
            }
        }
    }

    /// Captures current AudioUnit state (presets, parameters) from all channels
    /// and stores it in the session configuration for persistence
    private func syncAUStateToSession() {
        for (index, channel) in audioEngine.channelStrips.enumerated() {
            guard index < sessionStore.currentSession.channels.count else { continue }

            // Capture instrument state
            if let instrumentState = channel.saveInstrumentState() {
                sessionStore.currentSession.channels[index].instrument?.presetData = instrumentState
                print("KeyframeMacApp: Captured instrument state for channel \(index)")
            }

            // Capture effect states
            for effectIndex in 0..<channel.effects.count {
                if effectIndex < sessionStore.currentSession.channels[index].effects.count,
                   let effectState = channel.saveEffectState(at: effectIndex) {
                    sessionStore.currentSession.channels[index].effects[effectIndex].presetData = effectState
                    print("KeyframeMacApp: Captured effect \(effectIndex) state for channel \(index)")
                }
            }
        }
    }
}

// MARK: - App Delegate for Unsaved Changes Prompt

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let sessionStore = MacSessionStore.shared

        // Check if there are unsaved changes
        guard sessionStore.isDocumentDirty else {
            return .terminateNow
        }

        // Show save prompt
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to your session?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Sync AU state before saving
            syncAUStateToSession()

            // Save
            if let url = sessionStore.currentFileURL {
                sessionStore.saveToFile(url)
                return .terminateNow
            } else {
                // No file yet, show Save As panel
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.keyframeSession]
                panel.nameFieldStringValue = sessionStore.currentSession.name.isEmpty
                    ? "Untitled Session"
                    : sessionStore.currentSession.name
                panel.message = "Save your Keyframe session before quitting"

                if panel.runModal() == .OK, let url = panel.url {
                    if sessionStore.currentSession.name == "Untitled Session" {
                        sessionStore.currentSession.name = url.deletingPathExtension().lastPathComponent
                    }
                    sessionStore.saveToFile(url)
                    return .terminateNow
                } else {
                    // User cancelled save panel
                    return .terminateCancel
                }
            }

        case .alertSecondButtonReturn:
            // Don't Save
            return .terminateNow

        default:
            // Cancel
            return .terminateCancel
        }
    }

    /// Captures current AudioUnit state (presets, parameters) from all channels
    /// and stores it in the session configuration for persistence
    private func syncAUStateToSession() {
        let audioEngine = MacAudioEngine.shared
        let sessionStore = MacSessionStore.shared

        for (index, channel) in audioEngine.channelStrips.enumerated() {
            guard index < sessionStore.currentSession.channels.count else { continue }

            // Capture instrument state
            if let instrumentState = channel.saveInstrumentState() {
                sessionStore.currentSession.channels[index].instrument?.presetData = instrumentState
            }

            // Capture effect states
            for effectIndex in 0..<channel.effects.count {
                if effectIndex < sessionStore.currentSession.channels[index].effects.count,
                   let effectState = channel.saveEffectState(at: effectIndex) {
                    sessionStore.currentSession.channels[index].effects[effectIndex].presetData = effectState
                }
            }
        }
    }
}
