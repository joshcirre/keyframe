import Foundation
import AudioToolbox

// MARK: - Session Store

/// Manages the current session and saved sessions for macOS
final class MacSessionStore: ObservableObject {

    // MARK: - Singleton

    static let shared = MacSessionStore()

    // MARK: - Published Properties

    @Published var currentSession: MacSession
    @Published var savedSessions: [MacSession] = []
    @Published var currentPresetIndex: Int? {
        didSet {
            // Broadcast to iOS when preset changes (unless suppressed)
            if let index = currentPresetIndex, !suppressBroadcast {
                onPresetChanged?(index)
            }
        }
    }

    /// Callback when preset index changes - used for iOS sync
    var onPresetChanged: ((Int) -> Void)?

    /// Set to true to suppress broadcasting (e.g., when change came from iOS)
    var suppressBroadcast = false

    // Document state for file-based storage
    @Published var currentFileURL: URL?
    @Published var isDocumentDirty: Bool = false

    // MARK: - Persistence

    private let sessionsKey = "mac.savedSessions"
    private let currentSessionKey = "mac.currentSession"

    // MARK: - Initialization

    private init() {
        currentSession = MacSession()
        loadSessions()
        loadCurrentSession()
    }

    // MARK: - Session Management

    func saveCurrentSession() {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(currentSession) {
            defaults.set(data, forKey: currentSessionKey)
        }

        // Mark document as dirty (has unsaved changes to file)
        if currentFileURL != nil {
            isDocumentDirty = true
        }
    }

