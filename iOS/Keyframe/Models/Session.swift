import Foundation
import AudioToolbox

// MARK: - Unified MIDI Control Bindings

enum ControlMIDIMessageType: String, Codable, CaseIterable, Equatable {
    case controlChange
    case noteOn

    var displayName: String {
        switch self {
        case .controlChange: return "Control Change"
        case .noteOn: return "Note"
        }
    }
}

enum ControlBindingBehavior: String, Codable, CaseIterable, Equatable {
    case continuous
    case trigger
    case toggle
    case momentary

    var displayName: String { rawValue.capitalized }
}

struct ControlMIDIInput: Codable, Equatable {
    var messageType: ControlMIDIMessageType
    var number: Int
    var channel: Int?
    var sourceName: String?

    var displayName: String {
        let message = messageType == .controlChange ? "CC \(number)" : "NOTE \(number)"
        let channelName = channel.map { "CH \($0)" } ?? "ANY CH"
        return "\(message) · \(channelName)"
    }
}

enum ControlActionKind: String, Codable, CaseIterable, Equatable {
    case pluginParameter
    case pluginEnabled
    case pluginVisibility
    case channelVolume
    case channelMute
}

/// One destination in a MIDI control bundle. Parameter key paths are the persistent
/// identifier recommended by Audio Unit; the address is retained only as a fallback.
struct ControlAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ControlActionKind
    var channelId: UUID
    var pluginId: UUID?
    var parameterKeyPath: String?
    var parameterAddress: AUParameterAddress?
    var displayName: String
    var outputMinimum: Float = 0
    var outputMaximum: Float = 1
    var isInverted = false
}

struct ControlBinding: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var input: ControlMIDIInput
    var behavior: ControlBindingBehavior
    var actions: [ControlAction]
    var consumesEvent = true
    var isEnabled = true
}

/// Represents a complete performance session configuration
/// Includes all channels, plugins, and song presets
struct Session: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var channels: [ChannelConfiguration]
    var masterVolume: Float
    var songs: [PerformanceSong]
    var activeSongId: UUID?
    var createdAt: Date
    var modifiedAt: Date
    /// Optional keeps sessions created before unified control bindings decodable.
    var controlBindings: [ControlBinding]?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String = "New Session",
        channels: [ChannelConfiguration] = [],
        masterVolume: Float = 1.0,
        songs: [PerformanceSong] = [],
        activeSongId: UUID? = nil,
        controlBindings: [ControlBinding] = []
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.masterVolume = masterVolume
        self.songs = songs
        self.activeSongId = activeSongId
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.controlBindings = controlBindings
    }
    
    // MARK: - Helpers
    
    var activeSong: PerformanceSong? {
        songs.first { $0.id == activeSongId }
    }
    
    mutating func touch() {
        modifiedAt = Date()
    }
}

// MARK: - Channel Configuration

enum ChannelKind: String, Codable, CaseIterable, Equatable {
    case instrument
    case audioInput

    var displayName: String {
        switch self {
        case .instrument: return "Instrument"
        case .audioInput: return "Audio"
        }
    }
}

/// Configuration for a single channel in the session
struct ChannelConfiguration: Identifiable, Equatable {
    let id: UUID
    var kind: ChannelKind
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
    var isSingleNoteTarget: Bool

    /// Octave transpose for this channel (-3 to +3 octaves)
    var octaveTranspose: Int

    /// Preferred hardware input for audio channels. nil = current/default session input.
    var audioInputPortUID: String?
    var audioInputDisplayName: String?

    /// Preferred output pair for this channel. 0 = main output pair.
    var audioOutputPairIndex: Int

    // MIDI Control mapping (for fader/volume control)
    var controlSourceName: String?  // MIDI device that controls this channel's fader
    var controlChannel: Int?        // MIDI channel (1-16, nil = any channel)
    var controlCC: Int?             // CC number that controls volume (nil = not mapped)
    var controlNote: Int?           // Note number whose velocity controls volume (nil = not mapped)

