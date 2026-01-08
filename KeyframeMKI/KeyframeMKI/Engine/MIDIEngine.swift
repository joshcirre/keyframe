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
    @Published var nm2Channel: Int = 10  // 1-16
    @Published var isScaleFilterEnabled = true
    
    // MARK: - NM2 Chord Mapping
    
    var chordMapping: ChordMapping = .defaultMapping
    
    // MARK: - CoreMIDI
    
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    
    // Track active notes for proper note-off handling
    private var activeNotes: [Int: [(channel: UInt8, notes: [UInt8])]] = [:]  // Source -> active note mappings
    
    // Source endpoint to name mapping
    private var sourceNameMap: [MIDIEndpointRef: String] = [:]
    
    // Current source being processed (set in callback via connection ref)
    private var currentSourceName: String? = nil
    
    // MARK: - Audio Engine Reference
    
    private weak var audioEngine: AudioEngine?
    
    // MARK: - Initialization
    
    private init() {
        setupMIDI()
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
        
        isInitialized = true
        connectToAllSources()
        
        print("MIDIEngine: Initialized successfully")
    }
    
    private func teardownMIDI() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
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
    
    // MARK: - MIDI Event Processing
    
    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>, sourceName: String?) {
        var list = eventList.pointee
        
        withUnsafeMutablePointer(to: &list.packet) { firstPacket in
            var packet = firstPacket
            
            for _ in 0..<list.numPackets {
                handleMIDIEventPacket(packet.pointee, sourceName: sourceName)
                packet = MIDIEventPacketNext(packet)
            }
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
        // Check MIDI channel (0 = omni/all channels)
        let channelMatches = strip.midiChannel == 0 || strip.midiChannel == midiChannel
        
        // Check MIDI source (nil = any source)
        let sourceMatches = strip.midiSourceName == nil || strip.midiSourceName == sourceName
        
        return channelMatches && sourceMatches
    }
    
    private func processNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }
        
        let midiChannel = Int(channel) + 1  // Convert to 1-based
        
        // Check if this is from the NM2 (chord trigger)
        if midiChannel == nm2Channel && chordMapping.buttonMap[Int(note)] != nil {
            processChordTrigger(note: note, velocity: velocity, channel: channel, sourceName: sourceName)
            return
        }
        
        // Find target channel(s) that accept this source + channel
        let targetChannels = audioEngine.channelStrips.filter { strip in
            channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
        }
        
        for targetChannel in targetChannels {
            let processedNotes: [UInt8]
            
            if targetChannel.scaleFilterEnabled && isScaleFilterEnabled {
                processedNotes = applyScaleFilter(note: note)
            } else {
                processedNotes = [note]
            }
            
            // Store mapping for note-off (include source in key)
            let sourceHash = sourceName?.hashValue ?? 0
            let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)
            activeNotes[sourceKey] = [(channel: channel, notes: processedNotes)]
            
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
        let midiChannel = Int(channel) + 1
        
        if let mappings = activeNotes[sourceKey] {
            let targetChannels = audioEngine.channelStrips.filter { strip in
                channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
            }
            
            for mapping in mappings {
                for targetChannel in targetChannels {
                    for processedNote in mapping.notes {
                        targetChannel.sendMIDI(noteOff: processedNote)
                    }
                }
            }
            activeNotes.removeValue(forKey: sourceKey)
        }
    }
    
    private func processCC(cc: UInt8, value: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }
        
        let midiChannel = Int(channel) + 1
        
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
        
        // Find the NM2 chord channel
        let targetChannels = audioEngine.channelStrips.filter { $0.isNM2ChordChannel }
        
        for targetChannel in targetChannels {
            // Store mapping for note-off
            let sourceHash = sourceName?.hashValue ?? 0
            let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)
            activeNotes[sourceKey] = [(channel: channel, notes: chordNotes)]
            
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