    func loadCurrentSession() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: currentSessionKey),
           let session = try? JSONDecoder().decode(MacSession.self, from: data) {
            currentSession = session
        }
    }

    func saveSessions() {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(savedSessions) {
            defaults.set(data, forKey: sessionsKey)
        }
    }

    func loadSessions() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: sessionsKey),
           let sessions = try? JSONDecoder().decode([MacSession].self, from: data) {
            savedSessions = sessions
        }
    }

    func addToSaved(_ session: MacSession) {
        var sessionToSave = session
        sessionToSave.id = UUID()  // New ID for saved copy
        savedSessions.append(sessionToSave)
        saveSessions()
    }

    func loadSession(_ session: MacSession) {
        currentSession = session
        saveCurrentSession()
    }

    func deleteSession(_ session: MacSession) {
        savedSessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    @discardableResult
    func updateSavedSession() -> Bool {
        saveCurrentSession()

        if let index = savedSessions.firstIndex(where: { $0.id == currentSession.id }) {
            savedSessions[index] = currentSession
            saveSessions()
            return true
        }
        return false
    }

    var isCurrentSessionSaved: Bool {
        savedSessions.contains { $0.id == currentSession.id }
    }

    // MARK: - Preset Management

    func setActivePreset(_ preset: MacPreset) {
        currentSession.activePresetId = preset.id
        saveCurrentSession()
    }

    func addPreset(_ preset: MacPreset) {
        currentSession.presets.append(preset)
        saveCurrentSession()
    }

    func updatePreset(_ preset: MacPreset) {
        if let index = currentSession.presets.firstIndex(where: { $0.id == preset.id }) {
            currentSession.presets[index] = preset
            saveCurrentSession()
        }
    }

    func deletePreset(_ preset: MacPreset) {
        currentSession.presets.removeAll { $0.id == preset.id }
        saveCurrentSession()
    }

    func movePreset(from source: Int, to destination: Int) {
        let preset = currentSession.presets.remove(at: source)
        currentSession.presets.insert(preset, at: destination)

        // Update order values
        for (index, var p) in currentSession.presets.enumerated() {
            p.order = index
            currentSession.presets[index] = p
        }
        saveCurrentSession()
    }

    // MARK: - Channel Management

    func addChannel(_ config: MacChannelConfiguration) {
        currentSession.channels.append(config)
        saveCurrentSession()
    }

    func updateChannel(_ config: MacChannelConfiguration) {
        if let index = currentSession.channels.firstIndex(where: { $0.id == config.id }) {
            currentSession.channels[index] = config
            saveCurrentSession()
        }
    }

    func removeChannel(at index: Int) {
        guard index < currentSession.channels.count else { return }
        currentSession.channels.remove(at: index)
        saveCurrentSession()
    }

    // MARK: - MIDI Mapping Management

    func addMIDIMapping(_ mapping: MIDICCMapping) {
        // Remove any existing mapping for the same CC/channel/source combination
        currentSession.midiMappings.removeAll {
            $0.cc == mapping.cc &&
            $0.channel == mapping.channel &&
            $0.sourceName == mapping.sourceName
        }
        currentSession.midiMappings.append(mapping)
        saveCurrentSession()
    }

    func removeMIDIMapping(_ mapping: MIDICCMapping) {
        currentSession.midiMappings.removeAll { $0.id == mapping.id }
        saveCurrentSession()
    }

    func clearMIDIMappings() {
        currentSession.midiMappings.removeAll()
        saveCurrentSession()
    }

    /// Remove all mappings targeting a specific channel (called when channel is deleted)
    func removeMappingsForChannel(_ channelId: UUID) {
        currentSession.midiMappings.removeAll { $0.targetChannelId == channelId }
        saveCurrentSession()
    }

    // MARK: - Preset Trigger Mapping Management

    func addPresetTriggerMapping(_ mapping: PresetTriggerMapping) {
        // Remove any existing mapping for the same trigger
        currentSession.presetTriggerMappings.removeAll {
            $0.triggerType == mapping.triggerType &&
            $0.data1 == mapping.data1 &&
            $0.channel == mapping.channel &&
            $0.sourceName == mapping.sourceName
        }
        currentSession.presetTriggerMappings.append(mapping)
        saveCurrentSession()
    }

    func removePresetTriggerMapping(_ mapping: PresetTriggerMapping) {
        currentSession.presetTriggerMappings.removeAll { $0.id == mapping.id }
        saveCurrentSession()
    }

    func clearPresetTriggerMappings() {
        currentSession.presetTriggerMappings.removeAll()
        saveCurrentSession()
    }

    /// Find matching trigger for incoming MIDI
    func findPresetTrigger(type: PresetTriggerType, channel: Int, data1: Int, data2: Int, sourceName: String?) -> PresetTriggerMapping? {
        currentSession.presetTriggerMappings.first { mapping in
            mapping.matches(type: type, channel: channel, data1: data1, data2: data2, sourceName: sourceName)
        }
    }

    // MARK: - Setlist Management

    func addSetlist(_ setlist: Setlist) {
        currentSession.setlists.append(setlist)
        saveCurrentSession()
    }

    func updateSetlist(_ setlist: Setlist) {
        if let index = currentSession.setlists.firstIndex(where: { $0.id == setlist.id }) {
            currentSession.setlists[index] = setlist
            saveCurrentSession()
        }
    }

    func deleteSetlist(_ setlist: Setlist) {
        currentSession.setlists.removeAll { $0.id == setlist.id }
        if currentSession.activeSetlistId == setlist.id {
            currentSession.activeSetlistId = nil
        }
        saveCurrentSession()
    }

    func setActiveSetlist(_ setlist: Setlist?) {
        currentSession.activeSetlistId = setlist?.id
        saveCurrentSession()
    }

    /// Navigate to next song in active setlist, returns the preset to activate
    func nextSetlistEntry() -> MacPreset? {
        guard let setlistId = currentSession.activeSetlistId,
              var setlist = currentSession.setlists.first(where: { $0.id == setlistId }),
              let entry = setlist.next() else { return nil }

        // Update the setlist in the session
        if let index = currentSession.setlists.firstIndex(where: { $0.id == setlistId }) {
            currentSession.setlists[index] = setlist
            saveCurrentSession()
        }

        return currentSession.presets.first { $0.id == entry.presetId }
    }

    /// Navigate to previous song in active setlist, returns the preset to activate
    func previousSetlistEntry() -> MacPreset? {
        guard let setlistId = currentSession.activeSetlistId,
              var setlist = currentSession.setlists.first(where: { $0.id == setlistId }),
              let entry = setlist.previous() else { return nil }

        // Update the setlist in the session
        if let index = currentSession.setlists.firstIndex(where: { $0.id == setlistId }) {
            currentSession.setlists[index] = setlist
            saveCurrentSession()
        }

        return currentSession.presets.first { $0.id == entry.presetId }
    }

    /// Jump to specific position in setlist
    func goToSetlistEntry(at index: Int) -> MacPreset? {
        guard let setlistId = currentSession.activeSetlistId,
              var setlist = currentSession.setlists.first(where: { $0.id == setlistId }),
              let entry = setlist.goTo(index: index) else { return nil }

        // Update the setlist in the session
        if let idx = currentSession.setlists.firstIndex(where: { $0.id == setlistId }) {
            currentSession.setlists[idx] = setlist
            saveCurrentSession()
        }

        return currentSession.presets.first { $0.id == entry.presetId }
    }
}

