import Foundation

// MARK: - App Group Configuration
enum AppConstants {
    static let appGroupID = "group.com.keyframe.mki"
    static let activeSongKey = "activeSong"
    static let songListKey = "songList"
    static let chordMappingKey = "chordMapping"
    static let settingsKey = "settings"
    
    // Darwin notification for song changes
    static let songChangedNotification = "com.keyframe.mki.songChanged"
}

// MARK: - Scale Types
enum ScaleType: String, Codable, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"
    
    var id: String { rawValue }
    
    /// Intervals from root for each scale degree (semitones)
    var intervals: [Int] {
        switch self {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11] // W W H W W W H
        case .minor:
            return [0, 2, 3, 5, 7, 8, 10] // W H W W H W W (natural minor)
        }
    }
    
    /// Chord qualities for each scale degree (1-7)
    var chordQualities: [ChordQuality] {
        switch self {
        case .major:
            return [.major, .minor, .minor, .major, .major, .minor, .diminished]
        case .minor:
            return [.minor, .diminished, .major, .minor, .minor, .major, .major]
        }
    }
}

// MARK: - Filter Mode
enum FilterMode: String, Codable, CaseIterable, Identifiable {
    case block = "Block"
    case snap = "Snap"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .block:
            return "Block notes outside scale"
        case .snap:
            return "Snap to nearest scale note"
        }
    }
}

// MARK: - Chord Quality
enum ChordQuality: String, Codable {
    case major = "Major"
    case minor = "minor"
    case diminished = "dim"
    
    /// Intervals from root for the triad (semitones)
    var intervals: [Int] {
        switch self {
        case .major:
            return [0, 4, 7]      // Root, Major 3rd, Perfect 5th
        case .minor:
            return [0, 3, 7]      // Root, Minor 3rd, Perfect 5th
        case .diminished:
            return [0, 3, 6]      // Root, Minor 3rd, Diminished 5th
        }
    }
}

// MARK: - Note Names (using flats)
enum NoteName: Int, CaseIterable, Identifiable {
    case c = 0
    case db = 1
    case d = 2
    case eb = 3
    case e = 4
    case f = 5
    case gb = 6
    case g = 7
    case ab = 8
    case a = 9
    case bb = 10
    case b = 11
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .c: return "C"
        case .db: return "Db"
        case .d: return "D"
        case .eb: return "Eb"
        case .e: return "E"
        case .f: return "F"
        case .gb: return "Gb"
        case .g: return "G"
        case .ab: return "Ab"
        case .a: return "A"
        case .bb: return "Bb"
        case .b: return "B"
        }
    }
    
    static func from(midiNote: UInt8) -> NoteName {
        NoteName(rawValue: Int(midiNote) % 12)!
    }
}

// MARK: - MIDI Constants
enum MIDIConstants {
    static let noteOnStatus: UInt8 = 0x90
    static let noteOffStatus: UInt8 = 0x80
    static let controlChangeStatus: UInt8 = 0xB0
    static let programChangeStatus: UInt8 = 0xC0
    
    // Default CC mappings for AUM control
    static let defaultVolumeCC: UInt8 = 7
    static let defaultChannelVolumeCCs: [UInt8] = [70, 71, 72, 73] // For 4 channels
    static let defaultPluginBypassCCs: [UInt8] = [80, 81, 82, 83, 84, 85, 86, 87]
    
    // NM2 default channel
    static let defaultNM2Channel: UInt8 = 10
    
    // BPM CC (commonly used for tempo sync)
    static let defaultBPMCC: UInt8 = 20
    static let defaultBPMChannel: UInt8 = 0
    
    // Song selection via MIDI
    // Program Change on channel 16 (0-indexed: 15) will select songs
    static let songSelectChannel: UInt8 = 15
}
