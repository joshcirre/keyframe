import Foundation

/// Configuration for mapping ChordPad buttons to chord degrees
struct ChordMapping: Equatable {
    /// MIDI channel the ChordPad sends on (1-16, stored as 1-based)
    var chordPadChannel: Int

    /// Map of MIDI note number to scale degree (1-7)
    /// Key: MIDI note from ChordPad button, Value: Scale degree to play
    var buttonMap: [Int: Int]

    /// Base octave for chord output (MIDI octave, 4 = middle C octave)
    var baseOctave: Int

    // MARK: - Secondary Zone (Split Controller)

    /// Whether the secondary zone is enabled
    /// When enabled, notes starting from secondaryStartNote are routed to a specific track
    var secondaryZoneEnabled: Bool

    /// The first MIDI note of the secondary zone (degrees 1-7 are this note + 0-6)
    /// For example, if secondaryStartNote = 48 (C3), then:
    /// - Note 48 = degree 1, Note 49 = degree 2, ... Note 54 = degree 7
    var secondaryStartNote: Int?

    /// Target channel strip index for secondary zone (0-based)
    /// Notes in secondary zone go to this specific track
    var secondaryTargetChannel: Int?

    /// Base octave for secondary zone output (MIDI octave, 4 = middle C octave)
    var secondaryBaseOctave: Int

    /// Map of MIDI note number to scale degree for secondary zone (1-7)
    /// This replaces the consecutive-note approach when populated
    var secondaryButtonMap: [Int: Int]
    
    // MARK: - Default Configuration
    
    /// Default chord mapping for ChordPad (3x6 grid)
    /// Assumes ChordPad sends notes 36-53 for the 18 buttons
    static let defaultMapping = ChordMapping(
        chordPadChannel: 10,
        buttonMap: [
            // Row 1: Chords I, II, III, IV, V, VI
            36: 1,  // Button 1 → I chord
            37: 2,  // Button 2 → ii chord
            38: 3,  // Button 3 → iii chord
            39: 4,  // Button 4 → IV chord
            40: 5,  // Button 5 → V chord
            41: 6,  // Button 6 → vi chord

            // Row 2: Chords VII, then repeat with different voicings/octaves
            42: 7,  // Button 7 → vii° chord
            43: 1,  // Button 8 → I chord (can be configured differently)
            44: 4,  // Button 9 → IV chord
            45: 5,  // Button 10 → V chord
            46: 1,  // Button 11 → I chord
            47: 6,  // Button 12 → vi chord

            // Row 3: Common progressions
            48: 1,  // Button 13 → I
            49: 5,  // Button 14 → V
            50: 6,  // Button 15 → vi
            51: 4,  // Button 16 → IV
            52: 2,  // Button 17 → ii
            53: 5,  // Button 18 → V
        ],
        baseOctave: 4,
        secondaryZoneEnabled: false,
        secondaryStartNote: nil,
        secondaryTargetChannel: nil,
        secondaryBaseOctave: 4,
        secondaryButtonMap: [:]
    )
    
    // MARK: - Initialization

    init(
        chordPadChannel: Int = 10,
        buttonMap: [Int: Int] = [:],
        baseOctave: Int = 4,
        secondaryZoneEnabled: Bool = false,
        secondaryStartNote: Int? = nil,
        secondaryTargetChannel: Int? = nil,
        secondaryBaseOctave: Int = 4,
        secondaryButtonMap: [Int: Int] = [:]
    ) {
        self.chordPadChannel = chordPadChannel
        self.buttonMap = buttonMap
        self.baseOctave = baseOctave
        self.secondaryZoneEnabled = secondaryZoneEnabled
        self.secondaryStartNote = secondaryStartNote
        self.secondaryTargetChannel = secondaryTargetChannel
        self.secondaryBaseOctave = secondaryBaseOctave
        self.secondaryButtonMap = secondaryButtonMap
    }

    // MARK: - Helpers

    /// Check if a MIDI channel matches the ChordPad channel
    /// - Parameter channel: MIDI channel (0-15, 0-based as used in MIDI messages)
    /// - Returns: True if this is the ChordPad channel
    func isChordPadChannel(_ channel: UInt8) -> Bool {
        // MIDI channels in messages are 0-based (0-15)
        // We store as 1-based (1-16) for user-friendliness
        return Int(channel) + 1 == chordPadChannel
    }
    
