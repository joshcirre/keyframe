import Foundation

/// View model helper for editing chord mappings in the UI
/// Wraps ChordMapping from Shared for SwiftUI binding convenience
class ChordMapViewModel: ObservableObject {
    @Published var mapping: ChordMapping
    
    // MIDI Learn state
    @Published var isLearning = false
    @Published var learningForDegree: Int?  // Which degree we're learning a note for
    @Published var lastLearnedNote: Int?
    @Published var lastLearnedChannel: Int?
    @Published var learnedNotes: [Int: Int] = [:]  // degree -> note
    
    init(mapping: ChordMapping = .defaultMapping) {
        self.mapping = mapping
    }
    
    // MARK: - MIDI Learn
    
    /// Start learning mode for a specific degree
    func startLearning(forDegree degree: Int) {
        isLearning = true
        learningForDegree = degree
        lastLearnedNote = nil
        lastLearnedChannel = nil
    }
    
    /// Stop learning mode
    func stopLearning() {
        isLearning = false
        learningForDegree = nil
    }
    
    /// Handle a learned note
    func noteWasLearned(note: Int, channel: Int) {
        lastLearnedNote = note
        lastLearnedChannel = channel
        
        if let degree = learningForDegree {
            // Store the learned note -> degree mapping
            learnedNotes[degree] = note
            
            // Update the actual mapping
            mapping.setMapping(note: note, degree: degree)
            
            // Stop learning for this degree
            stopLearning()
        }
    }
    
    /// Clear all learned notes and reset
    func clearLearnedNotes() {
        learnedNotes.removeAll()
        lastLearnedNote = nil
        lastLearnedChannel = nil
    }
    
    /// Get note name for display
    func noteNameFor(_ midiNote: Int) -> String {
        let noteNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let octave = (midiNote / 12) - 1
        let noteName = noteNames[midiNote % 12]
        return "\(noteName)\(octave)"
    }
    
    // MARK: - NM2 Grid Access
    
    /// Get the degree for a grid position
    func degree(row: Int, col: Int) -> Int? {
        let note = ChordMapping.NM2Grid.noteAt(row: row, col: col)
        return mapping.buttonMap[note]
    }
    
    /// Set the degree for a grid position
    func setDegree(_ degree: Int?, row: Int, col: Int) {
        let note = ChordMapping.NM2Grid.noteAt(row: row, col: col)
        mapping.setMapping(note: note, degree: degree)
    }
    
    /// Get chord description for a grid position
    func chordDescription(row: Int, col: Int, rootNote: Int, scaleType: ScaleType) -> String {
        let note = ChordMapping.NM2Grid.noteAt(row: row, col: col)
        return mapping.descriptionForNote(note, rootNote: rootNote, scaleType: scaleType)
    }
    
    // MARK: - Channel Management
    
    var nm2Channel: Int {
        get { mapping.nm2Channel }
        set { mapping.nm2Channel = max(1, min(16, newValue)) }
    }
    
    var baseOctave: Int {
        get { mapping.baseOctave }
        set { mapping.baseOctave = max(0, min(8, newValue)) }
    }
    
    // MARK: - Preset Configurations
    
    /// Reset to default mapping
    func resetToDefault() {
        mapping = .defaultMapping
    }
    
    /// Clear all mappings
    func clearAllMappings() {
        mapping.buttonMap.removeAll()
    }
    
    /// Quick setup: Map first 7 buttons to degrees 1-7
    func setupSimpleLayout() {
        mapping.buttonMap.removeAll()
        for i in 0..<7 {
            let note = 36 + i
            mapping.buttonMap[note] = i + 1
        }
    }
    
    /// Quick setup: Map all buttons to I-IV-V-vi pattern (pop progression)
    func setupPopLayout() {
        mapping.buttonMap.removeAll()
        let pattern = [1, 5, 6, 4] // I-V-vi-IV
        for i in 0..<18 {
            let note = 36 + i
            mapping.buttonMap[note] = pattern[i % pattern.count]
        }
    }
}

// MARK: - Grid Button State

/// Represents the state of a button in the NM2 grid for UI purposes
struct NM2ButtonState: Identifiable {
    let id: Int  // MIDI note number
    let row: Int
    let col: Int
    var degree: Int?
    
    var hasMapping: Bool { degree != nil }
    
    /// Get display text for the button
    func displayText(rootNote: Int, scaleType: ScaleType) -> String {
        guard let degree = degree else { return "—" }
        return ChordEngine.romanNumeral(degree: degree, scaleType: scaleType)
    }
    
    /// Get chord name for the button
    func chordName(rootNote: Int, scaleType: ScaleType) -> String {
        guard let degree = degree else { return "" }
        return ChordEngine.chordName(degree: degree, rootNote: rootNote, scaleType: scaleType)
    }
    
    /// Get color for the degree (for visual differentiation)
    var degreeColorIndex: Int {
        degree ?? 0
    }
}

// MARK: - Grid Generator

extension ChordMapViewModel {
    /// Generate button states for the entire NM2 grid
    func generateGridStates() -> [[NM2ButtonState]] {
        var grid: [[NM2ButtonState]] = []
        
        for row in 0..<3 {
            var rowStates: [NM2ButtonState] = []
            for col in 0..<6 {
                let note = ChordMapping.NM2Grid.noteAt(row: row, col: col)
                let state = NM2ButtonState(
                    id: note,
                    row: row,
                    col: col,
                    degree: mapping.buttonMap[note]
                )
                rowStates.append(state)
            }
            grid.append(rowStates)
        }
        
        return grid
    }
}
