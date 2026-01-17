import Foundation
import AudioToolbox

/// Represents a complete performance session configuration
/// Includes all channels, plugins, and song presets
struct Session: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var channels: [ChannelConfiguration]
    var masterVolume: Float

    // New hierarchical model: Setlist → Songs → Presets
    var setlist: [SetlistSong]
    var activeSongId: UUID?
    var activePresetId: UUID?

    // Legacy support (for migration)
    var songs: [PerformanceSong]

    // MIDI Freeze/Hold configuration
    var freezeMode: FreezeMode
    var freezeTriggerCC: Int?           // CC number for freeze trigger (nil = not mapped)
    var freezeTriggerChannel: Int?       // MIDI channel (1-16, nil = any channel)
    var freezeTriggerSourceName: String? // MIDI device name (nil = any source)

    var createdAt: Date
    var modifiedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String = "New Session",
        channels: [ChannelConfiguration] = [],
        masterVolume: Float = 1.0,
        setlist: [SetlistSong] = [],
        activeSongId: UUID? = nil,
        activePresetId: UUID? = nil,
        songs: [PerformanceSong] = [],
        freezeMode: FreezeMode = .sustain,
        freezeTriggerCC: Int? = 64,  // Default: sustain pedal
        freezeTriggerChannel: Int? = nil,
        freezeTriggerSourceName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.masterVolume = masterVolume
        self.setlist = setlist
        self.activeSongId = activeSongId
        self.activePresetId = activePresetId
        self.songs = songs
        self.freezeMode = freezeMode
        self.freezeTriggerCC = freezeTriggerCC
        self.freezeTriggerChannel = freezeTriggerChannel
        self.freezeTriggerSourceName = freezeTriggerSourceName
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Migration

    /// Migrate legacy songs to new setlist format
    mutating func migrateToNewFormat() {
        guard setlist.isEmpty && !songs.isEmpty else { return }

        // Convert each PerformanceSong to a Song with one Preset
        setlist = songs.map { $0.toSetlistSong() }

        // Set first song/preset as active if none set
        if activeSongId == nil, let firstSong = setlist.first {
            activeSongId = firstSong.id
            activePresetId = firstSong.firstPreset?.id
        }

        print("Session: Migrated \(songs.count) legacy songs to new format")
    }

    // MARK: - Helpers

    /// Get the currently active song
    var activeSong: SetlistSong? {
        setlist.first { $0.id == activeSongId }
    }

    /// Get the currently active preset
    var activePreset: SongPreset? {
        guard let song = activeSong else { return nil }
        return song.presets.first { $0.id == activePresetId }
    }

    /// Legacy compatibility: get active song as PerformanceSong
    var activeLegacySong: PerformanceSong? {
        songs.first { $0.id == activeSongId }
    }

    /// Check if session uses new format
    var usesNewFormat: Bool {
        !setlist.isEmpty
    }

    mutating func touch() {
        modifiedAt = Date()
    }
}

// MARK: - Channel Configuration

/// Configuration for a single channel in the session
struct ChannelConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var instrument: PluginConfiguration?
    var effects: [PluginConfiguration]
    var volume: Float
    var pan: Float
    var isMuted: Bool
    var midiChannel: Int  // 1-16, 0 = omni (any channel)
    var midiSourceName: String?  // nil = any source, or specific controller name
    var scaleFilterEnabled: Bool
    var isChordPadTarget: Bool

    // MIDI Control mapping (for fader/volume control)
    var controlSourceName: String?  // MIDI device that controls this channel's fader
    var controlChannel: Int?        // MIDI channel (1-16, nil = any channel)
    var controlCC: Int?             // CC number that controls volume (nil = not mapped)

    init(
        id: UUID = UUID(),
        name: String = "New Channel",
        instrument: PluginConfiguration? = nil,
        effects: [PluginConfiguration] = [],
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        midiChannel: Int = 0,
        midiSourceName: String? = nil,
        scaleFilterEnabled: Bool = true,
        isChordPadTarget: Bool = false,
        controlSourceName: String? = nil,
        controlChannel: Int? = nil,
        controlCC: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.effects = effects
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.midiChannel = midiChannel
        self.midiSourceName = midiSourceName
        self.scaleFilterEnabled = scaleFilterEnabled
        self.isChordPadTarget = isChordPadTarget
        self.controlSourceName = controlSourceName
        self.controlChannel = controlChannel
        self.controlCC = controlCC
    }
}

