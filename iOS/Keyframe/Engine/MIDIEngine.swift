import CoreMIDI
import Foundation


/// Integrated MIDI Engine with built-in scale filtering and chord generation
/// Replaces the need for a separate Scale Filter AUv3
final class MIDIEngine: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MIDIEngine()
    
    // MARK: - Published Properties
    
    @Published private(set) var isInitialized = false
    @Published private(set) var connectedSources: [MIDISourceInfo] = []
    @Published private(set) var lastReceivedMessage: String?
    @Published private(set) var lastActivity: Date?
    
    // MARK: - Scale/Chord Settings

    @Published var currentRootNote: Int = 0  // C
    @Published var currentScaleType: ScaleType = .major
    @Published var filterMode: FilterMode = .snap
    @Published var isScaleFilterEnabled = true

    // MARK: - ChordPad Settings (persisted)

    @Published var chordPadChannel: Int = 10 {  // 1-16
        didSet { saveChordPadSettings() }
    }
    @Published var chordPadSourceName: String? = nil {  // nil = disabled
        didSet { saveChordPadSettings() }
    }
    var chordMapping: ChordMapping = .defaultMapping {
        didSet { saveChordPadSettings() }
    }

    // MARK: - Persistence Keys

    private let chordPadChannelKey = "chordPadChannel"
    private let chordPadSourceNameKey = "chordPadSourceName"
    private let chordMappingKey = "chordMapping"

    // MARK: - MIDI Learn Mode

    @Published var isLearningMode = false
    @Published var isCCLearningMode = false
    var onNoteLearn: ((Int, Int, String?) -> Void)?  // (note, channel, sourceName)
    var onCCLearn: ((Int, Int, String?) -> Void)?    // (cc, channel, sourceName)

    // MARK: - Control Callbacks

    var onSongTrigger: ((Int, Int, String?) -> Void)?       // (note, channel, sourceName) - for triggering songs
    var onFaderControl: ((Int, Int, Int, String?) -> Void)? // (cc, value, channel, sourceName) - for fader control
    
    // MARK: - CoreMIDI

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0

    // MARK: - MIDI Output Settings

    @Published private(set) var availableDestinations: [MIDIDestinationInfo] = []
    @Published var selectedDestinationEndpoint: MIDIEndpointRef? = nil {
        didSet {
            // Only save if not currently restoring (to avoid erasing saved name when device not yet discovered)
            if !isRestoringDestination {
                saveOutputSettings()
            }
        }
    }
    private var isRestoringDestination = false
    private var savedDestinationName: String?  // Keep saved name even if device not available yet
    @Published var externalMIDIChannel: Int = 1 {  // 1-16
        didSet { saveOutputSettings() }
    }
    @Published var isNetworkSessionEnabled: Bool = false {
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

    @Published var isExternalTempoSyncEnabled: Bool = false {
        didSet { saveOutputSettings() }
    }
    @Published var tapTempoCC: Int = 64 {  // Helix default tap tempo CC
        didSet { saveOutputSettings() }
    }

    /// Current session BPM for display purposes (default 90, updated when presets with BPM are selected)
    @Published var currentBPM: Int = 90

    // Persistence keys for output settings
    private let selectedDestinationKey = "midiOutputDestination"
    private let externalMIDIChannelKey = "externalMIDIChannel"
    private let networkSessionEnabledKey = "midiNetworkSessionEnabled"
    private let externalTempoSyncEnabledKey = "externalTempoSyncEnabled"
    private let tapTempoCCKey = "tapTempoCC"
    
    // Track active notes for proper note-off handling
    // Key: sourceHash ^ channel ^ note, Value: Dictionary of channelStripId -> processed notes sent
    private var activeNotes: [Int: [UUID: [UInt8]]] = [:]
    
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
    }

    // MARK: - ChordPad Persistence

    private func loadChordPadSettings() {
        let defaults = UserDefaults.standard

        // Load channel
        if defaults.object(forKey: chordPadChannelKey) != nil {
            chordPadChannel = defaults.integer(forKey: chordPadChannelKey)
        }

        // Load source name
        chordPadSourceName = defaults.string(forKey: chordPadSourceNameKey)

        // Load chord mapping
        if let data = defaults.data(forKey: chordMappingKey),
           let mapping = try? JSONDecoder().decode(ChordMapping.self, from: data) {
            chordMapping = mapping
        }

        print("MIDIEngine: Loaded ChordPad settings - source: \(chordPadSourceName ?? "none"), channel: \(chordPadChannel), mappings: \(chordMapping.buttonMap.count)")
    }

    private func saveChordPadSettings() {
        let defaults = UserDefaults.standard

        defaults.set(chordPadChannel, forKey: chordPadChannelKey)
        defaults.set(chordPadSourceName, forKey: chordPadSourceNameKey)

        if let data = try? JSONEncoder().encode(chordMapping) {
            defaults.set(data, forKey: chordMappingKey)
        }
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

        print("MIDIEngine: Loaded output settings - channel: \(externalMIDIChannel), network: \(isNetworkSessionEnabled), tempoSync: \(isExternalTempoSyncEnabled)")
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
            print("MIDIEngine: Restored destination '\(savedName)'")
        } else {
            print("MIDIEngine: Saved destination '\(savedName)' not found yet (will retry on refresh)")
        }
        isRestoringDestination = false
    }

    deinit {
        teardownMIDI()
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

        print("MIDIEngine: Initialized successfully")
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
                print("MIDIEngine: Connected to '\(name)'")
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.connectedSources = sources
            print("MIDIEngine: Connected to \(sources.count) sources")
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
            print("MIDIEngine: Found \(destinations.count) MIDI destinations")
        }
    }

    /// Configure Network MIDI session
    private func configureNetworkSession() {
        let networkSession = MIDINetworkSession.default()

        networkSession.isEnabled = isNetworkSessionEnabled
        networkSession.connectionPolicy = isNetworkSessionEnabled ? .anyone : .noOne

        if isNetworkSessionEnabled {
            print("MIDIEngine: Network MIDI session '\(networkSession.localName)' enabled")
        } else {
            print("MIDIEngine: Network MIDI session disabled")
        }

        // Refresh destinations to include/exclude network endpoints
        refreshDestinations()
    }

    // MARK: - External MIDI Output

    /// Send external MIDI messages to the configured destination
    /// These messages are output only and do not affect internal app state
    func sendExternalMIDIMessages(_ messages: [ExternalMIDIMessage]) {
        guard let destination = selectedDestinationEndpoint else {
            print("MIDIEngine: No MIDI output destination configured")
            return
        }

        guard outputPort != 0 else {
            print("MIDIEngine: Output port not initialized")
            return
        }

        for message in messages {
            sendMIDIMessage(message, to: destination)
        }

        print("MIDIEngine: Sent \(messages.count) external MIDI message(s)")
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
        print("MIDIEngine: Sent tap tempo at \(bpm) BPM")
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

        // Check if this is from the ChordPad (chord trigger controller)
        // Requires BOTH a specific source AND matching channel (no "any" source allowed)
        // ALL notes from ChordPad are captured - mapped ones trigger chords, unmapped ones are ignored
        if let chordPadSource = chordPadSourceName,
           chordPadSource == sourceName,
           midiChannel == chordPadChannel {
            // Only process if this note is mapped to a chord degree
            if chordMapping.buttonMap[Int(note)] != nil {
                processChordTrigger(note: note, velocity: velocity, channel: channel, sourceName: sourceName)
            }
            // Always return - don't let ChordPad notes fall through to instruments
            return
        }

        // Find target channel(s) that accept this source + channel
        let targetChannels = audioEngine.channelStrips.filter { strip in
            channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
        }

        // Create key for tracking this note
        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

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

            // Store which notes were actually sent to this specific channel
            activeNotes[sourceKey]?[targetChannel.id] = processedNotes

            // Send to instrument
            for processedNote in processedNotes {
                targetChannel.sendMIDI(noteOn: processedNote, velocity: velocity)
            }
        }

        let src = sourceName ?? "?"
        updateLastMessage("\(src): Note \(note) vel \(velocity) ch \(channel + 1)")
    }
    
    private func processNoteOff(note: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }

        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

        // Look up which notes were actually sent to each channel for this input note
        if let channelMappings = activeNotes[sourceKey] {
            for (channelId, processedNotes) in channelMappings {
                // Find the channel strip by ID
                if let targetChannel = audioEngine.channelStrips.first(where: { $0.id == channelId }) {
                    for processedNote in processedNotes {
                        targetChannel.sendMIDI(noteOff: processedNote)
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
        // TODO: Implement pitch bend forwarding
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
        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

        // Initialize mapping for this note if needed
        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        for targetChannel in targetChannels {
            // Store which chord notes were sent to this channel
            activeNotes[sourceKey]?[targetChannel.id] = chordNotes

            for chordNote in chordNotes {
                targetChannel.sendMIDI(noteOn: chordNote, velocity: velocity)
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
        
        print("MIDIEngine: Applied song settings - \(song.keyDisplayName), \(song.filterMode.rawValue)")
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