// MARK: - Session Model

struct MacSession: Codable, Identifiable {
    var id = UUID()
    var name: String = "Untitled Session"
    var channels: [MacChannelConfiguration] = []
    var presets: [MacPreset] = []
    var activePresetId: UUID?
    var masterVolume: Float = 1.0
    var midiMappings: [MIDICCMapping] = []
    var presetTriggerMappings: [PresetTriggerMapping] = []

    // Setlist support
    var setlists: [Setlist] = []
    var activeSetlistId: UUID?

    // Global settings
    var spilloverEnabled: Bool = true  // Smooth preset transitions

    var activePreset: MacPreset? {
        presets.first { $0.id == activePresetId }
    }

    var activeSetlist: Setlist? {
        setlists.first { $0.id == activeSetlistId }
    }

    /// Display name for window title
    var displayName: String {
        name.isEmpty ? "Untitled Session" : name
    }
}

// MARK: - Setlist Model

struct Setlist: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var entries: [SetlistEntry] = []
    var currentIndex: Int = 0

    init(name: String = "New Setlist") {
        self.name = name
    }

    var currentEntry: SetlistEntry? {
        guard currentIndex >= 0 && currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var currentPresetId: UUID? {
        currentEntry?.presetId
    }

    var hasNext: Bool {
        currentIndex < entries.count - 1
    }

    var hasPrevious: Bool {
        currentIndex > 0
    }

    mutating func next() -> SetlistEntry? {
        guard hasNext else { return nil }
        currentIndex += 1
        return currentEntry
    }

    mutating func previous() -> SetlistEntry? {
        guard hasPrevious else { return nil }
        currentIndex -= 1
        return currentEntry
    }

    mutating func goTo(index: Int) -> SetlistEntry? {
        guard index >= 0 && index < entries.count else { return nil }
        currentIndex = index
        return currentEntry
    }
}

struct SetlistEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var presetId: UUID
    var notes: String = ""          // Performance notes for this song
    var pauseAfter: Bool = false    // Optional pause between songs

    init(presetId: UUID, notes: String = "") {
        self.presetId = presetId
        self.notes = notes
    }
}

// MARK: - Channel Configuration

struct MacChannelConfiguration: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var instrument: MacPluginConfiguration?
    var effects: [MacPluginConfiguration]
    var volume: Float
    var pan: Float
    var isMuted: Bool
    var midiChannel: Int
    var midiSourceName: String?
    var scaleFilterEnabled: Bool
    var isChordPadTarget: Bool

    // Optional CC control mapping
    var controlSourceName: String?
    var controlChannel: Int?
    var controlCC: Int?

    // Keyboard zones (empty = full range, current behavior)
    var keyboardZones: [KeyboardZone] = []

    init(
        name: String = "New Channel",
        instrument: MacPluginConfiguration? = nil,
        effects: [MacPluginConfiguration] = [],
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        midiChannel: Int = 0,
        midiSourceName: String? = nil,
        scaleFilterEnabled: Bool = true,
        isChordPadTarget: Bool = false,
        keyboardZones: [KeyboardZone] = []
    ) {
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
        self.keyboardZones = keyboardZones
    }
}

// MARK: - Keyboard Zone (for splits/layers)