// MARK: - Plugin Configuration

/// Configuration for a loaded plugin (instrument or effect)
struct PluginConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var manufacturerName: String
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32
    var presetData: Data?
    var isBypassed: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        manufacturerName: String,
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32,
        presetData: Data? = nil,
        isBypassed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.presetData = presetData
        self.isBypassed = isBypassed
    }
    
    var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}

// MARK: - Song (Container for Presets)

/// A song contains multiple presets (e.g., "Oceans" has Intro, Verse, Chorus presets)
/// The first preset typically sets the tempo and key for the entire song
struct SetlistSong: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // Song name (e.g., "Oceans", "Way Maker")
    var artist: String?           // Optional artist name
    var presets: [SongPreset]     // Presets within this song (Intro, Verse, Chorus, etc.)
    var order: Int                // Position in setlist

    // Song-level settings (inherited by presets unless overridden)
    var rootNote: Int             // Key root note
    var scaleType: ScaleType      // Major/Minor
    var bpm: Int?                 // Tempo

    // MIDI trigger (to jump directly to this song's first preset)
    var triggerSourceName: String?
    var triggerChannel: Int?
    var triggerNote: Int?

    init(
        id: UUID = UUID(),
        name: String,
        artist: String? = nil,
        presets: [SongPreset] = [],
        order: Int = 0,
        rootNote: Int = 0,
        scaleType: ScaleType = .major,
        bpm: Int? = nil,
        triggerSourceName: String? = nil,
        triggerChannel: Int? = nil,
        triggerNote: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.presets = presets
        self.order = order
        self.rootNote = rootNote
        self.scaleType = scaleType
        self.bpm = bpm
        self.triggerSourceName = triggerSourceName
        self.triggerChannel = triggerChannel
        self.triggerNote = triggerNote
    }

    var keyDisplayName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        return "\(noteName) \(scaleType.rawValue)"
    }

    var keyShortName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        let suffix = scaleType == .major ? "maj" : "min"
        return "\(noteName)\(suffix)"
    }

    /// Get the first preset (typically used to start the song)
    var firstPreset: SongPreset? {
        presets.first
    }

    /// Get active preset index
    var activePresetIndex: Int? {
        presets.firstIndex { $0.isActive }
    }

    /// Get the active preset (or first preset if none active)
    var activePreset: SongPreset? {
        presets.first { $0.isActive } ?? presets.first
    }

    // MARK: - Convenience Properties (for view compatibility)

    /// Filter mode from active preset (convenience for views)
    var filterMode: FilterMode {
        get { activePreset?.filterMode ?? .snap }
        set {
            if let index = presets.firstIndex(where: { $0.isActive }) {
                presets[index].filterMode = newValue
            } else if !presets.isEmpty {
                presets[0].filterMode = newValue
            }
        }
    }

    /// Channel states from active preset (convenience for views)
    var channelStates: [ChannelPresetState] {
        get { activePreset?.channelStates ?? [] }
        set {
            if let index = presets.firstIndex(where: { $0.isActive }) {
                presets[index].channelStates = newValue
            } else if !presets.isEmpty {
                presets[0].channelStates = newValue
            }
        }
    }

    /// External MIDI messages from active preset (convenience for views)
    var externalMIDIMessages: [ExternalMIDIMessage] {
        get { activePreset?.externalMIDIMessages ?? [] }
        set {
            if let index = presets.firstIndex(where: { $0.isActive }) {
                presets[index].externalMIDIMessages = newValue
            } else if !presets.isEmpty {
                presets[0].externalMIDIMessages = newValue
            }
        }
    }
}

