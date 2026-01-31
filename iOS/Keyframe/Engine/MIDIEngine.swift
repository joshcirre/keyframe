import CoreMIDI
import Foundation

/// Configuration for a single expression axis mapping
struct ExpressionAxisMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Expression"
    var sourceName: String? = nil  // nil = use global source, specific = dedicated source
    var inputCC: Int = 1
    var inputChannel: Int = 0  // 0 = any
    var outputCC: Int = 1
    var enabled: Bool = true
    var invert: Bool = false
    var outputAsPitchBend: Bool = false
    var pitchBendDown: Bool = false
    var scale: Double = 1.0  // 0.05 to 1.0
    
    static func defaultAxis1() -> ExpressionAxisMapping {
        ExpressionAxisMapping(name: "Mod Wheel", inputCC: 1, outputCC: 1)
    }
    
    static func defaultAxis2() -> ExpressionAxisMapping {
        ExpressionAxisMapping(name: "Filter", inputCC: 74, outputCC: 74)
    }
    
    static func defaultAxis3() -> ExpressionAxisMapping {
        ExpressionAxisMapping(name: "Vibrato", inputCC: 2, outputCC: 2, outputAsPitchBend: true, pitchBendDown: false, scale: 0.25)
    }
    
    static func defaultAxis4() -> ExpressionAxisMapping {
        ExpressionAxisMapping(name: "Expression", inputCC: 11, outputCC: 11)
    }
}

/// Integrated MIDI Engine with built-in scale filtering and chord generation
/// Replaces the need for a separate Scale Filter AUv3
@Observable
@MainActor
final class MIDIEngine {

    // MARK: - Singleton

    static let shared = MIDIEngine()

    // MARK: - Observable Properties

    private(set) var isInitialized = false
    private(set) var connectedSources: [MIDISourceInfo] = []
    private(set) var lastReceivedMessage: String?
    private(set) var lastActivity: Date?

    // MARK: - Scale/Chord Settings

    var currentRootNote: Int = 0  // C
    var currentScaleType: ScaleType = .major
    var filterMode: FilterMode = .snap
    var isScaleFilterEnabled = true

    // MARK: - ChordPad Settings (persisted)

    /// Flag to prevent saving during load
    @ObservationIgnored private var isLoadingSettings = false