struct KeyboardZone: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Zone"
    var lowNote: Int = 0            // MIDI note 0-127
    var highNote: Int = 127         // MIDI note 0-127
    var transpose: Int = 0          // Semitones (-48 to +48)
    var velocityCurve: VelocityCurve = .linear
    var velocityFixed: Int = 100    // Fixed velocity value (when curve = .fixed)
    var isEnabled: Bool = true

    init(
        name: String = "Zone",
        lowNote: Int = 0,
        highNote: Int = 127,
        transpose: Int = 0,
        velocityCurve: VelocityCurve = .linear,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.lowNote = lowNote
        self.highNote = highNote
        self.transpose = transpose
        self.velocityCurve = velocityCurve
        self.isEnabled = isEnabled
    }

    /// Check if a note falls within this zone
    func contains(note: Int) -> Bool {
        isEnabled && note >= lowNote && note <= highNote
    }

    /// Apply zone transformations to a note
    func transform(note: Int, velocity: Int) -> (note: Int, velocity: Int)? {
        guard contains(note: note) else { return nil }

        let transposedNote = note + transpose
        guard transposedNote >= 0 && transposedNote <= 127 else { return nil }

        let adjustedVelocity: Int
        switch velocityCurve {
        case .linear:
            adjustedVelocity = velocity
        case .soft:
            // Compress velocity - quieter overall
            adjustedVelocity = Int(sqrt(Double(velocity) / 127.0) * 127.0)
        case .hard:
            // Expand velocity - louder overall
            adjustedVelocity = Int(pow(Double(velocity) / 127.0, 2) * 127.0)
        case .fixed:
            adjustedVelocity = velocityFixed
        }

        return (transposedNote, min(127, max(1, adjustedVelocity)))
    }

    /// Note name for display
    static func noteName(for midiNote: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (midiNote / 12) - 1
        let noteName = noteNames[midiNote % 12]
        return "\(noteName)\(octave)"
    }
}

enum VelocityCurve: String, Codable, CaseIterable {
    case linear = "Linear"
    case soft = "Soft"
    case hard = "Hard"
    case fixed = "Fixed"
}

// MARK: - Plugin Configuration

struct MacPluginConfiguration: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var manufacturerName: String
    var audioComponentDescription: AudioComponentDescription
    var presetData: Data?
    var isBypassed: Bool = false
}

// MARK: - Preset Model

struct MacPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var songName: String?
    var rootNote: NoteName?
    var scale: ScaleType?
    var filterMode: FilterMode
    var bpm: Double?
    var channelStates: [MacChannelState]
    var order: Int

    // MIDI trigger
    var triggerSourceName: String?
    var triggerChannel: Int?
    var triggerNote: Int?

    // External MIDI messages to send when preset is selected
    var externalMIDIMessages: [ExternalMIDIMessage] = []

    // Backing track for this preset
    var backingTrack: BackingTrack?

    init(
        id: UUID = UUID(),
        name: String = "New Preset",
        songName: String? = nil,
        rootNote: NoteName? = nil,
        scale: ScaleType? = nil,
        filterMode: FilterMode = .snap,
        bpm: Double? = nil,
        channelStates: [MacChannelState] = [],
        order: Int = 0,
        externalMIDIMessages: [ExternalMIDIMessage] = [],
        backingTrack: BackingTrack? = nil
    ) {
        self.id = id
        self.name = name
        self.songName = songName
        self.rootNote = rootNote
        self.scale = scale
        self.filterMode = filterMode
        self.bpm = bpm
        self.channelStates = channelStates
        self.order = order
        self.externalMIDIMessages = externalMIDIMessages
        self.backingTrack = backingTrack
    }
}

// MARK: - Backing Track

