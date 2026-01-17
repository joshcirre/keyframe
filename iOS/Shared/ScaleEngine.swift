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
        
        // Search up and down for nearest scale note
        var searchUp = noteInt + 1
        var searchDown = noteInt - 1
        
        while searchUp <= 127 || searchDown >= 0 {
            if searchDown >= 0 && isInScale(note: UInt8(searchDown), root: root, scale: scale) {
                return UInt8(searchDown)
            }
            if searchUp <= 127 && isInScale(note: UInt8(searchUp), root: root, scale: scale) {
                return UInt8(searchUp)
            }
            searchUp += 1
            searchDown -= 1
        }
        
        // Fallback (should never reach here)
        return note
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
