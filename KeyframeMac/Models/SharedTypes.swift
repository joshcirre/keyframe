import Foundation

// MARK: - Scale Types

enum ScaleType: String, Codable, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"
    case harmonicMinor = "Harmonic Minor"
    case melodicMinor = "Melodic Minor"
    case dorian = "Dorian"
    case phrygian = "Phrygian"
    case lydian = "Lydian"
    case mixolydian = "Mixolydian"
    case locrian = "Locrian"
    case pentatonicMajor = "Pentatonic Major"
    case pentatonicMinor = "Pentatonic Minor"
    case blues = "Blues"
    case chromatic = "Chromatic"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var intervals: [Int] {
        switch self {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11]
        case .minor:
            return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor:
            return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor:
            return [0, 2, 3, 5, 7, 9, 11]
        case .dorian:
            return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian:
            return [0, 1, 3, 5, 7, 8, 10]
        case .lydian:
            return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian:
            return [0, 2, 4, 5, 7, 9, 10]
        case .locrian:
            return [0, 1, 3, 5, 6, 8, 10]
        case .pentatonicMajor:
            return [0, 2, 4, 7, 9]
        case .pentatonicMinor:
            return [0, 3, 5, 7, 10]
        case .blues:
            return [0, 3, 5, 6, 7, 10]
        case .chromatic:
            return Array(0...11)
        }
    }

    var chordQualities: [ChordQuality] {
        switch self {
        case .major:
            return [.major, .minor, .minor, .major, .major, .minor, .diminished]
        case .minor, .harmonicMinor, .melodicMinor:
            return [.minor, .diminished, .major, .minor, .minor, .major, .major]
        default:
            return [.major, .minor, .minor, .major, .major, .minor, .diminished]
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

    var intervals: [Int] {
        switch self {
        case .major:
            return [0, 4, 7]
        case .minor:
            return [0, 3, 7]
        case .diminished:
            return [0, 3, 6]
        }
    }
}

// MARK: - Note Names

enum NoteName: String, Codable, CaseIterable, Identifiable {
    case c = "C", db = "Db", d = "D", eb = "Eb", e = "E", f = "F"
    case gb = "Gb", g = "G", ab = "Ab", a = "A", bb = "Bb", b = "B"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var midiValue: Int {
        switch self {
        case .c: return 0
        case .db: return 1
        case .d: return 2
        case .eb: return 3
        case .e: return 4
        case .f: return 5
        case .gb: return 6
        case .g: return 7
        case .ab: return 8
        case .a: return 9
        case .bb: return 10
        case .b: return 11
        }
    }

    static func from(midiNote: UInt8) -> NoteName {
        let noteValues: [NoteName] = [.c, .db, .d, .eb, .e, .f, .gb, .g, .ab, .a, .bb, .b]
        return noteValues[Int(midiNote) % 12]
    }

    static func from(midiValue: Int) -> NoteName? {
        let noteValues: [NoteName] = [.c, .db, .d, .eb, .e, .f, .gb, .g, .ab, .a, .bb, .b]
        guard midiValue >= 0 && midiValue < 12 else { return nil }
        return noteValues[midiValue]
    }
}

// MARK: - MIDI Message Type

enum MIDIMessageType: String, Codable, CaseIterable, Identifiable {
    case programChange = "PC"
    case controlChange = "CC"
    case noteOn = "Note On"
    case noteOff = "Note Off"

    var id: String { rawValue }

    var requiresData2: Bool {
        switch self {
        case .programChange: return false
        case .controlChange, .noteOn, .noteOff: return true
        }
    }

    var data1Label: String {
        switch self {
        case .programChange: return "PROGRAM"
        case .controlChange: return "CC #"
        case .noteOn, .noteOff: return "NOTE"
        }
    }

    var data2Label: String {
        switch self {
        case .programChange: return ""
        case .controlChange: return "VALUE"
        case .noteOn, .noteOff: return "VELOCITY"
        }
    }
}

// MARK: - External MIDI Message

struct ExternalMIDIMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var type: MIDIMessageType
    var data1: Int
    var data2: Int

    init(
        id: UUID = UUID(),
        type: MIDIMessageType = .programChange,
        data1: Int = 0,
        data2: Int = 127
    ) {
        self.id = id
        self.type = type
        self.data1 = min(max(data1, 0), 127)
        self.data2 = min(max(data2, 0), 127)
    }

    var displayDescription: String {
        switch type {
        case .programChange:
            return "PC \(data1)"
        case .controlChange:
            return "CC \(data1) = \(data2)"
        case .noteOn:
            return "Note \(data1) ON vel \(data2)"
        case .noteOff:
            return "Note \(data1) OFF"
        }
    }

    /// Create a Helix setlist/bank select message (CC32)
    static func helixSetlist(_ setlistIndex: Int) -> ExternalMIDIMessage {
        ExternalMIDIMessage(type: .controlChange, data1: 32, data2: min(max(setlistIndex, 0), 7))
    }

    /// Create a Helix preset select message (Program Change)
    static func helixPreset(_ presetIndex: Int) -> ExternalMIDIMessage {
        ExternalMIDIMessage(type: .programChange, data1: min(max(presetIndex, 0), 127), data2: 0)
    }

    /// Create a Helix snapshot select message (CC69)
    static func helixSnapshot(_ snapshotIndex: Int) -> ExternalMIDIMessage {
        ExternalMIDIMessage(type: .controlChange, data1: 69, data2: min(max(snapshotIndex, 0), 7))
    }
}