struct BackingTrack: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var fileBookmark: Data?         // Security-scoped bookmark for file access
    var filePath: String?           // Original file path (for display)
    var startPosition: Double = 0   // Start position in seconds
    var volume: Float = 1.0
    var isStereoSplit: Bool = false // True = left channel is click, right is music
    var clickVolume: Float = 1.0    // Volume for click track (left channel when split)
    var musicVolume: Float = 1.0    // Volume for music track (right channel when split)
    var autoStart: Bool = true      // Auto-start when preset is selected
    var loopEnabled: Bool = false

    init(
        name: String,
        fileBookmark: Data? = nil,
        filePath: String? = nil,
        autoStart: Bool = true
    ) {
        self.name = name
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.autoStart = autoStart
    }

    /// Resolve the security-scoped bookmark to get the file URL
    func resolveBookmark() -> URL? {
        guard let bookmark = fileBookmark else { return nil }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                print("BackingTrack: Bookmark is stale for '\(name)'")
            }
            return url
        } catch {
            print("BackingTrack: Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}

// MARK: - Channel State (for presets)

struct MacChannelState: Codable, Identifiable, Equatable {
    var id = UUID()
    var channelId: UUID
    var volume: Float
    var pan: Float
    var isMuted: Bool
    var isSoloed: Bool

    init(
        channelId: UUID,
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSoloed: Bool = false
    ) {
        self.channelId = channelId
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSoloed = isSoloed
    }
}

// MARK: - MIDI CC Mapping

/// Target types for MIDI CC mappings
enum MIDIMappingTarget: String, Codable, Equatable {
    case channelVolume      // Control a channel's volume fader
    case channelPan         // Control a channel's pan knob
    case channelMute        // Toggle a channel's mute
    case masterVolume       // Control master volume
    case pluginParameter    // Control a specific plugin parameter
}

/// A mapping from a MIDI CC to a controllable parameter
struct MIDICCMapping: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var cc: Int                         // CC number (0-127)
    var channel: Int?                   // MIDI channel (1-16, nil = any)
    var sourceName: String?             // MIDI source name (nil = any)
    var target: MIDIMappingTarget       // What to control
    var targetChannelId: UUID?          // For channel-specific targets
    var targetPluginId: UUID?           // For plugin parameter targets
    var targetParameterIndex: Int?      // Plugin parameter index
    var displayName: String             // User-friendly description

    init(
        cc: Int,
        channel: Int? = nil,
        sourceName: String? = nil,
        target: MIDIMappingTarget,
        targetChannelId: UUID? = nil,
        targetPluginId: UUID? = nil,
        targetParameterIndex: Int? = nil,
        displayName: String = ""
    ) {
        self.cc = cc
        self.channel = channel
        self.sourceName = sourceName
        self.target = target
        self.targetChannelId = targetChannelId
        self.targetPluginId = targetPluginId
        self.targetParameterIndex = targetParameterIndex
        self.displayName = displayName
    }

    /// Human-readable description of the mapping
    var description: String {
        let source = "CC \(cc)" + (channel != nil ? " Ch\(channel!)" : "")
        return "\(source) → \(displayName)"
    }
}

/// Represents the target being learned during MIDI Learn
struct MIDILearnTarget: Equatable {
    var target: MIDIMappingTarget
    var channelId: UUID?
    var pluginId: UUID?
    var parameterIndex: Int?
    var displayName: String

    static func channelVolume(channelId: UUID, name: String) -> MIDILearnTarget {
        MIDILearnTarget(target: .channelVolume, channelId: channelId, displayName: "\(name) Volume")
    }

    static func channelPan(channelId: UUID, name: String) -> MIDILearnTarget {
        MIDILearnTarget(target: .channelPan, channelId: channelId, displayName: "\(name) Pan")
    }

    static func channelMute(channelId: UUID, name: String) -> MIDILearnTarget {
        MIDILearnTarget(target: .channelMute, channelId: channelId, displayName: "\(name) Mute")
    }

    static var masterVolume: MIDILearnTarget {
        MIDILearnTarget(target: .masterVolume, displayName: "Master Volume")
    }

    static func pluginParameter(pluginId: UUID, parameterIndex: Int, parameterName: String) -> MIDILearnTarget {
        MIDILearnTarget(target: .pluginParameter, pluginId: pluginId, parameterIndex: parameterIndex, displayName: parameterName)
    }
}

// MARK: - Preset Trigger Mapping

/// Type of MIDI message that triggers a preset
enum PresetTriggerType: String, Codable, CaseIterable {
    case programChange = "Program Change"
    case controlChange = "Control Change"
    case noteOn = "Note On"

    var icon: String {
        switch self {
        case .programChange: return "pc.badge"
        case .controlChange: return "dial.min"
        case .noteOn: return "pianokeys"
        }
    }
}

/// Maps a MIDI message to a preset index
/// Supports Program Change, Control Change (value-based), or Note On triggers
struct PresetTriggerMapping: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var triggerType: PresetTriggerType
    var channel: Int?               // MIDI channel (1-16, nil = any)
    var sourceName: String?         // MIDI source filter (nil = any)
    var data1: Int                  // PC number, CC number, or Note number (0-127)
    var data2Min: Int?              // For CC/Note: min value (nil = 64 for toggle)
    var data2Max: Int?              // For CC/Note: max value (nil = 127)
    var presetIndex: Int            // Target preset index in session
    var displayName: String         // User-friendly description

    init(
        triggerType: PresetTriggerType,
        channel: Int? = nil,
        sourceName: String? = nil,
        data1: Int,
        data2Min: Int? = nil,
        data2Max: Int? = nil,
        presetIndex: Int,
        displayName: String = ""
    ) {
        self.triggerType = triggerType
        self.channel = channel
        self.sourceName = sourceName
        self.data1 = data1
        self.data2Min = data2Min
        self.data2Max = data2Max
        self.presetIndex = presetIndex
        self.displayName = displayName
    }

    /// Check if incoming MIDI matches this trigger
    func matches(type: PresetTriggerType, channel: Int, data1: Int, data2: Int, sourceName: String?) -> Bool {
        guard self.triggerType == type else { return false }
        guard self.data1 == data1 else { return false }

        // Channel filter (nil = any)
        if let requiredChannel = self.channel, requiredChannel != channel { return false }

        // Source filter (nil = any)
        if let requiredSource = self.sourceName, requiredSource != sourceName { return false }

        // For CC/Note, check value range
        if type == .controlChange || type == .noteOn {
            let minVal = data2Min ?? 64  // Default: trigger on values >= 64
            let maxVal = data2Max ?? 127
            guard data2 >= minVal && data2 <= maxVal else { return false }
        }

        return true
    }

    /// Human-readable trigger description
    var triggerDescription: String {
        var parts: [String] = []

        switch triggerType {
        case .programChange:
            parts.append("PC \(data1)")
        case .controlChange:
            parts.append("CC \(data1)")
        case .noteOn:
            parts.append("Note \(KeyboardZone.noteName(for: data1))")
        }

        if let ch = channel {
            parts.append("Ch \(ch)")
        }

        return parts.joined(separator: " ")
    }
}

