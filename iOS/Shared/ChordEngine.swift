import Foundation

/// Engine for generating diatonic chords and chord triggers
struct ChordEngine {
    
    // MARK: - Triad Generation
    
    /// Generate a diatonic tertian chord for a scale degree
    /// - Parameters:
    ///   - degree: Scale degree (1-7)
    ///   - rootNote: Root note of the key (0-11, where 0 = C)
    ///   - scaleType: Scale type (major or minor)
    ///   - octave: Base octave for the chord (MIDI octave, 4 = middle C octave)
    /// - Returns: Array of MIDI note numbers forming the chord
    static func tertianChord(
        degree: Int,
        rootNote: Int,
        scaleType: ScaleType,
        octave: Int = 4,
        noteCount: Int = 3
    ) -> [UInt8] {
        guard degree >= 1 && degree <= 7 else { return [] }

        let resolvedNoteCount = max(1, noteCount)
        var notes: [UInt8] = []

        for chordToneIndex in 0..<resolvedNoteCount {
            let scaleDegreeIndex = (degree - 1) + (chordToneIndex * 2)
            let octaveOffset = scaleDegreeIndex / scaleType.intervals.count
            let wrappedScaleIndex = scaleDegreeIndex % scaleType.intervals.count
            let midiNote = (octave * 12) + rootNote + scaleType.intervals[wrappedScaleIndex] + (octaveOffset * 12)
            if midiNote >= 0 && midiNote <= 127 {
                notes.append(UInt8(midiNote))
            }
        }

        return notes
    }

    /// Generate a diatonic triad for a scale degree
    static func triad(
        degree: Int,
        rootNote: Int,
        scaleType: ScaleType,
        octave: Int = 4
    ) -> [UInt8] {
        tertianChord(
            degree: degree,
            rootNote: rootNote,
            scaleType: scaleType,
            octave: octave,
            noteCount: 3
        )
    }
    
    /// Get the chord name for a scale degree
    /// - Parameters:
    ///   - degree: Scale degree (1-7)
    ///   - rootNote: Root note of the key (0-11)
    ///   - scaleType: Scale type
    /// - Returns: Chord name (e.g., "C", "Dm", "G")
    static func chordName(
        degree: Int,
        rootNote: Int,
        scaleType: ScaleType
    ) -> String {
        guard degree >= 1 && degree <= 7 else { return "?" }
        
        let degreeInterval = scaleType.intervals[degree - 1]
        let chordRoot = (rootNote + degreeInterval) % 12
        let noteName = NoteName(rawValue: chordRoot)?.displayName ?? "?"
        let quality = scaleType.chordQualities[degree - 1]
        
        switch quality {
        case .major:
            return noteName
        case .minor:
            return "\(noteName)m"
        case .diminished:
            return "\(noteName)°"
        }
    }
    
    /// Get Roman numeral notation for a scale degree
    /// - Parameters:
    ///   - degree: Scale degree (1-7)
    ///   - scaleType: Scale type
    /// - Returns: Roman numeral (e.g., "I", "ii", "V")
    static func romanNumeral(degree: Int, scaleType: ScaleType) -> String {
        guard degree >= 1 && degree <= 7 else { return "?" }
        
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let quality = scaleType.chordQualities[degree - 1]
        let numeral = numerals[degree - 1]
        
        switch quality {
        case .major:
            return numeral
        case .minor:
            return numeral.lowercased()
        case .diminished:
            return numeral.lowercased() + "°"
        }
    }
    
    // MARK: - Chord Trigger Processing
    
    /// Process an incoming MIDI note as a chord trigger
    /// - Parameters:
    ///   - inputNote: The MIDI note received from the ChordPad
    ///   - mapping: The chord mapping configuration
    ///   - rootNote: Current song's root note (0-11)
    ///   - scaleType: Current song's scale type
    ///   - baseOctave: Base octave for output chords
    /// - Returns: Array of MIDI notes for the chord, or nil if not mapped
    static func processChordTrigger(
        inputNote: UInt8,
        mapping: ChordMapping,
        rootNote: Int,
        scaleType: ScaleType,
        baseOctave: Int = 4,
        noteCount: Int = 3
    ) -> [UInt8]? {
        // Look up the scale degree for this button/note
        guard let degree = mapping.buttonMap[Int(inputNote)] else {
            return nil // Not a mapped button
        }
        
        // Generate the chord for this degree
        return tertianChord(
            degree: degree,
            rootNote: rootNote,
            scaleType: scaleType,
            octave: baseOctave,
            noteCount: noteCount
        )
    }
    
    // MARK: - Inversions (Future Enhancement)
    
    /// Generate a chord with optional inversion
    /// - Parameters:
    ///   - degree: Scale degree (1-7)
    ///   - rootNote: Root note of the key (0-11)
    ///   - scaleType: Scale type
    ///   - octave: Base octave
    ///   - inversion: 0 = root position, 1 = first inversion, 2 = second inversion
    /// - Returns: Array of MIDI notes
    static func triadWithInversion(
        degree: Int,
        rootNote: Int,
        scaleType: ScaleType,
        octave: Int = 4,
        inversion: Int = 0
    ) -> [UInt8] {
        var notes = triad(degree: degree, rootNote: rootNote, scaleType: scaleType, octave: octave)
        
        guard notes.count == 3, inversion > 0 else { return notes }
        
        // Apply inversion by moving bottom notes up an octave
        for i in 0..<min(inversion, 2) {
            if notes[i] + 12 <= 127 {
                notes[i] += 12
            }
        }
        
        return notes.sorted()
    }
}
