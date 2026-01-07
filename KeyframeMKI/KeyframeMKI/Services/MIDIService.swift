import Foundation
import CoreMIDI

/// Service for creating a virtual MIDI source and sending MIDI messages to AUM
/// Also listens for incoming MIDI to allow external song selection
final class MIDIService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MIDIService()
    
    // MARK: - Published Properties
    
    @Published private(set) var isInitialized = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSentMessage: String?
    @Published private(set) var lastReceivedMessage: String?
    @Published private(set) var isListeningForInput = false
    
    // MARK: - Callbacks
    
    /// Called when a Program Change is received for song selection
    var onSongSelect: ((Int) -> Void)?
    
    /// Called when a Note On is received for song selection (alternative to PC)
    var onSongSelectNote: ((Int) -> Void)?
    
    /// Called when any Note On is received (for MIDI Learn mode)
    /// Parameters: (note, channel, velocity)
    var onNoteLearn: ((Int, Int, Int) -> Void)?
    
    /// When true, all incoming notes trigger onNoteLearn regardless of channel
    @Published var isLearningMode = false
    
    // MARK: - Private Properties
    
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0
    private var virtualSource: MIDIEndpointRef = 0
    private var virtualDestination: MIDIEndpointRef = 0
    
    private let clientName = "Keyframe MK I"
    private let sourceName = "Keyframe MK I"
    private let destinationName = "Keyframe Song Select"
    
    /// MIDI channel to listen for song selection (0-indexed, default channel 16)
    var songSelectChannel: UInt8 = MIDIConstants.songSelectChannel
    
    /// Enable/disable listening for song selection via notes
    var enableNoteBasedSelection = true
    
    /// First note for song selection (songs mapped sequentially from this note)
    var songSelectBaseNote: UInt8 = 0  // C-1
    
    // MARK: - Initialization
    
    private init() {
        setupMIDI()
    }
    
    deinit {
        teardownMIDI()
    }
    
    // MARK: - MIDI Setup
    
    private func setupMIDI() {
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock(clientName as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        
        guard status == noErr else {
            lastError = "Failed to create MIDI client: \(status)"
            return
        }
        
        // Create virtual source (this is what AUM will see for outgoing messages)
        status = MIDISourceCreate(midiClient, sourceName as CFString, &virtualSource)
        
        guard status == noErr else {
            lastError = "Failed to create virtual MIDI source: \(status)"
            return
        }
        
        // Create virtual destination (this receives incoming MIDI for song selection)
        status = MIDIDestinationCreateWithBlock(
            midiClient,
            destinationName as CFString,
            &virtualDestination
        ) { [weak self] packetList, srcConnRefCon in
            self?.handleIncomingMIDI(packetList)
        }
        
        if status != noErr {
            // Log error but continue - outgoing MIDI still works
            print("Warning: Failed to create virtual MIDI destination: \(status)")
            // Don't set lastError here since outgoing MIDI is still functional
        }
        
        isInitialized = true
        isListeningForInput = virtualDestination != 0
        print("MIDI Service initialized successfully")
    }
    
    private func teardownMIDI() {
        if virtualDestination != 0 {
            MIDIEndpointDispose(virtualDestination)
        }
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
    
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        let messageID = notification.pointee.messageID
        print("MIDI Notification: \(messageID)")
    }
    
    // MARK: - Incoming MIDI Handling
    
    private func handleIncomingMIDI(_ packetListPtr: UnsafePointer<MIDIPacketList>) {
        let packetList = packetListPtr.pointee
        var packet = packetList.packet
        
        for _ in 0..<packetList.numPackets {
            let bytes = Mirror(reflecting: packet.data).children.map { $0.value as! UInt8 }
            let length = Int(packet.length)
            
            if length >= 2 {
                let statusByte = bytes[0]
                let channel = statusByte & 0x0F
                let messageType = statusByte & 0xF0
                
                // MIDI Learn mode - capture any note on any channel
                if isLearningMode && messageType == MIDIConstants.noteOnStatus && length >= 3 {
                    let note = Int(bytes[1])
                    let velocity = Int(bytes[2])
                    if velocity > 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.lastReceivedMessage = "Learn: Note \(note) (Ch \(channel + 1))"
                            self?.onNoteLearn?(note, Int(channel), velocity)
                        }
                    }
                    // Don't process other handlers when learning
                    packet = MIDIPacketNext(&packet).pointee
                    continue
                }
                
                // Check if this is on our song select channel
                if channel == songSelectChannel {
                    switch messageType {
                    case MIDIConstants.programChangeStatus:
                        // Program Change - select song by program number
                        let program = Int(bytes[1])
                        DispatchQueue.main.async { [weak self] in
                            self?.lastReceivedMessage = "PC \(program) (Ch \(channel + 1))"
                            self?.onSongSelect?(program)
                        }
                        
                    case MIDIConstants.noteOnStatus where enableNoteBasedSelection && length >= 3:
                        // Note On - select song by note number
                        let note = Int(bytes[1])
                        let velocity = bytes[2]
                        if velocity > 0 {
                            let songIndex = note - Int(songSelectBaseNote)
                            if songIndex >= 0 {
                                DispatchQueue.main.async { [weak self] in
                                    self?.lastReceivedMessage = "Note \(note) vel \(velocity) (Ch \(channel + 1))"
                                    self?.onSongSelectNote?(songIndex)
                                }
                            }
                        }
                        
                    default:
                        break
                    }
                }
            }
            
            packet = MIDIPacketNext(&packet).pointee
        }
    }
    
    // MARK: - Sending MIDI Messages
    
    /// Send a Control Change message
    /// - Parameters:
    ///   - cc: CC number (0-127)
    ///   - value: CC value (0-127)
    ///   - channel: MIDI channel (0-15)
    func sendCC(_ cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        guard isInitialized else {
            lastError = "MIDI not initialized"
            return
        }
        
        let status = MIDIConstants.controlChangeStatus | (channel & 0x0F)
        sendMessage([status, cc, value])
        lastSentMessage = "CC \(cc) = \(value) (Ch \(channel + 1))"
    }
    
    /// Send a Program Change message
    /// - Parameters:
    ///   - program: Program number (0-127)
    ///   - channel: MIDI channel (0-15)
    func sendProgramChange(_ program: UInt8, channel: UInt8 = 0) {
        guard isInitialized else {
            lastError = "MIDI not initialized"
            return
        }
        
        let status = MIDIConstants.programChangeStatus | (channel & 0x0F)
        sendMessage([status, program])
        lastSentMessage = "PC \(program) (Ch \(channel + 1))"
    }
    
    /// Send a Note On message
    /// - Parameters:
    ///   - note: Note number (0-127)
    ///   - velocity: Velocity (0-127)
    ///   - channel: MIDI channel (0-15)
    func sendNoteOn(_ note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard isInitialized else { return }
        
        let status = MIDIConstants.noteOnStatus | (channel & 0x0F)
        sendMessage([status, note, velocity])
    }
    
    /// Send a Note Off message
    /// - Parameters:
    ///   - note: Note number (0-127)
    ///   - channel: MIDI channel (0-15)
    func sendNoteOff(_ note: UInt8, channel: UInt8 = 0) {
        guard isInitialized else { return }
        
        let status = MIDIConstants.noteOffStatus | (channel & 0x0F)
        sendMessage([status, note, 0])
    }
    
    // MARK: - Preset Sending
    
    /// Send all CC messages for a preset
    /// - Parameter preset: The MIDI preset to send
    /// - Parameter useBatch: If true, sends all messages at once. If false, sends with small delays.
    func sendPreset(_ preset: MIDIPreset, useBatch: Bool = true) {
        guard isInitialized else {
            lastError = "MIDI not initialized"
            return
        }
        
        let messages = preset.allCCMessages()
        
        if useBatch {
            // Send all messages in a single packet (faster)
            sendCCBatch(messages)
        } else {
            // Send messages sequentially with delays (more compatible)
            for (channel, cc, value) in messages {
                sendCC(cc, value: value, channel: channel)
                usleep(1000) // 1ms delay
            }
        }
        
        lastSentMessage = "Sent preset: \(messages.count) CC messages"
        print("Sent preset with \(messages.count) CC messages")
    }
    
    /// Send preset for a song (includes BPM if set)
    /// - Parameter song: The song whose preset to send
    func sendPreset(for song: Song) {
        // Send the preset controls
        sendPreset(song.preset)
        
        // Send BPM if configured
        if let bpm = song.bpm {
            sendBPM(bpm, cc: UInt8(song.bpmCC), channel: UInt8(song.bpmChannel - 1))
        }
    }
    
    /// Send BPM as a CC message
    /// - Parameters:
    ///   - bpm: The BPM value (will be clamped to 0-127 for MIDI)
    ///   - cc: CC number to send on
    ///   - channel: MIDI channel (0-15)
    func sendBPM(_ bpm: Int, cc: UInt8 = MIDIConstants.defaultBPMCC, channel: UInt8 = MIDIConstants.defaultBPMChannel) {
        // BPM typically needs to be mapped to 0-127 range
        // Common approach: send BPM directly if <= 127, or scale it
        // For BPMs > 127, we can use MSB/LSB or just clamp
        let midiValue = UInt8(min(127, max(0, bpm)))
        sendCC(cc, value: midiValue, channel: channel)
        lastSentMessage = "BPM \(bpm) → CC \(cc) = \(midiValue) (Ch \(channel + 1))"
    }
    
    // MARK: - Raw MIDI Sending
    
    private func sendMessage(_ bytes: [UInt8]) {
        guard virtualSource != 0 else { return }
        
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)
        
        let status = MIDIReceived(virtualSource, &packetList)
        
        if status != noErr {
            print("Failed to send MIDI message: \(status)")
        }
    }
    
    // MARK: - Batch Message Sending
    
    /// Send multiple CC messages efficiently
    /// - Parameter messages: Array of (channel, cc, value) tuples
    func sendCCBatch(_ messages: [(channel: UInt8, cc: UInt8, value: UInt8)]) {
        guard isInitialized, virtualSource != 0 else { return }
        
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        
        for (channel, cc, value) in messages {
            let status = MIDIConstants.controlChangeStatus | (channel & 0x0F)
            let bytes: [UInt8] = [status, cc, value]
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)
        }
        
        MIDIReceived(virtualSource, &packetList)
    }
    
    // MARK: - Testing
    
    /// Send a test CC message to verify MIDI is working
    func sendTestMessage() {
        sendCC(1, value: 64, channel: 0) // Mod wheel to middle
        lastSentMessage = "Test: CC1 = 64"
    }
}

// MARK: - MIDI Destination Discovery

extension MIDIService {
    /// Get list of available MIDI destinations
    var availableDestinations: [String] {
        var destinations: [String] = []
        let count = MIDIGetNumberOfDestinations()
        
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            if let name = getEndpointName(endpoint) {
                destinations.append(name)
            }
        }
        
        return destinations
    }
    
    /// Get list of available MIDI sources (inputs)
    var availableSources: [String] {
        var sources: [String] = []
        let count = MIDIGetNumberOfSources()
        
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            if let name = getEndpointName(endpoint) {
                sources.append(name)
            }
        }
        
        return sources
    }
    
    private func getEndpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        
        if status == noErr, let name = name {
            return name.takeRetainedValue() as String
        }
        return nil
    }
}