/// Represents what we're learning during preset trigger MIDI Learn
struct PresetTriggerLearnTarget: Equatable {
    var presetIndex: Int
    var presetName: String
}

// MARK: - AudioComponentDescription Codable

extension AudioComponentDescription: Codable {
    enum CodingKeys: String, CodingKey {
        case componentType, componentSubType, componentManufacturer, componentFlags, componentFlagsMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            componentType: try container.decode(UInt32.self, forKey: .componentType),
            componentSubType: try container.decode(UInt32.self, forKey: .componentSubType),
            componentManufacturer: try container.decode(UInt32.self, forKey: .componentManufacturer),
            componentFlags: try container.decode(UInt32.self, forKey: .componentFlags),
            componentFlagsMask: try container.decode(UInt32.self, forKey: .componentFlagsMask)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(componentType, forKey: .componentType)
        try container.encode(componentSubType, forKey: .componentSubType)
        try container.encode(componentManufacturer, forKey: .componentManufacturer)
        try container.encode(componentFlags, forKey: .componentFlags)
        try container.encode(componentFlagsMask, forKey: .componentFlagsMask)
    }
}

extension AudioComponentDescription: Equatable {
    public static func == (lhs: AudioComponentDescription, rhs: AudioComponentDescription) -> Bool {
        lhs.componentType == rhs.componentType &&
        lhs.componentSubType == rhs.componentSubType &&
        lhs.componentManufacturer == rhs.componentManufacturer
    }
}