// MARK: - Song Preset (Sound/Patch within a Song)

/// A preset is a specific sound configuration within a song
/// e.g., "Intro Pad", "Verse Lead", "Chorus Full"
struct SongPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // Preset name (e.g., "Intro", "Verse 1", "Chorus")
    var channelStates: [ChannelPresetState]
    var filterMode: FilterMode
    var order: Int                // Position within song
    var isActive: Bool            // Currently active preset in song

    // Override song-level settings (nil = inherit from song)
    var rootNoteOverride: Int?
    var scaleTypeOverride: ScaleType?
    var bpmOverride: Int?

    // MIDI trigger (to jump directly to this preset)
    var triggerSourceName: String?
    var triggerChannel: Int?
    var triggerNote: Int?

    // External MIDI output messages (sent when this preset is selected)
    var externalMIDIMessages: [ExternalMIDIMessage]

    init(
        id: UUID = UUID(),
        name: String,
        channelStates: [ChannelPresetState] = [],
        filterMode: FilterMode = .snap,
        order: Int = 0,
        isActive: Bool = false,
        rootNoteOverride: Int? = nil,
        scaleTypeOverride: ScaleType? = nil,
        bpmOverride: Int? = nil,
        triggerSourceName: String? = nil,
        triggerChannel: Int? = nil,
        triggerNote: Int? = nil,
        externalMIDIMessages: [ExternalMIDIMessage] = []
    ) {
        self.id = id
        self.name = name
        self.channelStates = channelStates
        self.filterMode = filterMode
        self.order = order
        self.isActive = isActive
        self.rootNoteOverride = rootNoteOverride
        self.scaleTypeOverride = scaleTypeOverride
        self.bpmOverride = bpmOverride
        self.triggerSourceName = triggerSourceName
        self.triggerChannel = triggerChannel
        self.triggerNote = triggerNote
        self.externalMIDIMessages = externalMIDIMessages
    }

    /// Get effective root note (override or inherited from song)
    func effectiveRootNote(song: SetlistSong) -> Int {
        rootNoteOverride ?? song.rootNote
    }

    /// Get effective scale type (override or inherited from song)
    func effectiveScaleType(song: SetlistSong) -> ScaleType {
        scaleTypeOverride ?? song.scaleType
    }

    /// Get effective BPM (override or inherited from song)
    func effectiveBPM(song: SetlistSong) -> Int? {
        bpmOverride ?? song.bpm
    }

    /// Get key short name using song defaults
    func keyShortName(song: SetlistSong) -> String {
        let noteName = NoteName(rawValue: effectiveRootNote(song: song))?.displayName ?? "?"
        let suffix = effectiveScaleType(song: song) == .major ? "maj" : "min"
        return "\(noteName)\(suffix)"
    }
}

// MARK: - Legacy PerformanceSong (for backward compatibility)

