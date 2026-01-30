import Foundation

/// Engine for scale-based note filtering and quantization
struct ScaleEngine {
    
    // MARK: - Scale Note Checking
    
    /// Check if a MIDI note is in the specified scale
    /// - Parameters:
    ///   - note: MIDI note number (0-127)
    ///   - root: Root note of the scale (0-11, where 0 = C)
    ///   - scale: Scale type (major or minor)
    /// - Returns: True if the note is in the scale
    static func isInScale(note: UInt8, root: Int, scale: ScaleType) -> Bool {
        let noteClass = Int(note) % 12
        let normalizedNote = (noteClass - root + 12) % 12
        return scale.intervals.contains(normalizedNote)
    }
    
    /// Get all notes in the scale within the MIDI range
    /// - Parameters:
    ///   - root: Root note of the scale (0-11)
    ///   - scale: Scale type
    /// - Returns: Array of all MIDI note numbers in the scale (0-127)
    static func scaleNotes(root: Int, scale: ScaleType) -> [UInt8] {
        var notes: [UInt8] = []
        for midiNote in 0...127 {
            let note = UInt8(midiNote)
            if isInScale(note: note, root: root, scale: scale) {
                notes.append(note)
            }
        }
        return notes
    }
    
    // MARK: - Note Quantization
    
    /// Snap a MIDI note to the nearest note in the scale
    /// - Parameters:
    ///   - note: MIDI note number (0-127)
    ///   - root: Root note of the scale (0-11)
    ///   - scale: Scale type
    /// - Returns: The nearest note in the scale
    static func snapToScale(note: UInt8, root: Int, scale: ScaleType) -> UInt8 {
        // If already in scale, return as-is
        if isInScale(note: note, root: root, scale: scale) {
            return note
        }

        let noteInt = Int(note)

        // Find nearest scale note below
        var noteBelow: Int? = nil
        for i in stride(from: noteInt - 1, through: 0, by: -1) {
            if isInScale(note: UInt8(i), root: root, scale: scale) {
                noteBelow = i
                break
            }
        }

        // Find nearest scale note above
        var noteAbove: Int? = nil
        for i in (noteInt + 1)...127 {
            if isInScale(note: UInt8(i), root: root, scale: scale) {
                noteAbove = i
                break
            }
        }

        // Choose the nearest one
        switch (noteBelow, noteAbove) {
        case (nil, let above?):
            return UInt8(above)
        case (let below?, nil):
            return UInt8(below)
        case (let below?, let above?):
            let distBelow = noteInt - below
            let distAbove = above - noteInt
            if distBelow < distAbove {
                return UInt8(below)
            } else if distAbove < distBelow {
                return UInt8(above)
            } else {
                // Equidistant: snap to the note with the same letter name
                // F# → F, Bb → B, etc. (accidentals resolve to their natural)
                return UInt8(snapEquidistantByLetter(noteInt: noteInt, below: below, above: above))
            }
        case (nil, nil):
            return note // Fallback
        }
    }
    
    /// When equidistant, snap to the note that shares the same letter name
    /// Uses common enharmonic spellings: C#, F# (sharps → down), Eb, Ab, Bb (flats → up)
    private static func snapEquidistantByLetter(noteInt: Int, below: Int, above: Int) -> Int {
        let pitchClass = noteInt % 12
        
        switch pitchClass {
        // Black keys - use most common enharmonic spelling
        case 1:  return below  // C# → C (sharp, resolve down)
        case 3:  return above  // Eb → E (flat, resolve up)
        case 6:  return below  // F# → F (sharp, resolve down)
        case 8:  return above  // Ab → A (flat, resolve up)
        case 10: return above  // Bb → B (flat, resolve up)
        
        // White keys out of scale - snap to altered version with same letter
        case 4:  return below  // E → Eb (if Eb in scale)
        case 11: return below  // B → Bb (if Bb in scale)
        case 0:  return above  // C → C# (if C# in scale)
        case 5:  return above  // F → F# (if F# in scale)
        
        default: return below  // D, G, A - default down
        }
    }
    
    // MARK: - Scale Degree Calculation
    
    /// Get the scale degree (1-7) for a note, or nil if not in scale
    /// - Parameters:
    ///   - note: MIDI note number
    ///   - root: Root note of the scale (0-11)
    ///   - scale: Scale type
    /// - Returns: Scale degree (1-7) or nil
    static func scaleDegree(note: UInt8, root: Int, scale: ScaleType) -> Int? {
        let noteClass = Int(note) % 12
        let normalizedNote = (noteClass - root + 12) % 12
        
        if let index = scale.intervals.firstIndex(of: normalizedNote) {
            return index + 1 // Return 1-based degree
        }
        return nil
    }
    
    /// Get the MIDI note for a scale degree in a specific octave
    /// - Parameters:
    ///   - degree: Scale degree (1-7)
    ///   - root: Root note (0-11)
    ///   - scale: Scale type
    ///   - octave: MIDI octave (0-10, middle C is octave 5)
    /// - Returns: MIDI note number
    static func noteForDegree(_ degree: Int, root: Int, scale: ScaleType, octave: Int = 4) -> UInt8 {
        guard degree >= 1 && degree <= 7 else { return 60 } // Default to middle C
        
        let interval = scale.intervals[degree - 1]
        let baseNote = octave * 12 + root + interval
        return UInt8(min(127, max(0, baseNote)))
    }
    
    // MARK: - Note Filtering
    
    /// Process a MIDI note based on filter mode
    /// - Parameters:
    ///   - note: Input MIDI note
    ///   - root: Scale root (0-11)
    ///   - scale: Scale type
    ///   - mode: Filter mode (block or snap)
    /// - Returns: Processed note, or nil if blocked
    static func filterNote(_ note: UInt8, root: Int, scale: ScaleType, mode: FilterMode) -> UInt8? {
        switch mode {
        case .block:
            return isInScale(note: note, root: root, scale: scale) ? note : nil
        case .snap:
            return snapToScale(note: note, root: root, scale: scale)
        }
    }
}