// MARK: - Helix Preset Configuration

/// Represents a complete Helix preset configuration (setlist + preset + snapshot)
struct HelixPresetConfig: Codable, Equatable {
    var setlist: Int      // 0-7 (CC32 value)
    var preset: Int       // 0-127 (PC value)
    var snapshot: Int     // 0-7 (CC69 value)

    init(setlist: Int = 0, preset: Int = 0, snapshot: Int = 0) {
        self.setlist = min(max(setlist, 0), 7)
        self.preset = min(max(preset, 0), 127)
        self.snapshot = min(max(snapshot, 0), 7)
    }

    /// Human-readable display (1-indexed for users)
    var displayName: String {
        "Setlist \(setlist + 1), Preset \(preset + 1), Snap \(snapshot + 1)"
    }

    /// Convert to array of ExternalMIDIMessages
    func toMIDIMessages() -> [ExternalMIDIMessage] {
        [
            .helixSetlist(setlist),
            .helixPreset(preset),
            .helixSnapshot(snapshot)
        ]
    }
}

/// Helix setlist names (factory defaults)
enum HelixSetlist: Int, CaseIterable {
    case factory1 = 0
    case factory2 = 1
    case user1 = 2
    case user2 = 3
    case user3 = 4
    case user4 = 5
    case user5 = 6
    case user6 = 7

    var displayName: String {
        switch self {
        case .factory1: return "Factory 1"
        case .factory2: return "Factory 2"
        case .user1: return "User 1"
        case .user2: return "User 2"
        case .user3: return "User 3"
        case .user4: return "User 4"
        case .user5: return "User 5"
        case .user6: return "User 6"
        }
    }
}

// MARK: - Helix Default Messages

extension ExternalMIDIMessage {
    /// Generate default Helix messages based on preset index
    /// Uses User 1 setlist by default, with preset number matching the Keyframe preset index
    /// Snapshot 1 is used by default
    static func helixDefaults(forPresetIndex index: Int, setlist: Int = 2) -> [ExternalMIDIMessage] {
        [
            .helixSetlist(setlist),    // Default to User 1 (index 2)
            .helixPreset(index),        // Match Keyframe preset index
            .helixSnapshot(0)           // Default to Snapshot 1
        ]
    }

    /// Quick helper to create a basic Helix preset (just PC, no setlist/snapshot changes)
    static func helixPresetOnly(_ presetIndex: Int) -> ExternalMIDIMessage {
        .helixPreset(presetIndex)
    }
}

// MARK: - Chord Mapping

struct ChordMapping: Codable, Equatable {
    var chordPadChannel: Int
    var buttonMap: [Int: Int]
    var baseOctave: Int

    static let defaultMapping = ChordMapping(
        chordPadChannel: 10,
        buttonMap: [
            36: 1, 37: 2, 38: 3, 39: 4, 40: 5, 41: 6,
            42: 7, 43: 1, 44: 4, 45: 5, 46: 1, 47: 6,
            48: 1, 49: 5, 50: 6, 51: 4, 52: 2, 53: 5,
        ],
        baseOctave: 4
    )

    init(chordPadChannel: Int = 10, buttonMap: [Int: Int] = [:], baseOctave: Int = 4) {
        self.chordPadChannel = chordPadChannel
        self.buttonMap = buttonMap
        self.baseOctave = baseOctave
    }

    func isChordPadChannel(_ channel: UInt8) -> Bool {
        return Int(channel) + 1 == chordPadChannel
    }

    func degreeForNote(_ note: UInt8) -> Int? {
        return buttonMap[Int(note)]
    }

    mutating func setMapping(note: Int, degree: Int?) {
        if let degree = degree, degree >= 1 && degree <= 7 {
            buttonMap[note] = degree
        } else {
            buttonMap.removeValue(forKey: note)
        }
    }
}

// MARK: - Scale Engine (static methods)