    var chordPadSourceName: String? = nil {  // nil = disabled
        didSet { 
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }

    /// MIDI channel for chord triggers (1-16, 0 = any)
    var chordZoneChannel: Int = 10 {
        didSet { 
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }

    /// MIDI channel for single note triggers (1-16, 0 = any)
    var singleNoteZoneChannel: Int = 10 {
        didSet { 
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }

    var chordMapping: ChordMapping = .defaultMapping {
        didSet { 
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    // MARK: - Expression Axis Mappings (Dynamic Array)
    
    /// Global source for expression controllers (shared by all axes unless overridden)
    var expressionSourceName: String? = nil {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Dynamic array of expression axis mappings
    var expressionAxes: [ExpressionAxisMapping] = [] {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Maximum number of expression axes allowed
    let maxExpressionAxes = 8
    
    /// Force all pitch bend from LUMI to channel 1 (for non-MPE synths)
    var forcePitchBendToChannel1: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Add a new expression axis
    func addExpressionAxis() {
        guard expressionAxes.count < maxExpressionAxes else { return }
        let newAxis = ExpressionAxisMapping(name: "Axis \(expressionAxes.count + 1)")
        expressionAxes.append(newAxis)
    }
    
    /// Remove an expression axis by ID
    func removeExpressionAxis(id: UUID) {
        expressionAxes.removeAll { $0.id == id }
    }
    
    /// Update an expression axis
    func updateExpressionAxis(_ axis: ExpressionAxisMapping) {
        if let index = expressionAxes.firstIndex(where: { $0.id == axis.id }) {
            expressionAxes[index] = axis
        }
    }
    
    // MARK: - Legacy Global Expression Mappings (Axis 1 - e.g., joystick Y)
    
    /// Source for global expression controller (e.g., joystick)
    var globalExpressionSourceName: String? = nil {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// CC number to listen for from the expression source (default: CC1 = modulation)
    var globalExpressionInputCC: Int = 1 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// MIDI channel to listen for (0 = any, 1-16 = specific channel)
    var globalExpressionInputChannel: Int = 0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// CC number to output to all instruments (default: CC1 = modulation)
    var globalExpressionOutputCC: Int = 1 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Whether global expression is enabled
    var globalExpressionEnabled: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    // MARK: - Global Expression Mappings (Axis 2 - e.g., joystick X)
    
    /// CC number to listen for second axis (default: CC74 = filter)
    var globalExpression2InputCC: Int = 74 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// MIDI channel to listen for axis 2 (0 = any, 1-16 = specific)
    var globalExpression2InputChannel: Int = 0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// CC number to output for second axis (default: CC74 = filter)
    var globalExpression2OutputCC: Int = 74 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Whether second axis is enabled
    var globalExpression2Enabled: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Invert axis 2 output (127 - value) for filter-style controls
    var globalExpression2Invert: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    // MARK: - Global Expression Mappings (Axis 3)
    
    var globalExpression3InputCC: Int = 2 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression3InputChannel: Int = 0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression3OutputCC: Int = 2 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression3Enabled: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Output as pitch bend instead of CC (for vibrato)
    var globalExpression3OutputPitchBend: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Pitch bend direction: false = up from center, true = down from center
    var globalExpression3PitchBendDown: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Scale for axis 3 output (0.1 to 1.0, default 1.0 = full range)
    var globalExpression3Scale: Double = 1.0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    // MARK: - Global Expression Mappings (Axis 4)
    
    var globalExpression4InputCC: Int = 11 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression4InputChannel: Int = 0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression4OutputCC: Int = 11 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    var globalExpression4Enabled: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Output as pitch bend instead of CC (for vibrato)
    var globalExpression4OutputPitchBend: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Pitch bend direction: false = up from center, true = down from center
    var globalExpression4PitchBendDown: Bool = false {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Scale for axis 4 output (0.05 to 1.0, default 1.0 = full range)
    var globalExpression4Scale: Double = 1.0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    // MARK: - Expression Ramp Settings
    
    /// Ramp time for axis 1 in seconds (0 = instant, up to 2 seconds)
    var globalExpressionRampTime: Double = 0.0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Ramp time for axis 2 in seconds
    var globalExpression2RampTime: Double = 0.0 {
        didSet {
            if !isLoadingSettings { saveChordPadSettings() }
        }
    }
    
    /// Current smoothed values for ramping (updated by timer)
    @ObservationIgnored var axis1CurrentValue: Double = 0.0
    @ObservationIgnored var axis1TargetValue: Double = 0.0
    @ObservationIgnored var axis2CurrentValue: Double = 64.0  // Start at center for filter
    @ObservationIgnored var axis2TargetValue: Double = 64.0
    @ObservationIgnored private var rampTimer: Timer?

    /// Legacy property for backwards compatibility
    var chordPadChannel: Int {
        get { chordZoneChannel }
        set { chordZoneChannel = newValue }
    }

    // MARK: - Persistence Keys

    @ObservationIgnored private let chordZoneChannelKey = "chordZoneChannel"
    @ObservationIgnored private let singleNoteZoneChannelKey = "singleNoteZoneChannel"
    @ObservationIgnored private let chordPadSourceNameKey = "chordPadSourceName"
    @ObservationIgnored private let chordMappingKey = "chordMapping"
    // Expression axes (new dynamic system)
    @ObservationIgnored private let expressionSourceNameKey = "expressionSourceName"
    @ObservationIgnored private let expressionAxesKey = "expressionAxes"
    // Legacy key for migration
    @ObservationIgnored private let legacyChordPadChannelKey = "chordPadChannel"
    // Legacy Global expression keys (axis 1)
    @ObservationIgnored private let globalExpressionSourceNameKey = "globalExpressionSourceName"
    @ObservationIgnored private let globalExpressionInputCCKey = "globalExpressionInputCC"
    @ObservationIgnored private let globalExpressionInputChannelKey = "globalExpressionInputChannel"
    @ObservationIgnored private let globalExpressionOutputCCKey = "globalExpressionOutputCC"
    @ObservationIgnored private let globalExpressionEnabledKey = "globalExpressionEnabled"
    // Global expression keys (axis 2)
    @ObservationIgnored private let globalExpression2InputCCKey = "globalExpression2InputCC"
    @ObservationIgnored private let globalExpression2InputChannelKey = "globalExpression2InputChannel"
    @ObservationIgnored private let globalExpression2OutputCCKey = "globalExpression2OutputCC"
    @ObservationIgnored private let globalExpression2EnabledKey = "globalExpression2Enabled"
    @ObservationIgnored private let globalExpression2InvertKey = "globalExpression2Invert"
    // Global expression keys (axis 3)
    @ObservationIgnored private let globalExpression3InputCCKey = "globalExpression3InputCC"
    @ObservationIgnored private let globalExpression3InputChannelKey = "globalExpression3InputChannel"
    @ObservationIgnored private let globalExpression3OutputCCKey = "globalExpression3OutputCC"
    @ObservationIgnored private let globalExpression3EnabledKey = "globalExpression3Enabled"
    @ObservationIgnored private let globalExpression3OutputPitchBendKey = "globalExpression3OutputPitchBend"
    @ObservationIgnored private let globalExpression3PitchBendDownKey = "globalExpression3PitchBendDown"
    @ObservationIgnored private let globalExpression3ScaleKey = "globalExpression3Scale"
    // Global expression keys (axis 4)
    @ObservationIgnored private let globalExpression4InputCCKey = "globalExpression4InputCC"
    @ObservationIgnored private let globalExpression4InputChannelKey = "globalExpression4InputChannel"
    @ObservationIgnored private let globalExpression4OutputCCKey = "globalExpression4OutputCC"
    @ObservationIgnored private let globalExpression4EnabledKey = "globalExpression4Enabled"
    @ObservationIgnored private let globalExpression4OutputPitchBendKey = "globalExpression4OutputPitchBend"
    @ObservationIgnored private let globalExpression4PitchBendDownKey = "globalExpression4PitchBendDown"
    @ObservationIgnored private let globalExpression4ScaleKey = "globalExpression4Scale"
    // Ramp settings
    @ObservationIgnored private let globalExpressionRampTimeKey = "globalExpressionRampTime"
    @ObservationIgnored private let globalExpression2RampTimeKey = "globalExpression2RampTime"
    // Pitch bend routing
    @ObservationIgnored private let forcePitchBendToChannel1Key = "forcePitchBendToChannel1"

    // MARK: - MIDI Learn Mode

    var isLearningMode = false
    var isCCLearningMode = false
    @ObservationIgnored var onNoteLearn: ((Int, Int, String?) -> Void)?  // (note, channel, sourceName)
    @ObservationIgnored var onCCLearn: ((Int, Int, String?) -> Void)?    // (cc, channel, sourceName)

    // MARK: - Control Callbacks

    @ObservationIgnored var onSongTrigger: ((Int, Int, String?) -> Void)?       // (note, channel, sourceName) - for triggering songs
    @ObservationIgnored var onFaderControl: ((Int, Int, Int, String?) -> Void)? // (cc, value, channel, sourceName) - for fader control

    // MARK: - CoreMIDI

    @ObservationIgnored private var midiClient: MIDIClientRef = 0
    @ObservationIgnored private var inputPort: MIDIPortRef = 0
    @ObservationIgnored private var outputPort: MIDIPortRef = 0

    // MARK: - MIDI Output Settings

    private(set) var availableDestinations: [MIDIDestinationInfo] = []
    var selectedDestinationEndpoint: MIDIEndpointRef? = nil {
        didSet {
            // Only save if not currently restoring (to avoid erasing saved name when device not yet discovered)
            if !isRestoringDestination {
                saveOutputSettings()
            }
        }
    }
    @ObservationIgnored private var isRestoringDestination = false
    @ObservationIgnored private var savedDestinationName: String?  // Keep saved name even if device not available yet
    var externalMIDIChannel: Int = 1 {  // 1-16
        didSet { saveOutputSettings() }
    }
    var isNetworkSessionEnabled: Bool = false {
        didSet {
            configureNetworkSession()
            saveOutputSettings()
        }
    }

    /// The network session name (read-only, set by iOS based on device name)
    var networkSessionName: String {
        MIDINetworkSession.default().localName
    }

    // MARK: - External Tempo Sync

    var isExternalTempoSyncEnabled: Bool = false {
        didSet { saveOutputSettings() }
    }
    var tapTempoCC: Int = 64 {  // Helix default tap tempo CC
        didSet { saveOutputSettings() }
    }

    /// Current session BPM for display purposes (default 90, updated when presets with BPM are selected)
    var currentBPM: Int = 90

    // Persistence keys for output settings
    private let selectedDestinationKey = "midiOutputDestination"
    private let externalMIDIChannelKey = "externalMIDIChannel"
    private let networkSessionEnabledKey = "midiNetworkSessionEnabled"
    private let externalTempoSyncEnabledKey = "externalTempoSyncEnabled"
    private let tapTempoCCKey = "tapTempoCC"
    
    // Track active notes for proper note-off handling
    // Key: "sourceName|channel|note", Value: Dictionary of channelStripId -> (processedNote, midiChannel) pairs
    private var activeNotes: [String: [UUID: [(note: UInt8, channel: UInt8)]]] = [:]
    
    /// Generate a stable key for note tracking (avoids hash collisions)
    private func noteTrackingKey(sourceName: String?, channel: UInt8, note: UInt8) -> String {
        "\(sourceName ?? "_")|\(channel)|\(note)"
    }
    
    // Reference count for output notes - allows multiple inputs to map to same output
    // Key: (channelStripId, outputNote, midiChannel), Value: count of inputs currently holding this note
    // Only sends Note-Off when count reaches 0
    private var outputNoteRefCount: [String: Int] = [:]
    
    private func outputNoteKey(channelId: UUID, note: UInt8, midiChannel: UInt8 = 0) -> String {
        "\(channelId.uuidString)-\(note)-\(midiChannel)"
    }
    
    // Legacy for non-MPE contexts
    private func outputNoteKeyLegacy(channelId: UUID, note: UInt8) -> String {
        return "\(channelId.uuidString):\(note)"
    }
    
    // Source endpoint to name mapping
    private var sourceNameMap: [MIDIEndpointRef: String] = [:]
    
    // Current source being processed (set in callback via connection ref)
    private var currentSourceName: String? = nil
    
    // MARK: - Audio Engine Reference
    
    private weak var audioEngine: AudioEngine?
    
    // MARK: - Initialization

    private init() {
        loadChordPadSettings()
        loadOutputSettings()
        setupMIDI()
        startRampTimer()
    }
    
    /// Start the expression ramp timer (runs at 60Hz for smooth updates)
    private func startRampTimer() {
        rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateRampedValues()
        }
    }
    
    /// Update ramped expression values and send CC if changed
    private func updateRampedValues() {
        guard let audioEngine = audioEngine else { return }
        
        let dt = 1.0 / 60.0  // Timer interval
        
        // Axis 1 ramping
        if globalExpressionEnabled && globalExpressionRampTime > 0 {
            let rampRate = dt / max(0.01, globalExpressionRampTime)
            let diff = axis1TargetValue - axis1CurrentValue
            if abs(diff) > 0.5 {
                axis1CurrentValue += diff * min(1.0, rampRate * 10)
                let outputValue = UInt8(max(0, min(127, Int(axis1CurrentValue))))
                let outputCC = UInt8(globalExpressionOutputCC)
                for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                    strip.sendMIDI(controlChange: outputCC, value: outputValue)
                }
            }
        }
        
        // Axis 2 ramping (with invert)
        if globalExpression2Enabled && globalExpression2RampTime > 0 {
            let rampRate = dt / max(0.01, globalExpression2RampTime)
            let diff = axis2TargetValue - axis2CurrentValue
            if abs(diff) > 0.5 {
                axis2CurrentValue += diff * min(1.0, rampRate * 10)
                var outputValue = Int(axis2CurrentValue)
                if globalExpression2Invert {
                    outputValue = 127 - outputValue
                }
                let outputCC = UInt8(globalExpression2OutputCC)
                for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                    strip.sendMIDI(controlChange: outputCC, value: UInt8(max(0, min(127, outputValue))))
                }
            }
        }
    }

    // MARK: - ChordPad Persistence
    
    private func loadChordPadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        
        let defaults = UserDefaults.standard

        // Load chord zone channel (with migration from legacy key)
        if defaults.object(forKey: chordZoneChannelKey) != nil {
            chordZoneChannel = defaults.integer(forKey: chordZoneChannelKey)
        } else if defaults.object(forKey: legacyChordPadChannelKey) != nil {
            // Migrate from old single channel setting
            chordZoneChannel = defaults.integer(forKey: legacyChordPadChannelKey)
        }

        // Load single note zone channel (defaults to same as chord zone if not set)
        if defaults.object(forKey: singleNoteZoneChannelKey) != nil {
            singleNoteZoneChannel = defaults.integer(forKey: singleNoteZoneChannelKey)
        } else {
            singleNoteZoneChannel = chordZoneChannel
        }

        // Load source name
        chordPadSourceName = defaults.string(forKey: chordPadSourceNameKey)

        // Load chord mapping
        if let data = defaults.data(forKey: chordMappingKey),
           let mapping = try? JSONDecoder().decode(ChordMapping.self, from: data) {
            chordMapping = mapping
        }
        
        // Load expression axes (new dynamic system)
        expressionSourceName = defaults.string(forKey: expressionSourceNameKey)
        if let data = defaults.data(forKey: expressionAxesKey),
           let axes = try? JSONDecoder().decode([ExpressionAxisMapping].self, from: data) {
            expressionAxes = axes
        }
        
        // Load legacy global expression settings (axis 1)
        globalExpressionSourceName = defaults.string(forKey: globalExpressionSourceNameKey)
        if defaults.object(forKey: globalExpressionInputCCKey) != nil {
            globalExpressionInputCC = defaults.integer(forKey: globalExpressionInputCCKey)
        }
        globalExpressionInputChannel = defaults.integer(forKey: globalExpressionInputChannelKey)
        if defaults.object(forKey: globalExpressionOutputCCKey) != nil {
            globalExpressionOutputCC = defaults.integer(forKey: globalExpressionOutputCCKey)
        }
        globalExpressionEnabled = defaults.bool(forKey: globalExpressionEnabledKey)
        
        // Load global expression settings (axis 2)
        if defaults.object(forKey: globalExpression2InputCCKey) != nil {
            globalExpression2InputCC = defaults.integer(forKey: globalExpression2InputCCKey)
        }
        globalExpression2InputChannel = defaults.integer(forKey: globalExpression2InputChannelKey)
        if defaults.object(forKey: globalExpression2OutputCCKey) != nil {
            globalExpression2OutputCC = defaults.integer(forKey: globalExpression2OutputCCKey)
        }
        globalExpression2Enabled = defaults.bool(forKey: globalExpression2EnabledKey)
        globalExpression2Invert = defaults.bool(forKey: globalExpression2InvertKey)
        
        // Load global expression settings (axis 3)
        if defaults.object(forKey: globalExpression3InputCCKey) != nil {
            globalExpression3InputCC = defaults.integer(forKey: globalExpression3InputCCKey)
        }
        globalExpression3InputChannel = defaults.integer(forKey: globalExpression3InputChannelKey)
        if defaults.object(forKey: globalExpression3OutputCCKey) != nil {
            globalExpression3OutputCC = defaults.integer(forKey: globalExpression3OutputCCKey)
        }
        globalExpression3Enabled = defaults.bool(forKey: globalExpression3EnabledKey)
        globalExpression3OutputPitchBend = defaults.bool(forKey: globalExpression3OutputPitchBendKey)
        globalExpression3PitchBendDown = defaults.bool(forKey: globalExpression3PitchBendDownKey)
        if defaults.object(forKey: globalExpression3ScaleKey) != nil {
            globalExpression3Scale = defaults.double(forKey: globalExpression3ScaleKey)
        }
        
        // Load global expression settings (axis 4)
        if defaults.object(forKey: globalExpression4InputCCKey) != nil {
            globalExpression4InputCC = defaults.integer(forKey: globalExpression4InputCCKey)
        }
        globalExpression4InputChannel = defaults.integer(forKey: globalExpression4InputChannelKey)
        if defaults.object(forKey: globalExpression4OutputCCKey) != nil {
            globalExpression4OutputCC = defaults.integer(forKey: globalExpression4OutputCCKey)
        }
        globalExpression4Enabled = defaults.bool(forKey: globalExpression4EnabledKey)
        globalExpression4OutputPitchBend = defaults.bool(forKey: globalExpression4OutputPitchBendKey)
        globalExpression4PitchBendDown = defaults.bool(forKey: globalExpression4PitchBendDownKey)
        if defaults.object(forKey: globalExpression4ScaleKey) != nil {
            globalExpression4Scale = defaults.double(forKey: globalExpression4ScaleKey)
        }
        
        // Load ramp settings
        globalExpressionRampTime = defaults.double(forKey: globalExpressionRampTimeKey)
        globalExpression2RampTime = defaults.double(forKey: globalExpression2RampTimeKey)
        
        // Load pitch bend routing
        forcePitchBendToChannel1 = defaults.bool(forKey: forcePitchBendToChannel1Key)
    }

    private func saveChordPadSettings() {
        guard !isLoadingSettings else { return }
        
        let defaults = UserDefaults.standard

        defaults.set(chordZoneChannel, forKey: chordZoneChannelKey)
        defaults.set(singleNoteZoneChannel, forKey: singleNoteZoneChannelKey)
        defaults.set(chordPadSourceName, forKey: chordPadSourceNameKey)

        if let data = try? JSONEncoder().encode(chordMapping) {
            defaults.set(data, forKey: chordMappingKey)
        }
        
        // Save expression axes (new dynamic system)
        defaults.set(expressionSourceName, forKey: expressionSourceNameKey)
        if let data = try? JSONEncoder().encode(expressionAxes) {
            defaults.set(data, forKey: expressionAxesKey)
        }
        
        // Save legacy global expression settings (axis 1)
        defaults.set(globalExpressionSourceName, forKey: globalExpressionSourceNameKey)
        defaults.set(globalExpressionInputCC, forKey: globalExpressionInputCCKey)
        defaults.set(globalExpressionInputChannel, forKey: globalExpressionInputChannelKey)
        defaults.set(globalExpressionOutputCC, forKey: globalExpressionOutputCCKey)
        defaults.set(globalExpressionEnabled, forKey: globalExpressionEnabledKey)
        
        // Save global expression settings (axis 2)
        defaults.set(globalExpression2InputCC, forKey: globalExpression2InputCCKey)
        defaults.set(globalExpression2InputChannel, forKey: globalExpression2InputChannelKey)
        defaults.set(globalExpression2OutputCC, forKey: globalExpression2OutputCCKey)
        defaults.set(globalExpression2Enabled, forKey: globalExpression2EnabledKey)
        defaults.set(globalExpression2Invert, forKey: globalExpression2InvertKey)
        
        // Save global expression settings (axis 3)
        defaults.set(globalExpression3InputCC, forKey: globalExpression3InputCCKey)
        defaults.set(globalExpression3InputChannel, forKey: globalExpression3InputChannelKey)
        defaults.set(globalExpression3OutputCC, forKey: globalExpression3OutputCCKey)
        defaults.set(globalExpression3Enabled, forKey: globalExpression3EnabledKey)
        defaults.set(globalExpression3OutputPitchBend, forKey: globalExpression3OutputPitchBendKey)
        defaults.set(globalExpression3PitchBendDown, forKey: globalExpression3PitchBendDownKey)
        defaults.set(globalExpression3Scale, forKey: globalExpression3ScaleKey)
        
        // Save global expression settings (axis 4)
        defaults.set(globalExpression4InputCC, forKey: globalExpression4InputCCKey)
        defaults.set(globalExpression4InputChannel, forKey: globalExpression4InputChannelKey)
        defaults.set(globalExpression4OutputCC, forKey: globalExpression4OutputCCKey)
        defaults.set(globalExpression4Enabled, forKey: globalExpression4EnabledKey)
        defaults.set(globalExpression4OutputPitchBend, forKey: globalExpression4OutputPitchBendKey)
        defaults.set(globalExpression4PitchBendDown, forKey: globalExpression4PitchBendDownKey)
        defaults.set(globalExpression4Scale, forKey: globalExpression4ScaleKey)
        
        // Save ramp settings
        defaults.set(globalExpressionRampTime, forKey: globalExpressionRampTimeKey)
        defaults.set(globalExpression2RampTime, forKey: globalExpression2RampTimeKey)
        
        // Save pitch bend routing
        defaults.set(forcePitchBendToChannel1, forKey: forcePitchBendToChannel1Key)
        
        // Force synchronize to ensure data is written immediately
        defaults.synchronize()
    }

    // MARK: - Output Settings Persistence

    private func loadOutputSettings() {
        let defaults = UserDefaults.standard

        // Load network session state (but don't trigger didSet yet)
        let networkEnabled = defaults.bool(forKey: networkSessionEnabledKey)

        // Load channel
        if defaults.object(forKey: externalMIDIChannelKey) != nil {
            externalMIDIChannel = defaults.integer(forKey: externalMIDIChannelKey)
        }

        // Load tempo sync settings
        isExternalTempoSyncEnabled = defaults.bool(forKey: externalTempoSyncEnabledKey)
        if defaults.object(forKey: tapTempoCCKey) != nil {
            tapTempoCC = defaults.integer(forKey: tapTempoCCKey)
        }

        // Configure network session before refreshing destinations
        if networkEnabled {
            isNetworkSessionEnabled = networkEnabled
        }
    }

    private func saveOutputSettings() {
        let defaults = UserDefaults.standard

        defaults.set(externalMIDIChannel, forKey: externalMIDIChannelKey)
        defaults.set(isNetworkSessionEnabled, forKey: networkSessionEnabledKey)
        defaults.set(isExternalTempoSyncEnabled, forKey: externalTempoSyncEnabledKey)
        defaults.set(tapTempoCC, forKey: tapTempoCCKey)

        // Save selected destination by name (endpoints can change between launches)
        if let endpoint = selectedDestinationEndpoint,
           let dest = availableDestinations.first(where: { $0.endpoint == endpoint }) {
            savedDestinationName = dest.name
            defaults.set(dest.name, forKey: selectedDestinationKey)
        } else if savedDestinationName == nil {
            // Only clear if we don't have a saved name (device might just be offline)
            defaults.removeObject(forKey: selectedDestinationKey)
        }
        // If savedDestinationName is set but endpoint is nil, keep the saved name for later
    }

    private func restoreSelectedDestination() {
        let defaults = UserDefaults.standard

        // Load saved name if we haven't already
        if savedDestinationName == nil {
            savedDestinationName = defaults.string(forKey: selectedDestinationKey)
        }

        guard let savedName = savedDestinationName else { return }

        // Try to find the device - it might not be discovered yet (especially Bluetooth)
        isRestoringDestination = true
        if let dest = availableDestinations.first(where: { $0.name == savedName }) {
            selectedDestinationEndpoint = dest.endpoint
        }
        isRestoringDestination = false
    }

    deinit {
        // Note: teardownMIDI requires MainActor but deinit is nonisolated
        // CoreMIDI cleanup handled when the MIDIClientRef is deallocated
    }
    
    func setAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }
    
    // MARK: - MIDI Setup
    
    private func setupMIDI() {
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock("Keyframe Performance" as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        
        guard status == noErr else {
            print("MIDIEngine: Failed to create client: \(status)")
            return
        }
        
        // Create input port
        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            // srcConnRefCon is the endpoint ref we passed when connecting
            var sourceName: String? = nil
            if let refCon = srcConnRefCon {
                // Convert pointer back to MIDIEndpointRef (UInt32)
                let endpoint = MIDIEndpointRef(truncatingIfNeeded: UInt(bitPattern: refCon))
                sourceName = self?.sourceNameMap[endpoint]
            }
            self?.handleMIDIEventList(eventList, sourceName: sourceName)
        }
        
        guard status == noErr else {
            print("MIDIEngine: Failed to create input port: \(status)")
            return
        }

        // Create output port for external MIDI
        status = MIDIOutputPortCreate(
            midiClient,
            "Output" as CFString,
            &outputPort
        )

        guard status == noErr else {
            print("MIDIEngine: Failed to create output port: \(status)")
            return
        }

        isInitialized = true
        connectToAllSources()
        refreshDestinations()
    }
    
    private func teardownMIDI() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
    
    // MARK: - MIDI Notifications
    
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        let messageID = notification.pointee.messageID
        
        if messageID == .msgSetupChanged {
            DispatchQueue.main.async { [weak self] in
                self?.connectToAllSources()
            }
        }
    }
    
    // MARK: - Source Management
    
    /// Connect to all available MIDI sources
    func connectToAllSources() {
        guard isInitialized else { return }
        
        // Clear existing mappings
        sourceNameMap.removeAll()
        
        var sources: [MIDISourceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let name = getEndpointName(source) ?? "Unknown"
            
            // Store source name mapping
            sourceNameMap[source] = name
            
            // Connect to this source, passing the endpoint as the connection reference
            // This lets us identify which source sent each message
            let refCon = UnsafeMutableRawPointer(bitPattern: Int(source))
            let status = MIDIPortConnectSource(inputPort, source, refCon)
            
            if status == noErr {
                let info = MIDISourceInfo(
                    endpoint: source,
                    name: name,
                    isConnected: true
                )
                sources.append(info)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.connectedSources = sources
        }
    }
    
    private func getEndpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)

        if status == noErr, let name = name {
            return name.takeRetainedValue() as String
        }
        return nil
    }

    // MARK: - Destination Management

    /// Scan for available MIDI output destinations
    func refreshDestinations() {
        var destinations: [MIDIDestinationInfo] = []
        let destinationCount = MIDIGetNumberOfDestinations()

        for i in 0..<destinationCount {
            let destination = MIDIGetDestination(i)
            let name = getEndpointName(destination) ?? "Unknown"

            let info = MIDIDestinationInfo(
                endpoint: destination,
                name: name
            )
            destinations.append(info)
        }

        DispatchQueue.main.async { [weak self] in
            self?.availableDestinations = destinations
            self?.restoreSelectedDestination()
        }
    }

    /// Configure Network MIDI session
    private func configureNetworkSession() {
        let networkSession = MIDINetworkSession.default()

        networkSession.isEnabled = isNetworkSessionEnabled
        networkSession.connectionPolicy = isNetworkSessionEnabled ? .anyone : .noOne

        // Refresh destinations to include/exclude network endpoints
        refreshDestinations()
    }

    // MARK: - External MIDI Output

    /// Send external MIDI messages to the configured destination
    /// These messages are output only and do not affect internal app state
    func sendExternalMIDIMessages(_ messages: [ExternalMIDIMessage]) {
        guard let destination = selectedDestinationEndpoint else { return }
        guard outputPort != 0 else { return }

        for message in messages {
            sendMIDIMessage(message, to: destination)
        }
    }

    private func sendMIDIMessage(_ message: ExternalMIDIMessage, to destination: MIDIEndpointRef) {
        let channel = UInt8(externalMIDIChannel - 1)  // Convert to 0-indexed

        let midiBytes: [UInt8]
        switch message.type {
        case .noteOn:
            midiBytes = [
                0x90 | channel,
                UInt8(message.data1),
                UInt8(message.data2)
            ]
        case .noteOff:
            midiBytes = [
                0x80 | channel,
                UInt8(message.data1),
                UInt8(message.data2)
            ]
        case .controlChange:
            midiBytes = [
                0xB0 | channel,
                UInt8(message.data1),
                UInt8(message.data2)
            ]
        case .programChange:
            midiBytes = [
                0xC0 | channel,
                UInt8(message.data1)
            ]
        }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, midiBytes.count, midiBytes)

        let status = MIDISend(outputPort, destination, &packetList)
        if status != noErr {
            print("MIDIEngine: Failed to send MIDI message: \(status)")
        }
    }

    /// Send tap tempo to external device (e.g., Helix) via CC messages
    /// Sends multiple taps at the correct interval for Helix to average
    func sendTapTempo(bpm: Int) {
        guard isExternalTempoSyncEnabled else { return }
        guard let destination = selectedDestinationEndpoint else { return }
        guard outputPort != 0 else { return }

        let channel = UInt8(externalMIDIChannel - 1)
        let ccNumber = UInt8(tapTempoCC)
        let midiBytes: [UInt8] = [0xB0 | channel, ccNumber, 127]

        // Calculate interval in host time units for precise scheduling
        let intervalSeconds = 60.0 / Double(bpm)
        let intervalHostTime = secondsToHostTime(intervalSeconds)
        let now = mach_absolute_time()

        // Schedule 8 taps for better averaging on Helix
        let numTaps = 8

        // Use heap buffer for packets
        let bufferSize = 1024
        let packetListPtr = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4)
            .assumingMemoryBound(to: MIDIPacketList.self)
        defer { packetListPtr.deallocate() }

        var packet = MIDIPacketListInit(packetListPtr)

        for i in 0..<numTaps {
            let timestamp = now + intervalHostTime * UInt64(i)
            packet = MIDIPacketListAdd(packetListPtr, bufferSize, packet, timestamp, midiBytes.count, midiBytes)
        }

        MIDISend(outputPort, destination, packetListPtr)
    }

