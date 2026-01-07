import Foundation
import AudioToolbox
import UIKit

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
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String = "New Session",
        channels: [ChannelConfiguration] = [],
        masterVolume: Float = 1.0,
        songs: [PerformanceSong] = [],
        activeSongId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.masterVolume = masterVolume
        self.songs = songs
        self.activeSongId = activeSongId
        self.createdAt = Date()
        self.modifiedAt = Date()
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
    var isNM2ChordChannel: Bool
    var color: ChannelColor
    
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
        isNM2ChordChannel: Bool = false,
        color: ChannelColor = .cyan
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
        self.isNM2ChordChannel = isNM2ChordChannel
        self.color = color
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
    var name: String
    var rootNote: Int
    var scaleType: ScaleType
    var filterMode: FilterMode
    var bpm: Int?
    var channelStates: [ChannelPresetState]
    var order: Int  // For setlist ordering
    
    init(
        id: UUID = UUID(),
        name: String,
        rootNote: Int = 0,
        scaleType: ScaleType = .major,
        filterMode: FilterMode = .snap,
        bpm: Int? = nil,
        channelStates: [ChannelPresetState] = [],
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.rootNote = rootNote
        self.scaleType = scaleType
        self.filterMode = filterMode
        self.bpm = bpm
        self.channelStates = channelStates
        self.order = order
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
}

// MARK: - Channel Colors

enum ChannelColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, cyan, blue, indigo, purple, pink
    
    var id: String { rawValue }
    
    var uiColor: UIColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .mint: return .systemMint
        case .cyan: return .systemCyan
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        }
    }
}

// MARK: - Default Session

extension Session {
    /// Create a default session with 4 channels
    static func defaultSession() -> Session {
        let channels = [
            ChannelConfiguration(name: "Synth Pad", midiChannel: 1, color: .cyan),
            ChannelConfiguration(name: "Bass", midiChannel: 2, color: .purple),
            ChannelConfiguration(name: "Keys", midiChannel: 3, color: .green),
            ChannelConfiguration(name: "Lead", midiChannel: 4, isNM2ChordChannel: true, color: .orange)
        ]
        
        let songs = [
            PerformanceSong(name: "Intro", rootNote: 0, scaleType: .major, bpm: 120, order: 0),
            PerformanceSong(name: "Verse", rootNote: 9, scaleType: .minor, bpm: 120, order: 1),
            PerformanceSong(name: "Chorus", rootNote: 7, scaleType: .major, bpm: 120, order: 2),
            PerformanceSong(name: "Bridge", rootNote: 5, scaleType: .major, bpm: 100, order: 3),
            PerformanceSong(name: "Outro", rootNote: 0, scaleType: .major, bpm: 90, order: 4)
        ]
        
        return Session(
            name: "My Performance",
            channels: channels,
            songs: songs,
            activeSongId: songs.first?.id
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
    
    func saveSessions() {
        if let data = try? JSONEncoder().encode(savedSessions) {
            userDefaults.set(data, forKey: savedSessionsKey)
        }
    }
    
    func saveSessionAs(_ name: String) {
        var session = currentSession
        session.name = name
        savedSessions.append(session)
        saveSessions()
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
    
    // MARK: - Channel Management
    
    func updateChannel(_ channel: ChannelConfiguration) {
        if let index = currentSession.channels.firstIndex(where: { $0.id == channel.id }) {
            currentSession.channels[index] = channel
            saveCurrentSession()
        }
    }
}