enum ScaleEngine {
    static func isInScale(note: UInt8, root: Int, scale: ScaleType) -> Bool {
        let noteClass = Int(note) % 12
        let relativeNote = (noteClass - root + 12) % 12
        return scale.intervals.contains(relativeNote)
    }

    static func snapToScale(note: UInt8, root: Int, scale: ScaleType) -> UInt8 {
        let noteClass = Int(note) % 12
        let octave = Int(note) / 12
        let relativeNote = (noteClass - root + 12) % 12

        // Find nearest scale degree
        var minDistance = 12
        var nearestInterval = 0

        for interval in scale.intervals {
            let distance = min(abs(relativeNote - interval), 12 - abs(relativeNote - interval))
            if distance < minDistance {
                minDistance = distance
                nearestInterval = interval
            }
        }

        var snappedNote = (root + nearestInterval) % 12 + octave * 12
        if snappedNote < 0 { snappedNote += 12 }
        if snappedNote > 127 { snappedNote = 127 }

        return UInt8(snappedNote)
    }
}

// MARK: - Chord Engine (static methods)

enum ChordEngine {
    static func processChordTrigger(
        inputNote: UInt8,
        mapping: ChordMapping,
        rootNote: Int,
        scaleType: ScaleType,
        baseOctave: Int
    ) -> [UInt8]? {
        guard let degree = mapping.degreeForNote(inputNote) else { return nil }
        return generateChord(degree: degree, rootNote: rootNote, scaleType: scaleType, baseOctave: baseOctave)
    }

    static func generateChord(degree: Int, rootNote: Int, scaleType: ScaleType, baseOctave: Int) -> [UInt8] {
        guard degree >= 1 && degree <= 7 else { return [] }

        let intervals = scaleType.intervals
        let chordQualities = scaleType.chordQualities

        let degreeIndex = degree - 1
        let scaleInterval = intervals[degreeIndex]
        let chordQuality = chordQualities[degreeIndex]

        let chordRoot = (rootNote + scaleInterval) % 12
        let baseNote = chordRoot + (baseOctave + 1) * 12

        return chordQuality.intervals.map { interval in
            UInt8(min(127, max(0, baseNote + interval)))
        }
    }

    static func chordName(degree: Int, rootNote: Int, scaleType: ScaleType) -> String {
        guard degree >= 1 && degree <= 7 else { return "?" }

        let intervals = scaleType.intervals
        let chordQualities = scaleType.chordQualities

        let degreeIndex = degree - 1
        let scaleInterval = intervals[degreeIndex]
        let chordQuality = chordQualities[degreeIndex]

        let chordRoot = (rootNote + scaleInterval) % 12
        let noteName = NoteName.from(midiValue: chordRoot)?.displayName ?? "?"

        switch chordQuality {
        case .major: return noteName
        case .minor: return "\(noteName)m"
        case .diminished: return "\(noteName)dim"
        }
    }

    static func romanNumeral(degree: Int, scaleType: ScaleType) -> String {
        guard degree >= 1 && degree <= 7 else { return "?" }

        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let chordQualities = scaleType.chordQualities
        let quality = chordQualities[degree - 1]

        var numeral = numerals[degree - 1]
        switch quality {
        case .minor: numeral = numeral.lowercased()
        case .diminished: numeral = numeral.lowercased() + "°"
        case .major: break
        }

        return numeral
    }
}

// MARK: - Song (Legacy compatibility for applySongSettings)

struct Song: Codable {
    var rootNote: Int
    var scaleType: ScaleType
    var filterMode: FilterMode

    var keyDisplayName: String {
        let noteName = NoteName.from(midiValue: rootNote)?.displayName ?? "?"
        return "\(noteName) \(scaleType.rawValue)"
    }
}

// MARK: - Remote Preset Data (for iOS sync)

/// Lightweight preset data sent from Mac to iOS for remote mode
/// Does not include channel states (iOS doesn't need them in remote mode)
struct RemotePresetData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var index: Int              // Position in Mac's preset list (used for Program Change)
    var name: String
    var songName: String?       // Optional song/setlist name
    var bpm: Int?
    var rootNote: Int?          // NoteName raw value
    var scale: String?          // ScaleType raw value

    // iOS-only: External MIDI messages added locally
    // (not synced from Mac, stored separately on iOS)

    var displayName: String {
        if let songName = songName, !songName.isEmpty {
            return "\(songName) - \(name)"
        }
        return name
    }

    var keyDisplayName: String? {
        guard let rootNote = rootNote, let scale = scale else { return nil }
        let noteName = NoteName.from(midiValue: rootNote)?.displayName ?? "?"
        return "\(noteName) \(scale)"
    }
}
