import Foundation

/// Represents a song with its key, scale, and preset configuration
struct Song: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var rootNote: Int           // 0-11 (C=0, Db=1, D=2, etc.)
    var scaleType: ScaleType    // Major or Minor
    var filterMode: FilterMode  // Block or Snap
    var preset: MIDIPreset      // Channel levels and plugin states
    
    // BPM settings
    var bpm: Int?               // Optional BPM (nil = don't send)
    var bpmCC: Int              // CC number to send BPM on (default 20)
    var bpmChannel: Int         // MIDI channel for BPM (1-16, stored as 1-based)
    
    // MARK: - Computed Properties
    
    /// Display name for the key (e.g., "C Major", "A Minor")
    var keyDisplayName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        return "\(noteName) \(scaleType.rawValue)"
    }
    
    /// Short key name (e.g., "Cmaj", "Amin")
    var keyShortName: String {
        let noteName = NoteName(rawValue: rootNote)?.displayName ?? "?"
        let scaleSuffix = scaleType == .major ? "maj" : "min"
        return "\(noteName)\(scaleSuffix)"
    }
    
    /// BPM display string
    var bpmDisplayString: String {
        if let bpm = bpm {
            return "\(bpm) BPM"
        }
        return "—"
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String,
        rootNote: Int,
        scaleType: ScaleType,
        filterMode: FilterMode = .snap,
        preset: MIDIPreset = MIDIPreset(),
        bpm: Int? = nil,
        bpmCC: Int = Int(MIDIConstants.defaultBPMCC),
        bpmChannel: Int = Int(MIDIConstants.defaultBPMChannel) + 1
    ) {
        self.id = id
        self.name = name
        self.rootNote = rootNote
        self.scaleType = scaleType
        self.filterMode = filterMode
        self.preset = preset
        self.bpm = bpm
        self.bpmCC = bpmCC
        self.bpmChannel = bpmChannel
    }
    
    // MARK: - Diatonic Chords
    
    /// Get all diatonic chord names for this song's key
    var diatonicChords: [String] {
        (1...7).map { degree in
            ChordEngine.chordName(degree: degree, rootNote: rootNote, scaleType: scaleType)
        }
    }
    
    /// Get Roman numeral representations
    var romanNumerals: [String] {
        (1...7).map { degree in
            ChordEngine.romanNumeral(degree: degree, scaleType: scaleType)
        }
    }
}

// MARK: - Sample Songs

extension Song {
    /// Sample songs for initial app state
    static let sampleSongs: [Song] = [
        Song(
            name: "Opening",
            rootNote: 0,  // C
            scaleType: .major,
            filterMode: .snap,
            preset: MIDIPreset(controls: [
                MIDIControl(name: "Synth Pad", ccNumber: 70, value: 100, controlType: .fader),
                MIDIControl(name: "Bass", ccNumber: 71, value: 80, controlType: .fader),
                MIDIControl(name: "Reverb", ccNumber: 80, value: 127, controlType: .toggle),
            ]),
            bpm: 120
        ),
        Song(
            name: "Verse",
            rootNote: 9,  // A
            scaleType: .minor,
            filterMode: .snap,
            preset: MIDIPreset(controls: [
                MIDIControl(name: "Synth Pad", ccNumber: 70, value: 90, controlType: .fader),
                MIDIControl(name: "Bass", ccNumber: 71, value: 100, controlType: .fader),
                MIDIControl(name: "Keys", ccNumber: 72, value: 80, controlType: .fader),
                MIDIControl(name: "Reverb", ccNumber: 80, value: 127, controlType: .toggle),
                MIDIControl(name: "Delay", ccNumber: 81, value: 0, controlType: .toggle),
            ]),
            bpm: 95
        ),
        Song(
            name: "Chorus",
            rootNote: 7,  // G
            scaleType: .major,
            filterMode: .block,
            preset: MIDIPreset(controls: [
                MIDIControl(name: "Synth Pad", ccNumber: 70, value: 127, controlType: .fader),
                MIDIControl(name: "Bass", ccNumber: 71, value: 100, controlType: .fader),
                MIDIControl(name: "Keys", ccNumber: 72, value: 100, controlType: .fader),
                MIDIControl(name: "Lead", ccNumber: 73, value: 90, controlType: .fader),
                MIDIControl(name: "Reverb", ccNumber: 80, value: 127, controlType: .toggle),
                MIDIControl(name: "Delay", ccNumber: 81, value: 127, controlType: .toggle),
                MIDIControl(name: "Chorus FX", ccNumber: 82, value: 127, controlType: .toggle),
            ]),
            bpm: 128
        ),
        Song(
            name: "Bridge",
            rootNote: 5,  // F
            scaleType: .major,
            filterMode: .snap,
            preset: MIDIPreset(controls: [
                MIDIControl(name: "Synth Pad", ccNumber: 70, value: 80, controlType: .fader),
                MIDIControl(name: "Bass", ccNumber: 71, value: 70, controlType: .fader),
                MIDIControl(name: "Strings", ccNumber: 74, value: 100, controlType: .fader),
                MIDIControl(name: "Delay", ccNumber: 81, value: 127, controlType: .toggle),
            ]),
            bpm: 100
        ),
        Song(
            name: "Outro",
            rootNote: 4,  // E
            scaleType: .minor,
            filterMode: .snap,
            preset: MIDIPreset(controls: [
                MIDIControl(name: "Synth Pad", ccNumber: 70, value: 70, controlType: .fader),
                MIDIControl(name: "Bass", ccNumber: 71, value: 60, controlType: .fader),
                MIDIControl(name: "Reverb", ccNumber: 80, value: 127, controlType: .toggle),
            ]),
            bpm: 80
        )
    ]
    
    /// Empty song template
    static func newSong(name: String = "New Song") -> Song {
        Song(
            name: name,
            rootNote: 0,
            scaleType: .major,
            filterMode: .snap,
            preset: MIDIPreset.empty,
            bpm: nil
        )
    }
}