    /// CC-to-AUParameter mappings for this channel's instrument
    var ccParameterMappings: [CCParameterMapping] = []

    init(
        id: UUID = UUID(),
        kind: ChannelKind = .instrument,
        name: String = "New Channel",
        instrument: PluginConfiguration? = nil,
        effects: [PluginConfiguration] = [],
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        midiChannel: Int = 0,
        midiSourceName: String? = "__none__",  // Default to NONE - user must select input
        scaleFilterEnabled: Bool = true,
        isChordPadTarget: Bool = false,
        isSingleNoteTarget: Bool = false,
        octaveTranspose: Int = 0,
        audioInputPortUID: String? = nil,
        audioInputDisplayName: String? = nil,
        audioOutputPairIndex: Int = 0,
        controlSourceName: String? = nil,
        controlChannel: Int? = nil,
        controlCC: Int? = nil,
        controlNote: Int? = nil,
        ccParameterMappings: [CCParameterMapping] = []
    ) {
        self.id = id
        self.kind = kind
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
        self.isSingleNoteTarget = isSingleNoteTarget
        self.octaveTranspose = octaveTranspose
        self.audioInputPortUID = audioInputPortUID
        self.audioInputDisplayName = audioInputDisplayName
        self.audioOutputPairIndex = audioOutputPairIndex
        self.controlSourceName = controlSourceName
        self.controlChannel = controlChannel
        self.controlCC = controlCC
        self.controlNote = controlNote
        self.ccParameterMappings = ccParameterMappings
    }
}

// MARK: - ChannelConfiguration Codable (backwards compatible)

extension ChannelConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, name, instrument, effects, volume, pan, isMuted
        case midiChannel, midiSourceName, scaleFilterEnabled
        case isChordPadTarget, isSingleNoteTarget, octaveTranspose
        case audioInputPortUID, audioInputDisplayName, audioOutputPairIndex
        case controlSourceName, controlChannel, controlCC, controlNote
        case ccParameterMappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(ChannelKind.self, forKey: .kind) ?? .instrument
        name = try container.decode(String.self, forKey: .name)
        instrument = try container.decodeIfPresent(PluginConfiguration.self, forKey: .instrument)
        effects = try container.decodeIfPresent([PluginConfiguration].self, forKey: .effects) ?? []
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        midiChannel = try container.decodeIfPresent(Int.self, forKey: .midiChannel) ?? 0
        midiSourceName = try container.decodeIfPresent(String.self, forKey: .midiSourceName) ?? "__none__"
        scaleFilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .scaleFilterEnabled) ?? true
        isChordPadTarget = try container.decodeIfPresent(Bool.self, forKey: .isChordPadTarget) ?? false
        // New fields - default to false/0 if missing
        isSingleNoteTarget = try container.decodeIfPresent(Bool.self, forKey: .isSingleNoteTarget) ?? false
        octaveTranspose = try container.decodeIfPresent(Int.self, forKey: .octaveTranspose) ?? 0
        audioInputPortUID = try container.decodeIfPresent(String.self, forKey: .audioInputPortUID)
        audioInputDisplayName = try container.decodeIfPresent(String.self, forKey: .audioInputDisplayName)
        audioOutputPairIndex = try container.decodeIfPresent(Int.self, forKey: .audioOutputPairIndex) ?? 0
        controlSourceName = try container.decodeIfPresent(String.self, forKey: .controlSourceName)
        controlChannel = try container.decodeIfPresent(Int.self, forKey: .controlChannel)
        controlCC = try container.decodeIfPresent(Int.self, forKey: .controlCC)
        controlNote = try container.decodeIfPresent(Int.self, forKey: .controlNote)
        ccParameterMappings = try container.decodeIfPresent([CCParameterMapping].self, forKey: .ccParameterMappings) ?? []
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

// MARK: - Performance Song