/// Legacy model - kept for migration from old sessions
/// A song with scale settings and channel state presets
struct PerformanceSong: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // Preset name (e.g., "Clean Chorus")
    var songName: String?         // Optional song name (e.g., "The Joy")
    var rootNote: Int
    var scaleType: ScaleType
    var filterMode: FilterMode
    var bpm: Int?
    var channelStates: [ChannelPresetState]
    var order: Int  // For setlist ordering

    // MIDI trigger mapping (for selecting this song via MIDI)
    var triggerSourceName: String?  // MIDI device that can trigger this song
    var triggerChannel: Int?        // MIDI channel (1-16, nil = any channel)
    var triggerNote: Int?           // Note number that triggers this song (nil = not mapped)

    // External MIDI output messages (sent when this song is selected)
    var externalMIDIMessages: [ExternalMIDIMessage]

    init(
        id: UUID = UUID(),
        name: String,
        songName: String? = nil,
        rootNote: Int = 0,
        scaleType: ScaleType = .major,
        filterMode: FilterMode = .snap,
        bpm: Int? = nil,
        channelStates: [ChannelPresetState] = [],
        order: Int = 0,
        triggerSourceName: String? = nil,
        triggerChannel: Int? = nil,
        triggerNote: Int? = nil,
        externalMIDIMessages: [ExternalMIDIMessage] = []
    ) {
        self.id = id
        self.name = name
        self.songName = songName
        self.rootNote = rootNote
        self.scaleType = scaleType
        self.filterMode = filterMode
        self.bpm = bpm
        self.channelStates = channelStates
        self.order = order
        self.triggerSourceName = triggerSourceName
        self.triggerChannel = triggerChannel
        self.triggerNote = triggerNote
        self.externalMIDIMessages = externalMIDIMessages
    }

    var keyDisplayName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        return "\(noteName) \(scaleType.rawValue)"
    }

    var keyShortName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        let suffix = scaleType == .major ? "maj" : "min"
        return "\(noteName)\(suffix)"
    }

    /// Convert legacy PerformanceSong to new Song with single Preset
    func toSetlistSong() -> SetlistSong {
        let preset = SongPreset(
            id: UUID(),
            name: name,
            channelStates: channelStates,
            filterMode: filterMode,
            order: 0,
            isActive: true,
            triggerSourceName: triggerSourceName,
            triggerChannel: triggerChannel,
            triggerNote: triggerNote,
            externalMIDIMessages: externalMIDIMessages
        )

        return SetlistSong(
            id: id,
            name: songName ?? name,
            presets: [preset],
            order: order,
            rootNote: rootNote,
            scaleType: scaleType,
            bpm: bpm
        )
    }
}

// MARK: - Default Session

extension Session {
    /// Create a default empty session with new format
    static func defaultSession() -> Session {
        let defaultPreset = SongPreset(
            name: "Default",
            order: 0,
            isActive: true
        )

        let defaultSong = SetlistSong(
            name: "Untitled Song",
            presets: [defaultPreset],
            order: 0,
            rootNote: 0,
            scaleType: .major,
            bpm: 120
        )

        return Session(
            name: "Untitled",
            channels: [],
            setlist: [defaultSong],
            activeSongId: defaultSong.id,
            activePresetId: defaultPreset.id
        )
    }
}

// MARK: - Session Store

/// Manages persistence of sessions
final class SessionStore: ObservableObject {
    
    static let shared = SessionStore()
    
    @Published var currentSession: Session
    @Published var savedSessions: [Session] = []
    
    private let userDefaults = UserDefaults.standard
    private let currentSessionKey = "currentSession"
    private let savedSessionsKey = "savedSessions"
    
    private init() {
        // Load current session or create default
        if let data = userDefaults.data(forKey: currentSessionKey),
           var session = try? JSONDecoder().decode(Session.self, from: data) {
            // Migrate legacy format if needed
            if !session.usesNewFormat {
                session.migrateToNewFormat()
            }
            currentSession = session
        } else {
            currentSession = Session.defaultSession()
        }

        // Load saved sessions
        if let data = userDefaults.data(forKey: savedSessionsKey),
           var sessions = try? JSONDecoder().decode([Session].self, from: data) {
            // Migrate each session if needed
            for i in sessions.indices {
                if !sessions[i].usesNewFormat {
                    sessions[i].migrateToNewFormat()
                }
            }
            savedSessions = sessions
        }
    }
    
    func saveCurrentSession() {
        currentSession.touch()
        
        if let data = try? JSONEncoder().encode(currentSession) {
            userDefaults.set(data, forKey: currentSessionKey)
        }
    }
    
    func saveSessions() {
        if let data = try? JSONEncoder().encode(savedSessions) {
            userDefaults.set(data, forKey: savedSessionsKey)
        }
    }
    
