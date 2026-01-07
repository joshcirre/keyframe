import Foundation

/// A single MIDI control assignment (CC number -> value)
struct MIDIControl: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String           // User-friendly name (e.g., "Synth Volume", "Reverb Bypass")
    var ccNumber: Int          // CC number (0-127)
    var midiChannel: Int       // MIDI channel (1-16, stored as 1-based)
    var value: Int             // Current value (0-127)
    var controlType: ControlType
    
    enum ControlType: String, Codable, CaseIterable {
        case fader = "Fader"       // Continuous 0-127
        case toggle = "Toggle"     // On/Off (0 or 127)
    }
    
    init(name: String, ccNumber: Int, midiChannel: Int = 1, value: Int = 0, controlType: ControlType = .fader) {
        self.name = name
        self.ccNumber = ccNumber
        self.midiChannel = midiChannel
        self.value = min(127, max(0, value))
        self.controlType = controlType
    }
    
    /// For toggles: is the control "on"?
    var isOn: Bool {
        get { value >= 64 }
        set { value = newValue ? 127 : 0 }
    }
    
    /// Value as percentage (0-100)
    var percentage: Int {
        get { Int(Double(value) / 127.0 * 100) }
        set { value = Int(Double(newValue) / 100.0 * 127) }
    }
}

/// MIDI preset containing dynamic list of controls for a song
struct MIDIPreset: Codable, Equatable {
    /// List of controls this preset changes
    var controls: [MIDIControl]
    
    // MARK: - Initialization
    
    init(controls: [MIDIControl] = []) {
        self.controls = controls
    }
    
    /// Create a preset from the old fixed format (for migration)
    init(channelLevels: [Int], pluginStates: [Bool]) {
        var controls: [MIDIControl] = []
        
        // Add channel faders
        for (index, level) in channelLevels.enumerated() {
            controls.append(MIDIControl(
                name: "Channel \(index + 1)",
                ccNumber: 70 + index,
                value: level,
                controlType: .fader
            ))
        }
        
        // Add plugin toggles
        for (index, state) in pluginStates.enumerated() {
            controls.append(MIDIControl(
                name: "Plugin \(index + 1)",
                ccNumber: 80 + index,
                value: state ? 127 : 0,
                controlType: .toggle
            ))
        }
        
        self.controls = controls
    }
    
    // MARK: - Control Management
    
    /// Add a new control
    mutating func addControl(_ control: MIDIControl) {
        controls.append(control)
    }
    
    /// Remove a control by ID
    mutating func removeControl(id: UUID) {
        controls.removeAll { $0.id == id }
    }
    
    /// Update a control's value
    mutating func setValue(_ value: Int, for controlId: UUID) {
        if let index = controls.firstIndex(where: { $0.id == controlId }) {
            controls[index].value = min(127, max(0, value))
        }
    }
    
    /// Get control by ID
    func control(id: UUID) -> MIDIControl? {
        controls.first { $0.id == id }
    }
    
    /// Get all fader controls
    var faders: [MIDIControl] {
        controls.filter { $0.controlType == .fader }
    }
    
    /// Get all toggle controls
    var toggles: [MIDIControl] {
        controls.filter { $0.controlType == .toggle }
    }
    
    // MARK: - MIDI Message Generation
    
    /// Generate all CC messages for this preset
    func allCCMessages() -> [(channel: UInt8, cc: UInt8, value: UInt8)] {
        controls.map { control in
            (
                channel: UInt8(control.midiChannel - 1),  // Convert to 0-based
                cc: UInt8(control.ccNumber),
                value: UInt8(control.value)
            )
        }
    }
    
    // MARK: - Presets / Templates
    
    /// Empty preset
    static let empty = MIDIPreset(controls: [])
    
    /// Default 4-channel + 8-plugin preset
    static var defaultPreset: MIDIPreset {
        var controls: [MIDIControl] = []
        
        for i in 0..<4 {
            controls.append(MIDIControl(
                name: "Channel \(i + 1)",
                ccNumber: 70 + i,
                value: 100,
                controlType: .fader
            ))
        }
        
        for i in 0..<8 {
            controls.append(MIDIControl(
                name: "Plugin \(i + 1)",
                ccNumber: 80 + i,
                value: 0,
                controlType: .toggle
            ))
        }
        
        return MIDIPreset(controls: controls)
    }
}

// MARK: - Display Helpers

extension MIDIPreset {
    /// Summary of the preset
    var summary: String {
        let faderCount = faders.count
        let activeToggles = toggles.filter { $0.isOn }.count
        let totalToggles = toggles.count
        
        var parts: [String] = []
        if faderCount > 0 {
            parts.append("\(faderCount) fader\(faderCount == 1 ? "" : "s")")
        }
        if totalToggles > 0 {
            parts.append("\(activeToggles)/\(totalToggles) FX on")
        }
        
        return parts.isEmpty ? "No controls" : parts.joined(separator: ", ")
    }
    
    /// Detailed description
    var detailedDescription: String {
        if controls.isEmpty {
            return "No MIDI controls configured"
        }
        
        return controls.map { control in
            if control.controlType == .toggle {
                return "\(control.name): \(control.isOn ? "ON" : "OFF")"
            } else {
                return "\(control.name): \(control.percentage)%"
            }
        }.joined(separator: "\n")
    }
}