/// A song with scale settings and channel state presets
struct PerformanceSong: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // Preset name (e.g., "Clean Chorus")
    var songName: String?         // Optional song name (e.g., "The Joy")
    var rootNote: Int
    var scaleType: ScaleType
    var filterMode: FilterMode
    var chordPadPerformanceMode: ChordPadPerformanceMode
    var chordPadNoteCount: ChordPadNoteCount
    var chordPadStrumIntervalMs: Double
    var chordPadArpPattern: ChordPadArpPattern
    var chordPadArpRate: ChordPadArpRate
    var transposeEnabled: Bool
    var transposeBaseNote: Int
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
        chordPadPerformanceMode: ChordPadPerformanceMode = .hit,
        chordPadNoteCount: ChordPadNoteCount = .three,
        chordPadStrumIntervalMs: Double = 22,
        chordPadArpPattern: ChordPadArpPattern = .up,
        chordPadArpRate: ChordPadArpRate = .eighth,
        transposeEnabled: Bool = false,
        transposeBaseNote: Int? = nil,
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
        self.chordPadPerformanceMode = chordPadPerformanceMode
        self.chordPadNoteCount = chordPadNoteCount
        self.chordPadStrumIntervalMs = chordPadStrumIntervalMs
        self.chordPadArpPattern = chordPadArpPattern
        self.chordPadArpRate = chordPadArpRate
        self.transposeEnabled = transposeEnabled
        self.transposeBaseNote = transposeBaseNote ?? rootNote
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

    var playedRootNote: Int {
        transposeEnabled ? transposeBaseNote : rootNote
    }

    var playedKeyDisplayName: String {
        let noteName = NoteName(rawValue: playedRootNote)?.displayName ?? "?"
        return "\(noteName) \(scaleType.rawValue)"
    }

    var playedKeyShortName: String {
        let noteName = NoteName(rawValue: playedRootNote)?.displayName ?? "?"
        let suffix = scaleType == .major ? "maj" : "min"
        return "\(noteName)\(suffix)"
    }

    var transposeSemitones: Int {
        guard transposeEnabled else { return 0 }
        return NoteName.signedSemitoneDistance(from: playedRootNote, to: rootNote)
    }

    var transposeSemitoneDisplay: String {
        let semitones = transposeSemitones
        if semitones == 0 {
            return "0 ST"
        }

        let sign = semitones > 0 ? "+" : ""
        return "\(sign)\(semitones) ST"
    }

    var transposeDescription: String? {
        guard transposeEnabled else { return nil }

        let direction: String
        if transposeSemitones == 0 {
            direction = "UNISON"
        } else if transposeSemitones > 0 {
            direction = "UP \(abs(transposeSemitones)) SEMITONE\(abs(transposeSemitones) == 1 ? "" : "S")"
        } else {
            direction = "DOWN \(abs(transposeSemitones)) SEMITONE\(abs(transposeSemitones) == 1 ? "" : "S")"
        }

        return "PLAY \(playedKeyDisplayName.uppercased()) -> SOUND \(keyDisplayName.uppercased()) (\(direction))"
    }
}

// MARK: - PerformanceSong Codable (backwards compatible)