    func saveSessionAs(_ name: String) {
        // Create a NEW session with a new ID (standard "Save As" behavior)
        // This allows the original saved session to remain unchanged
        let newSession = Session(
            id: UUID(),  // New ID!
            name: name,
            channels: currentSession.channels,
            masterVolume: currentSession.masterVolume,
            setlist: currentSession.setlist,
            activeSongId: currentSession.activeSongId,
            activePresetId: currentSession.activePresetId,
            freezeMode: currentSession.freezeMode,
            freezeTriggerCC: currentSession.freezeTriggerCC,
            freezeTriggerChannel: currentSession.freezeTriggerChannel,
            freezeTriggerSourceName: currentSession.freezeTriggerSourceName
        )

        // Switch current session to the new one
        currentSession = newSession
        saveCurrentSession()

        // Add to saved sessions list
        savedSessions.append(newSession)
        saveSessions()

        print("SessionStore: Created new session '\(name)' with ID \(newSession.id)")
    }

    /// Update the saved copy of the current session (if it exists in saved sessions)
    /// Returns true if an existing saved session was updated, false if not found
    @discardableResult
    func updateSavedSession() -> Bool {
        saveCurrentSession()

        // Find and update the saved copy if it exists
        if let index = savedSessions.firstIndex(where: { $0.id == currentSession.id }) {
            savedSessions[index] = currentSession
            saveSessions()
            print("SessionStore: Updated saved session '\(currentSession.name)'")
            return true
        }
        return false
    }

    /// Check if the current session has a saved copy
    var isCurrentSessionSaved: Bool {
        savedSessions.contains { $0.id == currentSession.id }
    }
    
    func loadSession(_ session: Session) {
        currentSession = session
        saveCurrentSession()
    }
    