    /// Convert seconds to host time units (mach_absolute_time)
    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = seconds * 1_000_000_000
        return UInt64(nanoseconds * Double(timebaseInfo.denom) / Double(timebaseInfo.numer))
    }

    // MARK: - MIDI Event Processing
    
    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>, sourceName: String?) {
        let numPackets = Int(eventList.pointee.numPackets)
        guard numPackets > 0 else { return }

        // Use unsafeBitCast to get a pointer to the first packet in the original memory
        // This avoids copying the variable-length packet data
        var packet = UnsafeRawPointer(eventList)
            .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIEventPacket.self)

        for _ in 0..<numPackets {
            handleMIDIEventPacket(packet.pointee, sourceName: sourceName)
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
    }
    
    private func handleMIDIEventPacket(_ packet: MIDIEventPacket, sourceName: String?) {
        // Extract MIDI bytes from the Universal MIDI Packet
        let words = [packet.words.0, packet.words.1, packet.words.2, packet.words.3]
        
        // For MIDI 1.0, the data is in the first word
        let word = words[0]
        
        // Extract channel voice message
        let status = UInt8((word >> 16) & 0xFF)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)
        
        let messageType = status & 0xF0
        let channel = status & 0x0F
        
        DispatchQueue.main.async { [weak self] in
            self?.lastActivity = Date()
        }
        
        switch messageType {
        case 0x90: // Note On
            if data2 > 0 {
                processNoteOn(note: data1, velocity: data2, channel: channel, sourceName: sourceName)
            } else {
                processNoteOff(note: data1, channel: channel, sourceName: sourceName)
            }
            
        case 0x80: // Note Off
            processNoteOff(note: data1, channel: channel, sourceName: sourceName)
            
        case 0xB0: // Control Change
            processCC(cc: data1, value: data2, channel: channel, sourceName: sourceName)
            
        case 0xE0: // Pitch Bend
            processPitchBend(lsb: data1, msb: data2, channel: channel, sourceName: sourceName)
            
        default:
            break
        }
    }
    
    // MARK: - Note Processing
    
    /// Check if a channel strip should receive MIDI from the given source and channel
    private func channelAcceptsMIDI(_ strip: ChannelStrip, sourceName: String?, midiChannel: Int) -> Bool {
        // "__none__" means explicitly disabled - don't accept any MIDI
        if strip.midiSourceName == "__none__" {
            return false
        }

        // Check MIDI channel (0 = omni/all channels)
        let channelMatches = strip.midiChannel == 0 || strip.midiChannel == midiChannel

        // Check MIDI source (nil = any source)
        let sourceMatches = strip.midiSourceName == nil || strip.midiSourceName == sourceName

        return channelMatches && sourceMatches
    }
    
    private func processNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?) {
        let midiChannel = Int(channel) + 1  // Convert to 1-based

        // MIDI Learn mode - intercept note and call callback
        if isLearningMode {
            DispatchQueue.main.async { [weak self] in
                self?.onNoteLearn?(Int(note), midiChannel, sourceName)
            }
            return
        }

        // Song trigger callback (checked before instrument routing)
        DispatchQueue.main.async { [weak self] in
            self?.onSongTrigger?(Int(note), midiChannel, sourceName)
        }

        guard let audioEngine = audioEngine else { return }

        // Check if this is from the ChordPad controller
        // Requires a specific source (no "any" source allowed)
        guard let chordPadSource = chordPadSourceName else {
            // No ChordPad configured, route to normal channels
            routeToInstrumentChannels(note: note, velocity: velocity, channel: channel, sourceName: sourceName, audioEngine: audioEngine)
            return
        }

        if chordPadSource == sourceName {
            // This is from the ChordPad controller - check if it matches chord or single note channel

            // Check for single note zone (secondary zone) first
            let singleNoteChannelMatches = singleNoteZoneChannel == 0 || midiChannel == singleNoteZoneChannel
            if singleNoteChannelMatches && chordMapping.isSecondaryZoneNote(note) {
                processSecondaryZoneNote(note: note, velocity: velocity, channel: channel, sourceName: sourceName)
                return
            }

            // Check for chord zone
            let chordChannelMatches = chordZoneChannel == 0 || midiChannel == chordZoneChannel
            if chordChannelMatches && chordMapping.buttonMap[Int(note)] != nil {
                processChordTrigger(note: note, velocity: velocity, channel: channel, sourceName: sourceName)
                return
            }

            // Note is from ChordPad but not mapped - don't pass through
            return
        }

        // Not from ChordPad, route to normal instrument channels
        routeToInstrumentChannels(note: note, velocity: velocity, channel: channel, sourceName: sourceName, audioEngine: audioEngine)
    }

    /// Route a note to instrument channels based on MIDI source/channel filtering
    private func routeToInstrumentChannels(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?, audioEngine: AudioEngine) {
        let midiChannel = Int(channel) + 1

        // Find target channel(s) that accept this source + channel
        let targetChannels = audioEngine.channelStrips.filter { strip in
            channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
        }

        // Create key for tracking this note (using stable string key, not hash)
        let sourceKey = noteTrackingKey(sourceName: sourceName, channel: channel, note: note)

        // Initialize mapping for this note if needed
        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        for targetChannel in targetChannels {
            let processedNotes: [UInt8]

            if targetChannel.scaleFilterEnabled && isScaleFilterEnabled {
                processedNotes = applyScaleFilter(note: note)
            } else {
                processedNotes = [note]
            }

            // Apply octave transpose (each octave = 12 semitones)
            let transposeSemitones = targetChannel.octaveTranspose * 12
            let transposedNotes = processedNotes.map { note in
                UInt8(clamping: Int(note) + transposeSemitones)
            }

            // Store which notes and channels were actually sent to this specific channel
            let noteChannelPairs = transposedNotes.map { (note: $0, channel: channel) }
            activeNotes[sourceKey]?[targetChannel.id] = noteChannelPairs

            // Send to instrument with reference counting
            // This allows multiple inputs to map to the same output note (e.g., Bb and B both -> B)
            // Always send Note-On (for retrigger/arp behavior), increment ref count
            for transposedNote in transposedNotes {
                let key = outputNoteKey(channelId: targetChannel.id, note: transposedNote, midiChannel: channel)
                outputNoteRefCount[key, default: 0] += 1
                // Pass through the MIDI channel for MPE support
                targetChannel.sendMIDI(noteOn: transposedNote, velocity: velocity, channel: channel)
            }
        }

        let src = sourceName ?? "?"
        updateLastMessage("\(src): Note \(note) vel \(velocity) ch \(channel + 1)")
    }
    
    private func processNoteOff(note: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }

        let sourceKey = noteTrackingKey(sourceName: sourceName, channel: channel, note: note)

        // Look up which notes were actually sent to each channel for this input note
        if let channelMappings = activeNotes[sourceKey] {
            for (channelId, noteChannelPairs) in channelMappings {
                // Find the channel strip by ID
                if let targetChannel = audioEngine.channelStrips.first(where: { $0.id == channelId }) {
                    for pair in noteChannelPairs {
                        // Decrement reference count - only send Note-Off when no inputs are holding this note
                        let key = outputNoteKey(channelId: channelId, note: pair.note, midiChannel: pair.channel)
                        let currentCount = outputNoteRefCount[key, default: 0]
                        if currentCount <= 1 {
                            // Last input holding this note - send Note-Off on the same MIDI channel
                            outputNoteRefCount.removeValue(forKey: key)
                            targetChannel.sendMIDI(noteOff: pair.note, channel: pair.channel)
                        } else {
                            // Other inputs still holding this note - just decrement
                            outputNoteRefCount[key] = currentCount - 1
                        }
                    }
                }
            }
            activeNotes.removeValue(forKey: sourceKey)
        }
    }
    
    private func processCC(cc: UInt8, value: UInt8, channel: UInt8, sourceName: String?) {
        let midiChannel = Int(channel) + 1

        // CC Learn mode - intercept CC and call callback
        if isCCLearningMode {
            DispatchQueue.main.async { [weak self] in
                self?.onCCLearn?(Int(cc), midiChannel, sourceName)
            }
            return
        }

        // Fader control callback (for mapped CC controls)
        DispatchQueue.main.async { [weak self] in
            self?.onFaderControl?(Int(cc), Int(value), midiChannel, sourceName)
        }

        guard let audioEngine = audioEngine else { return }
        
        // Helper to check if channel matches (0 = any)
        func channelMatches(_ requiredChannel: Int) -> Bool {
            requiredChannel == 0 || midiChannel == requiredChannel
        }
        
        // Check dynamic expression axes first
        for axis in expressionAxes where axis.enabled {
            // Determine source to match (axis-specific or global)
            let axisSource = axis.sourceName ?? expressionSourceName
            guard let requiredSource = axisSource,
                  sourceName == requiredSource,
                  Int(cc) == axis.inputCC,
                  channelMatches(axis.inputChannel) else {
                continue
            }
            
            // Apply scale and invert
            var scaledValue = Int(Double(value) * axis.scale)
            if axis.invert {
                scaledValue = 127 - scaledValue
            }
            
            for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                if axis.outputAsPitchBend {
                    // Convert to pitch bend from center
                    let maxBend = Int(8191.0 * axis.scale)
                    let pitchBendValue: Int
                    if axis.pitchBendDown {
                        pitchBendValue = 8192 - (scaledValue * maxBend / 127)
                    } else {
                        pitchBendValue = 8192 + (scaledValue * maxBend / 127)
                    }
                    let lsb = UInt8(max(0, min(16383, pitchBendValue)) & 0x7F)
                    let msb = UInt8((max(0, min(16383, pitchBendValue)) >> 7) & 0x7F)
                    strip.sendMIDI(pitchBend: lsb, msb: msb)
                } else {
                    strip.sendMIDI(controlChange: UInt8(axis.outputCC), value: UInt8(max(0, min(127, scaledValue))))
                }
            }
            
            let src = sourceName ?? "?"
            updateLastMessage("\(src): \(axis.name) = \(scaledValue)")
            return
        }
        
        // Check for legacy global expression routing (axis 1)
        if globalExpressionEnabled,
           let expressionSource = globalExpressionSourceName,
           sourceName == expressionSource,
           Int(cc) == globalExpressionInputCC,
           channelMatches(globalExpressionInputChannel) {
            let outputCC = UInt8(globalExpressionOutputCC)
            
            // If ramping is enabled, set target and let timer handle output
            if globalExpressionRampTime > 0 {
                axis1TargetValue = Double(value)
            } else {
                // Immediate output
                for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                    strip.sendMIDI(controlChange: outputCC, value: value)
                }
            }
            let src = sourceName ?? "?"
            updateLastMessage("\(src): Global CC\(cc)→CC\(outputCC) = \(value)")
            return
        }
        
        // Check for global expression routing (axis 2)
        if globalExpression2Enabled,
           let expressionSource = globalExpressionSourceName,
           sourceName == expressionSource,
           Int(cc) == globalExpression2InputCC,
           channelMatches(globalExpression2InputChannel) {
            let outputCC = UInt8(globalExpression2OutputCC)
            
            // If ramping is enabled, set target and let timer handle output
            if globalExpression2RampTime > 0 {
                axis2TargetValue = Double(value)
            } else {
                // Immediate output
                let outputValue = globalExpression2Invert ? (127 - value) : value
                for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                    strip.sendMIDI(controlChange: outputCC, value: outputValue)
                }
            }
            let src = sourceName ?? "?"
            let invertLabel = globalExpression2Invert ? "~" : ""
            updateLastMessage("\(src): Global CC\(cc)→\(invertLabel)CC\(outputCC) = \(value)")
            return
        }
        
        // Check for global expression routing (axis 3 - can output as pitch bend)
        if globalExpression3Enabled,
           let expressionSource = globalExpressionSourceName,
           sourceName == expressionSource,
           Int(cc) == globalExpression3InputCC,
           channelMatches(globalExpression3InputChannel) {
            // Apply scale to reduce range (for subtle vibrato)
            let scaledValue = Int(Double(value) * globalExpression3Scale)
            
            for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                if globalExpression3OutputPitchBend {
                    // Convert CC value (0-127) to pitch bend from center
                    // Scale reduces the range: 1.0 = full ±8192, 0.1 = subtle ±819
                    let maxBend = Int(8191.0 * globalExpression3Scale)
                    let pitchBendValue: Int
                    if globalExpression3PitchBendDown {
                        // Down from center: value 0 = center (8192), value 127 = min
                        pitchBendValue = 8192 - (scaledValue * maxBend / 127)
                    } else {
                        // Up from center: value 0 = center (8192), value 127 = max
                        pitchBendValue = 8192 + (scaledValue * maxBend / 127)
                    }
                    let lsb = UInt8(max(0, min(16383, pitchBendValue)) & 0x7F)
                    let msb = UInt8((max(0, min(16383, pitchBendValue)) >> 7) & 0x7F)
                    strip.sendMIDI(pitchBend: lsb, msb: msb)
                } else {
                    strip.sendMIDI(controlChange: UInt8(globalExpression3OutputCC), value: UInt8(scaledValue))
                }
            }
            let src = sourceName ?? "?"
            let scalePercent = Int(globalExpression3Scale * 100)
            let outputLabel = globalExpression3OutputPitchBend ? (globalExpression3PitchBendDown ? "PB↓" : "PB↑") : "CC\(globalExpression3OutputCC)"
            updateLastMessage("\(src): CC\(cc)→\(outputLabel)@\(scalePercent)% = \(scaledValue)")
            return
        }
        
        // Check for global expression routing (axis 4 - can output as pitch bend)
        if globalExpression4Enabled,
           let expressionSource = globalExpressionSourceName,
           sourceName == expressionSource,
           Int(cc) == globalExpression4InputCC,
           channelMatches(globalExpression4InputChannel) {
            // Apply scale to reduce range
            let scaledValue = Int(Double(value) * globalExpression4Scale)
            
            for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
                if globalExpression4OutputPitchBend {
                    // Convert CC value (0-127) to pitch bend from center
                    let maxBend = Int(8191.0 * globalExpression4Scale)
                    let pitchBendValue: Int
                    if globalExpression4PitchBendDown {
                        pitchBendValue = 8192 - (scaledValue * maxBend / 127)
                    } else {
                        pitchBendValue = 8192 + (scaledValue * maxBend / 127)
                    }
                    let lsb = UInt8(max(0, min(16383, pitchBendValue)) & 0x7F)
                    let msb = UInt8((max(0, min(16383, pitchBendValue)) >> 7) & 0x7F)
                    strip.sendMIDI(pitchBend: lsb, msb: msb)
                } else {
                    strip.sendMIDI(controlChange: UInt8(globalExpression4OutputCC), value: UInt8(scaledValue))
                }
            }
            let src = sourceName ?? "?"
            let scalePercent = Int(globalExpression4Scale * 100)
            let outputLabel = globalExpression4OutputPitchBend ? (globalExpression4PitchBendDown ? "PB↓" : "PB↑") : "CC\(globalExpression4OutputCC)"
            updateLastMessage("\(src): CC\(cc)→\(outputLabel)@\(scalePercent)% = \(scaledValue)")
            return
        }

        let targetChannels = audioEngine.channelStrips.filter { strip in
            channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
        }

        for targetChannel in targetChannels {
            targetChannel.sendMIDI(controlChange: cc, value: value)
        }

        let src = sourceName ?? "?"
        updateLastMessage("\(src): CC \(cc) = \(value) ch \(channel + 1)")
    }
    
    private func processPitchBend(lsb: UInt8, msb: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else {
            print("⚠️ PB: No audioEngine!")
            return
        }
        
        let value = (Int(msb) << 7) | Int(lsb)
        print("🎹 PB IN: ch=\(channel + 1) val=\(value) src=\(sourceName ?? "?")")
        
        // MPE/Multi-channel sends notes on channels 2-16, with per-note pitch bend on those channels
        // The synth handles the per-channel routing internally, so we just need to forward
        // the message with the original channel intact
        let targetChannels = audioEngine.channelStrips.filter { strip in
            // Skip disabled channels
            if strip.midiSourceName == "__none__" {
                return false
            }
            // Must have an instrument loaded
            guard strip.isInstrumentLoaded else {
                return false
            }
            // Match by source (nil = any source)
            let stripSource = strip.midiSourceName
            let sourceMatches = stripSource == nil || stripSource == sourceName
            return sourceMatches
        }
        
        print("🎹 PB: \(targetChannels.count) targets, forceToChannel1=\(forcePitchBendToChannel1)")
        
        // Determine output channel: force to channel 1 (0-indexed = 0) for non-MPE synths
        let outputChannel: UInt8 = forcePitchBendToChannel1 ? 0 : channel
        
        for targetChannel in targetChannels {
            print("🎹 PB OUT: strip[\(targetChannel.index)] src=\(targetChannel.midiSourceName ?? "any") outCh=\(outputChannel + 1)")
            targetChannel.sendMIDI(pitchBend: lsb, msb: msb, channel: outputChannel)
        }
        
        let src = sourceName ?? "?"
        updateLastMessage("\(src): PB \(value) ch \(channel + 1)")
    }
    
    // MARK: - Scale Filtering
    
    private func applyScaleFilter(note: UInt8) -> [UInt8] {
        switch filterMode {
        case .block:
            if ScaleEngine.isInScale(note: note, root: currentRootNote, scale: currentScaleType) {
                return [note]
            }
            return []
            
        case .snap:
            let snapped = ScaleEngine.snapToScale(note: note, root: currentRootNote, scale: currentScaleType)
            return [snapped]
        }
    }
    
    // MARK: - Secondary Zone Processing (Split Controller)

    /// Process a note from the ChordPad's secondary zone
    /// These notes play scale degree notes on all Single Note Target channels
    private func processSecondaryZoneNote(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }

        // Get the scale degree for this input note
        guard let degree = chordMapping.secondaryDegree(note) else { return }

        // Find all Single Note Target channels
        let targetChannels = audioEngine.channelStrips.filter { $0.isSingleNoteTarget }
        guard !targetChannels.isEmpty else { return }

        // Calculate the actual MIDI note from scale degree
        let outputNote = ScaleEngine.noteForDegree(
            degree,
            root: currentRootNote,
            scale: currentScaleType,
            octave: chordMapping.secondaryBaseOctave
        )

        // Track notes and send to all targets
        let sourceKey = noteTrackingKey(sourceName: sourceName, channel: channel, note: note)

        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        for targetChannel in targetChannels {
            // Apply octave transpose (each octave = 12 semitones)
            let transposeSemitones = targetChannel.octaveTranspose * 12
            let transposedNote = UInt8(clamping: Int(outputNote) + transposeSemitones)

            // ChordPad routing uses channel 0 (non-MPE)
            activeNotes[sourceKey]?[targetChannel.id] = [(note: transposedNote, channel: 0)]
            targetChannel.sendMIDI(noteOn: transposedNote, velocity: velocity, channel: 0)
        }

        let degreeNames = ["1", "2", "3", "4", "5", "6", "7"]
        updateLastMessage("Split: Deg \(degreeNames[degree - 1]) → Note \(outputNote)")
    }

    // MARK: - Chord Triggering

    private func processChordTrigger(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }

        // Get chord notes from engine
        guard let chordNotes = ChordEngine.processChordTrigger(
            inputNote: note,
            mapping: chordMapping,
            rootNote: currentRootNote,
            scaleType: currentScaleType,
            baseOctave: chordMapping.baseOctave
        ) else {
            return
        }

        // Find the ChordPad target channels
        let targetChannels = audioEngine.channelStrips.filter { $0.isChordPadTarget }

        // Create key for tracking this note
        let sourceKey = noteTrackingKey(sourceName: sourceName, channel: channel, note: note)

        // Initialize mapping for this note if needed
        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        for targetChannel in targetChannels {
            // Apply octave transpose (each octave = 12 semitones)
            let transposeSemitones = targetChannel.octaveTranspose * 12
            let transposedChordNotes = chordNotes.map { note in
                UInt8(clamping: Int(note) + transposeSemitones)
            }

            // Store which chord notes were sent to this channel (ChordPad uses channel 0)
            let noteChannelPairs = transposedChordNotes.map { (note: $0, channel: UInt8(0)) }
            activeNotes[sourceKey]?[targetChannel.id] = noteChannelPairs

            for transposedNote in transposedChordNotes {
                targetChannel.sendMIDI(noteOn: transposedNote, velocity: velocity, channel: 0)
            }
        }

        updateLastMessage("Chord: \(chordNotes.map { String($0) }.joined(separator: ","))")
    }
    
    // MARK: - Song/Preset Changes
    
    /// Update scale settings when song changes
    func applySongSettings(_ song: Song) {
        currentRootNote = song.rootNote
        currentScaleType = song.scaleType
        filterMode = song.filterMode
    }
    
    // MARK: - Panic / All Notes Off
    
    /// Send All Notes Off (CC 123) to all instruments - use to stop stuck notes
    func panicAllNotesOff() {
        guard let audioEngine = audioEngine else { return }
        
        // Clear all tracking state
        activeNotes.removeAll()
        outputNoteRefCount.removeAll()
        
        // Send All Notes Off (CC 123 value 0) to all channels on all instruments
        for strip in audioEngine.channelStrips where strip.isInstrumentLoaded {
            // Send to all 16 MIDI channels for thoroughness
            for ch: UInt8 in 0..<16 {
                strip.sendMIDI(controlChange: 123, value: 0, channel: ch)
                // Also send All Sound Off (CC 120) for synths that need it
                strip.sendMIDI(controlChange: 120, value: 0, channel: ch)
            }
        }
        
        updateLastMessage("PANIC: All Notes Off")
    }
    
    // MARK: - Helpers
    
    private func updateLastMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastReceivedMessage = message
        }
    }
}

// MARK: - MIDI Source Info

struct MIDISourceInfo: Identifiable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String
    var isConnected: Bool
}

// MARK: - MIDI Destination Info

struct MIDIDestinationInfo: Identifiable, Equatable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String

    static func == (lhs: MIDIDestinationInfo, rhs: MIDIDestinationInfo) -> Bool {
        lhs.endpoint == rhs.endpoint
    }
}