extension PerformanceSong {
    enum CodingKeys: String, CodingKey {
        case id, name, songName, rootNote, scaleType, filterMode
        case chordPadPerformanceMode, chordPadNoteCount, chordPadStrumIntervalMs, chordPadArpPattern, chordPadArpRate
        case transposeEnabled, transposeBaseNote
        case bpm, channelStates, order
        case triggerSourceName, triggerChannel, triggerNote
        case externalMIDIMessages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        songName = try container.decodeIfPresent(String.self, forKey: .songName)
        rootNote = try container.decodeIfPresent(Int.self, forKey: .rootNote) ?? 0
        scaleType = try container.decodeIfPresent(ScaleType.self, forKey: .scaleType) ?? .major
        filterMode = try container.decodeIfPresent(FilterMode.self, forKey: .filterMode) ?? .snap
        chordPadPerformanceMode = try container.decodeIfPresent(ChordPadPerformanceMode.self, forKey: .chordPadPerformanceMode) ?? .hit
        chordPadNoteCount = try container.decodeIfPresent(ChordPadNoteCount.self, forKey: .chordPadNoteCount) ?? .three
        chordPadStrumIntervalMs = try container.decodeIfPresent(Double.self, forKey: .chordPadStrumIntervalMs) ?? 22
        chordPadArpPattern = try container.decodeIfPresent(ChordPadArpPattern.self, forKey: .chordPadArpPattern) ?? .up
        chordPadArpRate = try container.decodeIfPresent(ChordPadArpRate.self, forKey: .chordPadArpRate) ?? .eighth
        transposeEnabled = try container.decodeIfPresent(Bool.self, forKey: .transposeEnabled) ?? false
        transposeBaseNote = try container.decodeIfPresent(Int.self, forKey: .transposeBaseNote) ?? rootNote
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm)
        channelStates = try container.decodeIfPresent([ChannelPresetState].self, forKey: .channelStates) ?? []
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        triggerSourceName = try container.decodeIfPresent(String.self, forKey: .triggerSourceName)
        triggerChannel = try container.decodeIfPresent(Int.self, forKey: .triggerChannel)
        triggerNote = try container.decodeIfPresent(Int.self, forKey: .triggerNote)
        externalMIDIMessages = try container.decodeIfPresent([ExternalMIDIMessage].self, forKey: .externalMIDIMessages) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(songName, forKey: .songName)
        try container.encode(rootNote, forKey: .rootNote)
        try container.encode(scaleType, forKey: .scaleType)
        try container.encode(filterMode, forKey: .filterMode)
        try container.encode(chordPadPerformanceMode, forKey: .chordPadPerformanceMode)
        try container.encode(chordPadNoteCount, forKey: .chordPadNoteCount)
        try container.encode(chordPadStrumIntervalMs, forKey: .chordPadStrumIntervalMs)
        try container.encode(chordPadArpPattern, forKey: .chordPadArpPattern)
        try container.encode(chordPadArpRate, forKey: .chordPadArpRate)
        try container.encode(transposeEnabled, forKey: .transposeEnabled)
        try container.encode(transposeBaseNote, forKey: .transposeBaseNote)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encode(channelStates, forKey: .channelStates)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(triggerSourceName, forKey: .triggerSourceName)
        try container.encodeIfPresent(triggerChannel, forKey: .triggerChannel)
        try container.encodeIfPresent(triggerNote, forKey: .triggerNote)
        try container.encode(externalMIDIMessages, forKey: .externalMIDIMessages)
    }
}

// MARK: - Default Session

extension Session {
    /// Create a default empty session
    static func defaultSession() -> Session {
        let songs = [
            PerformanceSong(name: "DEFAULT", rootNote: 0, scaleType: .major, bpm: 120, order: 0)
        ]

        return Session(
            name: "Untitled",
            channels: [],
            songs: songs,
            activeSongId: songs.first?.id
        )
    }
}

// MARK: - Session Store

/// Manages persistence of sessions
@Observable
@MainActor
final class SessionStore {

    static let shared = SessionStore()

    var currentSession: Session
    var savedSessions: [Session] = []

    @ObservationIgnored private let userDefaults = UserDefaults.standard
    @ObservationIgnored private let currentSessionKey = "currentSession"
    @ObservationIgnored private let savedSessionsKey = "savedSessions"

    private init() {
        // Load current session or create default
        if let data = userDefaults.data(forKey: currentSessionKey),
           let session = try? JSONDecoder().decode(Session.self, from: data) {
            currentSession = session
        } else {
            currentSession = Session.defaultSession()
        }
        
        // Load saved sessions
        if let data = userDefaults.data(forKey: savedSessionsKey),
           let sessions = try? JSONDecoder().decode([Session].self, from: data) {
            savedSessions = sessions
        }
    }
    
    func saveCurrentSession() {
        currentSession.touch()
        
        if let data = try? JSONEncoder().encode(currentSession) {
            userDefaults.set(data, forKey: currentSessionKey)
        }
    }