    /// Get the scale degree for a MIDI note, if mapped
    func degreeForNote(_ note: UInt8) -> Int? {
        return buttonMap[Int(note)]
    }
    
    /// Update a button mapping
    mutating func setMapping(note: Int, degree: Int?) {
        if let degree = degree, degree >= 1 && degree <= 7 {
            buttonMap[note] = degree
        } else {
            buttonMap.removeValue(forKey: note)
        }
    }
    
    /// Get all mapped notes (primary chord zone)
    var mappedNotes: [Int] {
        Array(buttonMap.keys).sorted()
    }

    /// Check if a note is in the secondary zone
    func isSecondaryZoneNote(_ note: UInt8) -> Bool {
        guard secondaryZoneEnabled else { return false }
        // If we have individual mappings, use them
        if !secondaryButtonMap.isEmpty {
            return secondaryButtonMap[Int(note)] != nil
        }
        // Fall back to consecutive note range (legacy)
        guard let startNote = secondaryStartNote else { return false }
        let noteInt = Int(note)
        return noteInt >= startNote && noteInt < startNote + 7
    }

    /// Get the scale degree (1-7) for a secondary zone input note
    func secondaryDegree(_ note: UInt8) -> Int? {
        guard secondaryZoneEnabled else { return nil }
        // If we have individual mappings, use them
        if !secondaryButtonMap.isEmpty {
            return secondaryButtonMap[Int(note)]
        }
        // Fall back to consecutive note range (legacy)
        guard let startNote = secondaryStartNote else { return nil }
        let noteInt = Int(note)
        guard noteInt >= startNote && noteInt < startNote + 7 else { return nil }
        return noteInt - startNote + 1  // 1-based degree
    }
    
    /// Get a description of the mapping for a note
    func descriptionForNote(_ note: Int, rootNote: Int = 0, scaleType: ScaleType = .major) -> String {
        guard let degree = buttonMap[note] else { return "—" }
        let chordName = ChordEngine.chordName(degree: degree, rootNote: rootNote, scaleType: scaleType)
        let roman = ChordEngine.romanNumeral(degree: degree, scaleType: scaleType)
        return "\(roman) (\(chordName))"
    }
}

// MARK: - Codable with backwards compatibility

extension ChordMapping: Codable {
    enum CodingKeys: String, CodingKey {
        case chordPadChannel, buttonMap, baseOctave
        case secondaryZoneEnabled, secondaryStartNote, secondaryTargetChannel
        case secondaryBaseOctave, secondaryButtonMap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        chordPadChannel = try container.decode(Int.self, forKey: .chordPadChannel)
        buttonMap = try container.decode([Int: Int].self, forKey: .buttonMap)
        baseOctave = try container.decode(Int.self, forKey: .baseOctave)

        // Optional fields with defaults (for backwards compatibility)
        secondaryZoneEnabled = try container.decodeIfPresent(Bool.self, forKey: .secondaryZoneEnabled) ?? false
        secondaryStartNote = try container.decodeIfPresent(Int.self, forKey: .secondaryStartNote)
        secondaryTargetChannel = try container.decodeIfPresent(Int.self, forKey: .secondaryTargetChannel)
        secondaryBaseOctave = try container.decodeIfPresent(Int.self, forKey: .secondaryBaseOctave) ?? 4
        secondaryButtonMap = try container.decodeIfPresent([Int: Int].self, forKey: .secondaryButtonMap) ?? [:]
    }
}

// MARK: - ChordPad Grid Helper

extension ChordMapping {
    /// ChordPad grid layout helper (3 rows x 6 columns)
    struct ChordPadGrid {
        /// Get the note number for a grid position
        /// - Parameters:
        ///   - row: Row index (0-2)
        ///   - col: Column index (0-5)
        ///   - baseNote: Starting MIDI note for the grid (default 36 = C2)
        /// - Returns: MIDI note number
        static func noteAt(row: Int, col: Int, baseNote: Int = 36) -> Int {
            return baseNote + (row * 6) + col
        }
        
        /// Get the grid position for a note number
        /// - Parameters:
        ///   - note: MIDI note number
        ///   - baseNote: Starting MIDI note for the grid
        /// - Returns: Tuple of (row, col) or nil if outside grid
        static func positionFor(note: Int, baseNote: Int = 36) -> (row: Int, col: Int)? {
            let offset = note - baseNote
            guard offset >= 0 && offset < 18 else { return nil }
            return (row: offset / 6, col: offset % 6)
        }
    }
}