    func deleteSession(_ session: Session) {
        savedSessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    /// Reset to a fresh default session
    func resetToDefault() {
        currentSession = Session.defaultSession()
        saveCurrentSession()
        print("SessionStore: Reset to default session")
    }

    // MARK: - Channel Management

    func addChannel(_ channel: ChannelConfiguration) {
        currentSession.channels.append(channel)
        saveCurrentSession()
    }

    func deleteChannel(at index: Int) {
        guard index < currentSession.channels.count else { return }
        currentSession.channels.remove(at: index)
        saveCurrentSession()
    }

    func resetChannel(at index: Int) {
        guard index < currentSession.channels.count else { return }
        let oldName = currentSession.channels[index].name
        currentSession.channels[index] = ChannelConfiguration(name: oldName)
        saveCurrentSession()
    }

    // MARK: - Song Management (New Format)

    /// Set the active song and its first preset
    func setActiveSong(_ song: SetlistSong) {
        currentSession.activeSongId = song.id
        currentSession.activePresetId = song.firstPreset?.id
        saveCurrentSession()
    }

    /// Set the active preset within a song
    func setActivePreset(_ preset: SongPreset, in song: SetlistSong) {
        currentSession.activeSongId = song.id
        currentSession.activePresetId = preset.id
        saveCurrentSession()
    }

    /// Add a new song to the setlist
    func addSong(_ song: SetlistSong) {
        var newSong = song
        newSong.order = currentSession.setlist.count
        currentSession.setlist.append(newSong)
        saveCurrentSession()
    }

    /// Update an existing song
    func updateSong(_ song: SetlistSong) {
        if let index = currentSession.setlist.firstIndex(where: { $0.id == song.id }) {
            currentSession.setlist[index] = song
            saveCurrentSession()
        }
    }

    /// Delete a song from the setlist
    func deleteSong(_ song: SetlistSong) {
        currentSession.setlist.removeAll { $0.id == song.id }
        if currentSession.activeSongId == song.id {
            currentSession.activeSongId = currentSession.setlist.first?.id
            currentSession.activePresetId = currentSession.setlist.first?.firstPreset?.id
        }
        saveCurrentSession()
    }

    /// Move a song in the setlist
    func moveSong(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < currentSession.setlist.count,
              destinationIndex >= 0, destinationIndex < currentSession.setlist.count else {
            return
        }

        let song = currentSession.setlist.remove(at: sourceIndex)
        currentSession.setlist.insert(song, at: destinationIndex)

        // Update order values to match array positions
        for (index, _) in currentSession.setlist.enumerated() {
            currentSession.setlist[index].order = index
        }

        saveCurrentSession()
    }

    // MARK: - Preset Management

    /// Add a preset to a song
    func addPreset(_ preset: SongPreset, to songId: UUID) {
        guard let songIndex = currentSession.setlist.firstIndex(where: { $0.id == songId }) else { return }
        var newPreset = preset
        newPreset.order = currentSession.setlist[songIndex].presets.count
        currentSession.setlist[songIndex].presets.append(newPreset)
        saveCurrentSession()
    }

    /// Update a preset in a song
    func updatePreset(_ preset: SongPreset, in songId: UUID) {
        guard let songIndex = currentSession.setlist.firstIndex(where: { $0.id == songId }),
              let presetIndex = currentSession.setlist[songIndex].presets.firstIndex(where: { $0.id == preset.id }) else { return }
        currentSession.setlist[songIndex].presets[presetIndex] = preset
        saveCurrentSession()
    }

    /// Delete a preset from a song
    func deletePreset(_ preset: SongPreset, from songId: UUID) {
        guard let songIndex = currentSession.setlist.firstIndex(where: { $0.id == songId }) else { return }
        currentSession.setlist[songIndex].presets.removeAll { $0.id == preset.id }

        // If deleted preset was active, select another
        if currentSession.activePresetId == preset.id {
            currentSession.activePresetId = currentSession.setlist[songIndex].firstPreset?.id
        }
        saveCurrentSession()
    }

    /// Move a preset within a song
    func movePreset(from sourceIndex: Int, to destinationIndex: Int, in songId: UUID) {
        guard let songIndex = currentSession.setlist.firstIndex(where: { $0.id == songId }),
              sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < currentSession.setlist[songIndex].presets.count,
              destinationIndex >= 0, destinationIndex < currentSession.setlist[songIndex].presets.count else {
            return
        }

        let preset = currentSession.setlist[songIndex].presets.remove(at: sourceIndex)
        currentSession.setlist[songIndex].presets.insert(preset, at: destinationIndex)

        // Update order values
        for (index, _) in currentSession.setlist[songIndex].presets.enumerated() {
            currentSession.setlist[songIndex].presets[index].order = index
        }

        saveCurrentSession()
    }

    // MARK: - Legacy Song Management (for backward compatibility)

    func setActiveLegacySong(_ song: PerformanceSong) {
        currentSession.activeSongId = song.id
        saveCurrentSession()
    }

    func addLegacySong(_ song: PerformanceSong) {
        var newSong = song
        newSong.order = currentSession.songs.count
        currentSession.songs.append(newSong)
        saveCurrentSession()
    }

    func updateLegacySong(_ song: PerformanceSong) {
        if let index = currentSession.songs.firstIndex(where: { $0.id == song.id }) {
            currentSession.songs[index] = song
            saveCurrentSession()
        }
    }

    func deleteLegacySong(_ song: PerformanceSong) {
        currentSession.songs.removeAll { $0.id == song.id }
        if currentSession.activeSongId == song.id {
            currentSession.activeSongId = currentSession.songs.first?.id
        }
        saveCurrentSession()
    }

    func moveLegacySong(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < currentSession.songs.count,
              destinationIndex >= 0, destinationIndex < currentSession.songs.count else {
            return
        }

        let song = currentSession.songs.remove(at: sourceIndex)
        currentSession.songs.insert(song, at: destinationIndex)

        // Update order values to match array positions
        for (index, _) in currentSession.songs.enumerated() {
            currentSession.songs[index].order = index
        }

        saveCurrentSession()
    }

    // MARK: - Channel Management
    
    func updateChannel(_ channel: ChannelConfiguration) {
        if let index = currentSession.channels.firstIndex(where: { $0.id == channel.id }) {
            currentSession.channels[index] = channel
            saveCurrentSession()
        }
    }
}