    var controlBindings: [ControlBinding] {
        currentSession.controlBindings ?? []
    }

    func upsertControlBinding(_ binding: ControlBinding) {
        var bindings = currentSession.controlBindings ?? []
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
        currentSession.controlBindings = bindings
        saveCurrentSession()
    }

    func removeControlBinding(id: UUID) {
        currentSession.controlBindings?.removeAll { $0.id == id }
        saveCurrentSession()
    }

    func removeControlBindings(channelId: UUID, pluginId: UUID? = nil) {
        currentSession.controlBindings?.removeAll { binding in
            binding.actions.contains { action in
                action.channelId == channelId && (pluginId == nil || action.pluginId == pluginId)
            }
        }
        saveCurrentSession()
    }
    
    /// Sync plugin preset state from AudioEngine's live channel strips back to the session config.
    /// Call this before saving to ensure instrument/effect presets are persisted.
    func syncPluginStateFromAudioEngine() {
        let strips = AudioEngine.shared.channelStrips
        
        for (index, strip) in strips.enumerated() {
            guard index < currentSession.channels.count else { continue }
            
            // Update instrument preset data
            if var instrument = currentSession.channels[index].instrument,
               let liveInstrument = strip.instrument {
                // Serialize the live plugin state
                if let state = liveInstrument.auAudioUnit.fullState,
                   let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) {
                    instrument.presetData = data
                    currentSession.channels[index].instrument = instrument
                }
            }
            
            // Update effect preset data
            for (effectIndex, effect) in strip.effects.enumerated() {
                guard effectIndex < currentSession.channels[index].effects.count else { continue }
                
                if let state = effect.auAudioUnit.fullState,
                   let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) {
                    currentSession.channels[index].effects[effectIndex].presetData = data
                }
                
                // Also sync bypass state
                currentSession.channels[index].effects[effectIndex].isBypassed = effect.auAudioUnit.shouldBypassEffect
            }
        }
        
        print("SessionStore: Synced plugin state from \(strips.count) channel strips")
    }
    
    func saveSessions() {
        if let data = try? JSONEncoder().encode(savedSessions) {
            userDefaults.set(data, forKey: savedSessionsKey)
        }
    }
    
    func saveSessionAs(_ name: String) {
        // Sync plugin state before saving
        syncPluginStateFromAudioEngine()
        
        // Create a NEW session with a new ID (standard "Save As" behavior)
        // This allows the original saved session to remain unchanged
        let newSession = Session(
            id: UUID(),  // New ID!
            name: name,
            channels: currentSession.channels,
            masterVolume: currentSession.masterVolume,
            songs: currentSession.songs,
            activeSongId: currentSession.activeSongId,
            controlBindings: currentSession.controlBindings ?? []
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
        // Sync plugin state before saving
        syncPluginStateFromAudioEngine()
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

    func loadSession(_ session: Session) {
        currentSession = session
        saveCurrentSession()
    }

    func deleteSession(_ session: Session) {
        savedSessions.removeAll { $0.id == session.id }
        saveSessions()
    }
    
    // MARK: - Song Management
    
    func setActiveSong(_ song: PerformanceSong) {
        currentSession.activeSongId = song.id
        saveCurrentSession()
    }
    
    func addSong(_ song: PerformanceSong) {
        var newSong = song
        newSong.order = currentSession.songs.count
        currentSession.songs.append(newSong)
        saveCurrentSession()
    }
    
    func updateSong(_ song: PerformanceSong) {
        if let index = currentSession.songs.firstIndex(where: { $0.id == song.id }) {
            currentSession.songs[index] = song
            saveCurrentSession()
        }
    }
    
    func deleteSong(_ song: PerformanceSong) {
        currentSession.songs.removeAll { $0.id == song.id }
        if currentSession.activeSongId == song.id {
            currentSession.activeSongId = currentSession.songs.first?.id
        }
        saveCurrentSession()
    }

    func moveSong(from sourceIndex: Int, to destinationIndex: Int) {
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
