import Foundation

// MARK: - MIDI Message Type

/// Types of MIDI messages that can be sent to external devices
enum MIDIMessageType: String, Codable, CaseIterable, Identifiable {
    case programChange = "PC"
    case controlChange = "CC"
    case noteOn = "Note On"
    case noteOff = "Note Off"

    var id: String { rawValue }

    /// Whether this message type uses data2 (velocity/value)
    var requiresData2: Bool {
        switch self {
        case .programChange: return false
        case .controlChange, .noteOn, .noteOff: return true
        }
    }

    /// Label for the data1 field
    var data1Label: String {
        switch self {
        case .programChange: return "PROGRAM"
        case .controlChange: return "CC #"
        case .noteOn, .noteOff: return "NOTE"
        }
    }

    /// Label for the data2 field
    var data2Label: String {
        switch self {
        case .programChange: return ""
        case .controlChange: return "VALUE"
        case .noteOn, .noteOff: return "VELOCITY"
        }
    }
}

// MARK: - External MIDI Message

/// A MIDI message to send to external devices when a song preset is selected
/// Channel is set globally in MIDIEngine.externalMIDIChannel
struct ExternalMIDIMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var type: MIDIMessageType
    var data1: Int        // Note/CC/PC number (0-127)
    var data2: Int        // Velocity/Value (0-127), ignored for PC

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

    /// Human-readable description of the message
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
}

// MARK: - Remote Preset Data (synced from Mac)

/// Lightweight preset data received from Mac in remote mode
/// Does not include channel states (iOS doesn't need them in remote mode)
struct RemotePresetData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var index: Int              // Position in Mac's preset list (used for Program Change)
    var name: String
    var songName: String?       // Optional song/setlist name
    var bpm: Int?
    var rootNote: Int?          // NoteName raw value (0-11)
    var scale: String?          // ScaleType raw value

    var displayName: String {
        if let songName = songName, !songName.isEmpty {
            return "\(songName) - \(name)"
        }
        return name
    }

    var keyDisplayName: String? {
        guard let rootNote = rootNote, let scale = scale else { return nil }
        let noteNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        guard rootNote >= 0 && rootNote < 12 else { return nil }
        return "\(noteNames[rootNote]) \(scale)"
    }
}

// MARK: - Remote Preset (iOS storage with local external MIDI)

/// A remote preset with locally-added external MIDI messages for Helix
struct RemotePreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var remoteData: RemotePresetData        // Synced from Mac
    var externalMIDIMessages: [ExternalMIDIMessage] = []  // Added locally on iOS

    // Convenience accessors
    var index: Int { remoteData.index }
    var name: String { remoteData.name }
    var displayName: String { remoteData.displayName }
    var bpm: Int? { remoteData.bpm }
    var keyDisplayName: String? { remoteData.keyDisplayName }
}
