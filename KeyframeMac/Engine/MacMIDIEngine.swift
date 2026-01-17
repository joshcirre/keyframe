import CoreMIDI
import Foundation

/// MIDI Engine for macOS - handles CoreMIDI input/output and Network MIDI
/// Adapted from iOS MIDIEngine
final class MacMIDIEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = MacMIDIEngine()

    // MARK: - Published Properties

    @Published private(set) var isInitialized = false
    @Published private(set) var connectedSources: [MacMIDISourceInfo] = []
    @Published private(set) var lastReceivedMessage: String?
    @Published private(set) var lastActivity: Date?

    // MARK: - Scale/Chord Settings

    @Published var currentRootNote: Int = 0
    @Published var currentScaleType: ScaleType = .major
    @Published var filterMode: FilterMode = .snap
    @Published var isScaleFilterEnabled = true

    // MARK: - ChordPad Settings

    @Published var chordPadChannel: Int = 10 {
        didSet { saveChordPadSettings() }
    }
    @Published var chordPadSourceName: String? = nil {
        didSet { saveChordPadSettings() }
    }
    var chordMapping: ChordMapping = .defaultMapping {
        didSet { saveChordPadSettings() }
    }

    // MARK: - MIDI Learn Mode

    @Published var isLearningMode = false
    @Published var isCCLearningMode = false
    var onNoteLearn: ((Int, Int, String?) -> Void)?
    var onCCLearn: ((Int, Int, String?) -> Void)?

    // MARK: - MIDI CC Mappings

    /// Active CC mappings - loaded from session on startup
    @Published var midiMappings: [MIDICCMapping] = []

    /// When set, the next CC received will be mapped to this target
    @Published var learningTarget: MIDILearnTarget?

    /// Callback when a CC mapping is completed
    var onMappingLearned: ((MIDICCMapping) -> Void)?

    // MARK: - Preset Trigger MIDI Learn

    /// Active preset trigger mappings - loaded from session
    @Published var presetTriggerMappings: [PresetTriggerMapping] = []

    /// When set, the next PC/CC/Note will be mapped to trigger this preset
    @Published var presetTriggerLearnTarget: PresetTriggerLearnTarget?

    /// Callback when preset trigger mapping is learned
    var onPresetTriggerLearned: ((PresetTriggerMapping) -> Void)?

    // MARK: - Control Callbacks

    var onSongTrigger: ((Int, Int, String?) -> Void)?
    var onFaderControl: ((Int, Int, Int, String?) -> Void)?

    // iOS remote control callback - triggered when iOS sends preset change
    var onRemotePresetChange: ((Int) -> Void)?

    // MARK: - CoreMIDI

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0

    // MARK: - MIDI Output Settings

    @Published private(set) var availableDestinations: [MacMIDIDestinationInfo] = []
    @Published var selectedDestinationEndpoint: MIDIEndpointRef? = nil {
        didSet {
            if !isRestoringDestination {
                saveOutputSettings()
            }
        }
    }
    private var isRestoringDestination = false
    private var savedDestinationName: String?

    @Published var externalMIDIChannel: Int = 1 {
        didSet { saveOutputSettings() }
    }

    /// Network MIDI for iOS remote - enabled by default for seamless connection
    @Published var isNetworkSessionEnabled: Bool = true {
        didSet {
            configureNetworkSession()
            saveOutputSettings()
        }
    }

    var networkSessionName: String {
        MIDINetworkSession.default().localName
    }

    // MARK: - External Tempo Sync

    @Published var isExternalTempoSyncEnabled: Bool = false {
        didSet { saveOutputSettings() }
    }
    @Published var tapTempoCC: Int = 64 {
        didSet { saveOutputSettings() }
    }

    @Published var currentBPM: Int = 90

    // MARK: - Helix Integration

    /// Detected Helix device info (nil if not connected)
    @Published private(set) var detectedHelix: MacMIDIDestinationInfo?

    /// Auto-connect to detected Helix
    @Published var autoConnectHelix: Bool = true {
        didSet { saveOutputSettings() }
    }

    // MARK: - External Preset Trigger (MIDI controller → preset change)

    /// Enable external MIDI controller preset selection
    @Published var isExternalPresetTriggerEnabled: Bool = false {
        didSet { saveOutputSettings() }
    }

    /// MIDI channel to listen for preset triggers (1-16, channel 16 reserved for iOS remote)
    @Published var externalPresetTriggerChannel: Int = 1 {
        didSet { saveOutputSettings() }
    }

    /// Optional MIDI source filter for preset triggers (nil = any source)
    @Published var externalPresetTriggerSource: String? = nil {
        didSet { saveOutputSettings() }
    }

    /// Callback when external MIDI controller triggers a preset change
    var onExternalPresetTrigger: ((Int) -> Void)?

    // MARK: - Persistence Keys

    private let chordPadChannelKey = "mac.chordPadChannel"
    private let chordPadSourceNameKey = "mac.chordPadSourceName"
    private let chordMappingKey = "mac.chordMapping"
    private let selectedDestinationKey = "mac.midiOutputDestination"
    private let externalMIDIChannelKey = "mac.externalMIDIChannel"
    private let networkSessionEnabledKey = "mac.midiNetworkSessionEnabled"
    private let externalTempoSyncEnabledKey = "mac.externalTempoSyncEnabled"
    private let tapTempoCCKey = "mac.tapTempoCC"
    private let externalPresetTriggerEnabledKey = "mac.externalPresetTriggerEnabled"
    private let externalPresetTriggerChannelKey = "mac.externalPresetTriggerChannel"
    private let externalPresetTriggerSourceKey = "mac.externalPresetTriggerSource"
    private let autoConnectHelixKey = "mac.autoConnectHelix"

    private var lastSentTempo: Int?
    private var activeNotes: [Int: [UUID: [UInt8]]] = [:]
    private var sourceNameMap: [MIDIEndpointRef: String] = [:]

    // MARK: - Audio Engine Reference

    private weak var audioEngine: MacAudioEngine?
    private weak var sessionStore: MacSessionStore?

    // MARK: - Initialization

    private init() {
        loadChordPadSettings()
        loadOutputSettings()
        setupMIDI()
    }

    deinit {
        teardownMIDI()
    }

    func setAudioEngine(_ engine: MacAudioEngine) {
        self.audioEngine = engine
    }

    func setSessionStore(_ store: MacSessionStore) {
        self.sessionStore = store
    }

    // MARK: - Persistence

    private func loadChordPadSettings() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: chordPadChannelKey) != nil {
            chordPadChannel = defaults.integer(forKey: chordPadChannelKey)
        }

        chordPadSourceName = defaults.string(forKey: chordPadSourceNameKey)

        if let data = defaults.data(forKey: chordMappingKey),
           let mapping = try? JSONDecoder().decode(ChordMapping.self, from: data) {
            chordMapping = mapping
        }
    }

    private func saveChordPadSettings() {
        let defaults = UserDefaults.standard

        defaults.set(chordPadChannel, forKey: chordPadChannelKey)
        defaults.set(chordPadSourceName, forKey: chordPadSourceNameKey)

        if let data = try? JSONEncoder().encode(chordMapping) {
            defaults.set(data, forKey: chordMappingKey)
        }
    }

    private func loadOutputSettings() {
        let defaults = UserDefaults.standard

        // Network MIDI: default to true (enabled) for seamless iOS remote connection
        // Only disable if user explicitly turned it off
        if defaults.object(forKey: networkSessionEnabledKey) != nil {
            isNetworkSessionEnabled = defaults.bool(forKey: networkSessionEnabledKey)
        } else {
            // First launch: auto-enable network MIDI
            isNetworkSessionEnabled = true
        }

        if defaults.object(forKey: externalMIDIChannelKey) != nil {
            externalMIDIChannel = defaults.integer(forKey: externalMIDIChannelKey)
        }

        isExternalTempoSyncEnabled = defaults.bool(forKey: externalTempoSyncEnabledKey)
        if defaults.object(forKey: tapTempoCCKey) != nil {
            tapTempoCC = defaults.integer(forKey: tapTempoCCKey)
        }

        // External preset trigger settings
        isExternalPresetTriggerEnabled = defaults.bool(forKey: externalPresetTriggerEnabledKey)
        if defaults.object(forKey: externalPresetTriggerChannelKey) != nil {
            externalPresetTriggerChannel = defaults.integer(forKey: externalPresetTriggerChannelKey)
        }
        externalPresetTriggerSource = defaults.string(forKey: externalPresetTriggerSourceKey)

        // Helix auto-connect (default true)
        if defaults.object(forKey: autoConnectHelixKey) != nil {
            autoConnectHelix = defaults.bool(forKey: autoConnectHelixKey)
        }

        savedDestinationName = defaults.string(forKey: selectedDestinationKey)
    }

    private func saveOutputSettings() {
        let defaults = UserDefaults.standard

        defaults.set(externalMIDIChannel, forKey: externalMIDIChannelKey)
        defaults.set(isNetworkSessionEnabled, forKey: networkSessionEnabledKey)
        defaults.set(isExternalTempoSyncEnabled, forKey: externalTempoSyncEnabledKey)
        defaults.set(tapTempoCC, forKey: tapTempoCCKey)

        // External preset trigger settings
        defaults.set(isExternalPresetTriggerEnabled, forKey: externalPresetTriggerEnabledKey)
        defaults.set(externalPresetTriggerChannel, forKey: externalPresetTriggerChannelKey)
        defaults.set(externalPresetTriggerSource, forKey: externalPresetTriggerSourceKey)

        // Helix auto-connect
        defaults.set(autoConnectHelix, forKey: autoConnectHelixKey)

        if let endpoint = selectedDestinationEndpoint,
           let dest = availableDestinations.first(where: { $0.endpoint == endpoint }) {
            savedDestinationName = dest.name
            defaults.set(dest.name, forKey: selectedDestinationKey)
        }
    }

    private func restoreSelectedDestination() {
        let defaults = UserDefaults.standard

        if savedDestinationName == nil {
            savedDestinationName = defaults.string(forKey: selectedDestinationKey)
        }

        guard let savedName = savedDestinationName else { return }

        isRestoringDestination = true
        if let dest = availableDestinations.first(where: { $0.name == savedName }) {
            selectedDestinationEndpoint = dest.endpoint
            print("MacMIDIEngine: Restored destination '\(savedName)'")
        }
        isRestoringDestination = false
    }

    // MARK: - MIDI Setup

    private func setupMIDI() {
        var status: OSStatus

        status = MIDIClientCreateWithBlock("Keyframe Mac" as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }

        guard status == noErr else {
            print("MacMIDIEngine: Failed to create client: \(status)")
            return
        }

        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            var sourceName: String? = nil
            if let refCon = srcConnRefCon {
                let endpoint = MIDIEndpointRef(truncatingIfNeeded: UInt(bitPattern: refCon))
                sourceName = self?.sourceNameMap[endpoint]
            }
            self?.handleMIDIEventList(eventList, sourceName: sourceName)
        }

        guard status == noErr else {
            print("MacMIDIEngine: Failed to create input port: \(status)")
            return
        }

        status = MIDIOutputPortCreate(
            midiClient,
            "Output" as CFString,
            &outputPort
        )

        guard status == noErr else {
            print("MacMIDIEngine: Failed to create output port: \(status)")
            return
        }

        isInitialized = true
        connectToAllSources()
        refreshDestinations()

        print("MacMIDIEngine: Initialized successfully")
    }

    private func teardownMIDI() {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    // MARK: - Network MIDI

    private func configureNetworkSession() {
        let networkSession = MIDINetworkSession.default()

        networkSession.isEnabled = isNetworkSessionEnabled
        networkSession.connectionPolicy = isNetworkSessionEnabled ? .anyone : .noOne

        if isNetworkSessionEnabled {
            print("MacMIDIEngine: Network MIDI session '\(networkSession.localName)' enabled")
        }

        refreshDestinations()
    }

    // MARK: - Notifications

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        if notification.pointee.messageID == .msgSetupChanged {
            DispatchQueue.main.async { [weak self] in
                self?.connectToAllSources()
                self?.refreshDestinations()
            }
        }
    }

    // MARK: - Source Management

    func connectToAllSources() {
        guard isInitialized else { return }

        sourceNameMap.removeAll()

        var sources: [MacMIDISourceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let name = getEndpointName(source) ?? "Unknown"

            sourceNameMap[source] = name

            let refCon = UnsafeMutableRawPointer(bitPattern: Int(source))
            let status = MIDIPortConnectSource(inputPort, source, refCon)

            if status == noErr {
                let info = MacMIDISourceInfo(endpoint: source, name: name, isConnected: true)
                sources.append(info)
                print("MacMIDIEngine: Connected to '\(name)'")
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.connectedSources = sources
        }
    }

    func refreshDestinations() {
        var destinations: [MacMIDIDestinationInfo] = []
        var helix: MacMIDIDestinationInfo? = nil
        let destinationCount = MIDIGetNumberOfDestinations()

        for i in 0..<destinationCount {
            let destination = MIDIGetDestination(i)
            let name = getEndpointName(destination) ?? "Unknown"

            let info = MacMIDIDestinationInfo(endpoint: destination, name: name)
            destinations.append(info)

            // Detect Helix (matches "Helix", "Helix Floor", "Helix LT", "HX Stomp", etc.)
            if name.lowercased().contains("helix") || name.lowercased().contains("hx stomp") || name.lowercased().contains("hx effects") {
                helix = info
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableDestinations = destinations
            self.detectedHelix = helix
            self.restoreSelectedDestination()

            // Auto-connect to Helix if enabled and no destination selected
            if self.autoConnectHelix,
               let helixDest = helix,
               self.selectedDestinationEndpoint == nil {
                self.selectedDestinationEndpoint = helixDest.endpoint
                print("MacMIDIEngine: Auto-connected to Helix '\(helixDest.name)'")
            }
        }
    }

    /// Manually connect to detected Helix
    func connectToHelix() {
        guard let helix = detectedHelix else {
            print("MacMIDIEngine: No Helix detected")
            return
        }
        selectedDestinationEndpoint = helix.endpoint
        print("MacMIDIEngine: Connected to Helix '\(helix.name)'")
    }

    /// Check if currently connected to Helix
    var isConnectedToHelix: Bool {
        guard let helix = detectedHelix,
              let selected = selectedDestinationEndpoint else { return false }
        return helix.endpoint == selected
    }

    private func getEndpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)

        if status == noErr, let name = name {
            return name.takeRetainedValue() as String
        }
        return nil
    }

    // MARK: - External MIDI Output

    func sendExternalMIDIMessages(_ messages: [ExternalMIDIMessage]) {
        guard let destination = selectedDestinationEndpoint else { return }
        guard outputPort != 0 else { return }

        for message in messages {
            sendMIDIMessage(message, to: destination)
        }
    }

    private func sendMIDIMessage(_ message: ExternalMIDIMessage, to destination: MIDIEndpointRef) {
        let channel = UInt8(externalMIDIChannel - 1)

        let midiBytes: [UInt8]
        switch message.type {
        case .noteOn:
            midiBytes = [0x90 | channel, UInt8(message.data1), UInt8(message.data2)]
        case .noteOff:
            midiBytes = [0x80 | channel, UInt8(message.data1), UInt8(message.data2)]
        case .controlChange:
            midiBytes = [0xB0 | channel, UInt8(message.data1), UInt8(message.data2)]
        case .programChange:
            midiBytes = [0xC0 | channel, UInt8(message.data1)]
        }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, midiBytes.count, midiBytes)

        MIDISend(outputPort, destination, &packetList)
    }

    func sendTapTempo(bpm: Int) {
        guard isExternalTempoSyncEnabled else { return }
        guard let destination = selectedDestinationEndpoint else { return }
        guard outputPort != 0 else { return }

        if let lastTempo = lastSentTempo, lastTempo == bpm { return }
        lastSentTempo = bpm

        let channel = UInt8(externalMIDIChannel - 1)
        let ccNumber = UInt8(tapTempoCC)
        let midiBytes: [UInt8] = [0xB0 | channel, ccNumber, 127]

        let intervalSeconds = 60.0 / Double(bpm)
        let intervalHostTime = secondsToHostTime(intervalSeconds)
        let now = mach_absolute_time()

        let numTaps = 8
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
        print("MacMIDIEngine: Sent tap tempo at \(bpm) BPM")
    }

    func resetTempoTracking() {
        lastSentTempo = nil
    }

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

        var packet = UnsafeRawPointer(eventList)
            .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIEventPacket.self)

        for _ in 0..<numPackets {
            handleMIDIEventPacket(packet.pointee, sourceName: sourceName)
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
    }

    private func handleMIDIEventPacket(_ packet: MIDIEventPacket, sourceName: String?) {
        let words = [packet.words.0, packet.words.1, packet.words.2, packet.words.3]
        let word = words[0]

        let status = UInt8((word >> 16) & 0xFF)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        let messageType = status & 0xF0
        let channel = status & 0x0F

        DispatchQueue.main.async { [weak self] in
            self?.lastActivity = Date()
        }

        switch messageType {
        case 0x90:
            if data2 > 0 {
                processNoteOn(note: data1, velocity: data2, channel: channel, sourceName: sourceName)
            } else {
                processNoteOff(note: data1, channel: channel, sourceName: sourceName)
            }
        case 0x80:
            processNoteOff(note: data1, channel: channel, sourceName: sourceName)
        case 0xB0:
            processCC(cc: data1, value: data2, channel: channel, sourceName: sourceName)
        case 0xC0:
            processProgramChange(program: data1, channel: channel, sourceName: sourceName)
        case 0xE0:
            processPitchBend(lsb: data1, msb: data2, channel: channel, sourceName: sourceName)
        default:
            break
        }
    }

    // MARK: - Note Processing

    private func channelAcceptsMIDI(_ strip: MacChannelStrip, sourceName: String?, midiChannel: Int) -> Bool {
        let channelMatches = strip.midiChannel == 0 || strip.midiChannel == midiChannel
        let sourceMatches = strip.midiSourceName == nil || strip.midiSourceName == sourceName
        return channelMatches && sourceMatches
    }

    /// Check if a note falls within any of the channel's keyboard zones
    /// Returns transformed (note, velocity) tuples for each matching zone
    private func applyKeyboardZones(note: UInt8, velocity: UInt8, config: MacChannelConfiguration) -> [(note: UInt8, velocity: UInt8)] {
        // If no zones configured, pass through unchanged (full range)
        if config.keyboardZones.isEmpty {
            return [(note, velocity)]
        }

        var results: [(note: UInt8, velocity: UInt8)] = []

        for zone in config.keyboardZones {
            if let transformed = zone.transform(note: Int(note), velocity: Int(velocity)) {
                results.append((UInt8(transformed.note), UInt8(transformed.velocity)))
            }
        }

        return results
    }

    private func processNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, sourceName: String?) {
        let midiChannel = Int(channel) + 1

        // Preset trigger learn mode - capture Note On
        if let target = presetTriggerLearnTarget {
            completePresetTriggerLearn(type: .noteOn, channel: midiChannel, data1: Int(note), data2: Int(velocity), sourceName: sourceName, target: target)
            return
        }

        // Check for preset trigger mappings
        if checkPresetTriggers(type: .noteOn, channel: midiChannel, data1: Int(note), data2: Int(velocity), sourceName: sourceName) {
            return
        }

        if isLearningMode {
            DispatchQueue.main.async { [weak self] in
                self?.onNoteLearn?(Int(note), midiChannel, sourceName)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onSongTrigger?(Int(note), midiChannel, sourceName)
        }

        guard let audioEngine = audioEngine else { return }

        // Check for ChordPad
        if let chordPadSource = chordPadSourceName,
           chordPadSource == sourceName,
           midiChannel == chordPadChannel {
            if chordMapping.buttonMap[Int(note)] != nil {
                processChordTrigger(note: note, velocity: velocity, channel: channel, sourceName: sourceName)
            }
            return
        }

        let targetChannels = audioEngine.channelStrips.filter { strip in
            channelAcceptsMIDI(strip, sourceName: sourceName, midiChannel: midiChannel)
        }

        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        // Get channel configurations for zone processing
        let session = sessionStore?.currentSession

        for targetChannel in targetChannels {
            // Find the channel configuration for zone support
            let config = session?.channels.first { $0.id == targetChannel.id }

            // Apply keyboard zones first (if configured)
            let zoneTransformed: [(note: UInt8, velocity: UInt8)]
            if let config = config {
                zoneTransformed = applyKeyboardZones(note: note, velocity: velocity, config: config)
            } else {
                zoneTransformed = [(note, velocity)]
            }

            // Skip if note doesn't fall in any zone
            guard !zoneTransformed.isEmpty else { continue }

            var allProcessedNotes: [UInt8] = []

            for (zoneNote, zoneVelocity) in zoneTransformed {
                let processedNotes: [UInt8]

                // Apply scale filter after zone transformation
                if targetChannel.scaleFilterEnabled && isScaleFilterEnabled {
                    processedNotes = applyScaleFilter(note: zoneNote)
                } else {
                    processedNotes = [zoneNote]
                }

                allProcessedNotes.append(contentsOf: processedNotes)

                for processedNote in processedNotes {
                    targetChannel.sendMIDI(noteOn: processedNote, velocity: zoneVelocity)
                }
            }

            activeNotes[sourceKey]?[targetChannel.id] = allProcessedNotes
        }

        updateLastMessage("\(sourceName ?? "?"): Note \(note) vel \(velocity) ch \(channel + 1)")
    }

    private func processNoteOff(note: UInt8, channel: UInt8, sourceName: String?) {
        guard let audioEngine = audioEngine else { return }

        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

        if let channelMappings = activeNotes[sourceKey] {
            for (channelId, processedNotes) in channelMappings {
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

        // Preset trigger learn mode - capture CC for preset triggering
        if let target = presetTriggerLearnTarget {
            completePresetTriggerLearn(type: .controlChange, channel: midiChannel, data1: Int(cc), data2: Int(value), sourceName: sourceName, target: target)
            return
        }

        // Check for preset trigger mappings (CC-based triggers)
        if checkPresetTriggers(type: .controlChange, channel: midiChannel, data1: Int(cc), data2: Int(value), sourceName: sourceName) {
            return
        }

        // MIDI Learn mode - capture CC for fader/pan mapping
        if let target = learningTarget {
            completeMIDILearn(cc: Int(cc), channel: midiChannel, sourceName: sourceName, target: target)
            return
        }

        if isCCLearningMode {
            DispatchQueue.main.async { [weak self] in
                self?.onCCLearn?(Int(cc), midiChannel, sourceName)
            }
            return
        }

        // Check for iOS remote control messages on channel 16
        if midiChannel == 16 {
            handleRemoteControlCC(cc: Int(cc), value: Int(value))
            return
        }

        // Check for learned MIDI mappings
        if applyMIDIMappings(cc: Int(cc), value: Int(value), channel: midiChannel, sourceName: sourceName) {
            // Mapping was applied, don't pass through to channels
            updateLastMessage("\(sourceName ?? "?"): CC \(cc) = \(value) ch \(channel + 1) [mapped]")
            return
        }

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

        updateLastMessage("\(sourceName ?? "?"): CC \(cc) = \(value) ch \(channel + 1)")
    }

    // MARK: - MIDI Learn

    /// Start learning a MIDI CC for the specified target
    func startMIDILearn(for target: MIDILearnTarget) {
        learningTarget = target
        print("MacMIDIEngine: Learning MIDI CC for '\(target.displayName)'")
    }

    /// Cancel MIDI learn mode
    func cancelMIDILearn() {
        learningTarget = nil
    }

    /// Complete MIDI learn by creating a mapping
    private func completeMIDILearn(cc: Int, channel: Int, sourceName: String?, target: MIDILearnTarget) {
        let mapping = MIDICCMapping(
            cc: cc,
            channel: channel,
            sourceName: sourceName,
            target: target.target,
            targetChannelId: target.channelId,
            targetPluginId: target.pluginId,
            targetParameterIndex: target.parameterIndex,
            displayName: target.displayName
        )

        // Store mapping
        if !midiMappings.contains(where: { $0.id == mapping.id }) {
            midiMappings.append(mapping)
        }

        // Notify via callback
        DispatchQueue.main.async { [weak self] in
            self?.onMappingLearned?(mapping)
            self?.learningTarget = nil
        }

        // Save to session
        sessionStore?.addMIDIMapping(mapping)

        print("MacMIDIEngine: Learned CC \(cc) ch\(channel) → '\(target.displayName)'")
    }

    /// Apply learned MIDI mappings to incoming CC
    /// Returns true if a mapping was found and applied
    private func applyMIDIMappings(cc: Int, value: Int, channel: Int, sourceName: String?) -> Bool {
        guard let audioEngine = audioEngine else { return false }

        // Find matching mappings
        let matchingMappings = midiMappings.filter { mapping in
            mapping.cc == cc &&
            (mapping.channel == nil || mapping.channel == channel) &&
            (mapping.sourceName == nil || mapping.sourceName == sourceName)
        }

        guard !matchingMappings.isEmpty else { return false }

        let normalizedValue = Float(value) / 127.0

        for mapping in matchingMappings {
            switch mapping.target {
            case .channelVolume:
                if let channelId = mapping.targetChannelId,
                   let channel = audioEngine.channelStrips.first(where: { $0.id == channelId }) {
                    DispatchQueue.main.async {
                        channel.volume = normalizedValue
                    }
                }

            case .channelPan:
                if let channelId = mapping.targetChannelId,
                   let channel = audioEngine.channelStrips.first(where: { $0.id == channelId }) {
                    // Pan: 0 = left (-1), 64 = center (0), 127 = right (1)
                    let pan = (normalizedValue * 2.0) - 1.0
                    DispatchQueue.main.async {
                        channel.pan = pan
                    }
                }

            case .channelMute:
                if let channelId = mapping.targetChannelId,
                   let channel = audioEngine.channelStrips.first(where: { $0.id == channelId }) {
                    // Toggle on any non-zero value, or use threshold
                    let muted = value > 63
                    DispatchQueue.main.async {
                        channel.isMuted = muted
                    }
                }

            case .masterVolume:
                DispatchQueue.main.async {
                    audioEngine.masterVolume = normalizedValue
                }

            case .pluginParameter:
                // TODO: Implement plugin parameter control
                // Requires access to AU parameters via AudioUnit API
                break
            }
        }

        return true
    }

    /// Load mappings from session (call when session changes)
    func loadMappings(from session: MacSession) {
        DispatchQueue.main.async { [weak self] in
            self?.midiMappings = session.midiMappings
        }
        print("MacMIDIEngine: Loaded \(session.midiMappings.count) MIDI mappings")
    }

    /// Remove a specific mapping
    func removeMapping(_ mapping: MIDICCMapping) {
        midiMappings.removeAll { $0.id == mapping.id }
        sessionStore?.removeMIDIMapping(mapping)
    }

    // MARK: - Preset Trigger MIDI Learn

    /// Start learning a MIDI trigger for the specified preset
    func startPresetTriggerLearn(forPresetIndex index: Int, presetName: String) {
        presetTriggerLearnTarget = PresetTriggerLearnTarget(presetIndex: index, presetName: presetName)
        print("MacMIDIEngine: Learning preset trigger for '\(presetName)' (index \(index))")
    }

    /// Cancel preset trigger learn mode
    func cancelPresetTriggerLearn() {
        presetTriggerLearnTarget = nil
    }

    /// Complete preset trigger learning
    private func completePresetTriggerLearn(type: PresetTriggerType, channel: Int, data1: Int, data2: Int, sourceName: String?, target: PresetTriggerLearnTarget) {
        let mapping = PresetTriggerMapping(
            triggerType: type,
            channel: channel,
            sourceName: sourceName,
            data1: data1,
            data2Min: type == .programChange ? nil : 64,
            data2Max: type == .programChange ? nil : 127,
            presetIndex: target.presetIndex,
            displayName: target.presetName
        )

        // Store mapping
        if !presetTriggerMappings.contains(where: { $0.id == mapping.id }) {
            presetTriggerMappings.append(mapping)
        }

        // Notify and save
        DispatchQueue.main.async { [weak self] in
            self?.onPresetTriggerLearned?(mapping)
            self?.presetTriggerLearnTarget = nil
        }

        sessionStore?.addPresetTriggerMapping(mapping)
        print("MacMIDIEngine: Learned \(type.rawValue) \(data1) ch\(channel) → preset '\(target.presetName)'")
    }

    /// Check for matching preset trigger and fire if found
    /// Returns true if a trigger was matched
    private func checkPresetTriggers(type: PresetTriggerType, channel: Int, data1: Int, data2: Int, sourceName: String?) -> Bool {
        guard let mapping = presetTriggerMappings.first(where: { $0.matches(type: type, channel: channel, data1: data1, data2: data2, sourceName: sourceName) }) else {
            return false
        }

        DispatchQueue.main.async { [weak self] in
            self?.onExternalPresetTrigger?(mapping.presetIndex)
        }

        print("MacMIDIEngine: Preset trigger matched → index \(mapping.presetIndex)")
        return true
    }

    /// Load preset trigger mappings from session
    func loadPresetTriggerMappings(from session: MacSession) {
        DispatchQueue.main.async { [weak self] in
            self?.presetTriggerMappings = session.presetTriggerMappings
        }
        print("MacMIDIEngine: Loaded \(session.presetTriggerMappings.count) preset trigger mappings")
    }

    /// Remove a preset trigger mapping
    func removePresetTriggerMapping(_ mapping: PresetTriggerMapping) {
        presetTriggerMappings.removeAll { $0.id == mapping.id }
        sessionStore?.removePresetTriggerMapping(mapping)
    }

    private func processProgramChange(program: UInt8, channel: UInt8, sourceName: String?) {
        let midiChannel = Int(channel) + 1

        // Preset trigger learn mode - capture Program Change
        if let target = presetTriggerLearnTarget {
            completePresetTriggerLearn(type: .programChange, channel: midiChannel, data1: Int(program), data2: 0, sourceName: sourceName, target: target)
            return
        }

        // iOS remote preset change on channel 16
        if midiChannel == 16 {
            DispatchQueue.main.async { [weak self] in
                self?.onRemotePresetChange?(Int(program))
            }
            print("MacMIDIEngine: Remote preset change to index \(program)")
            return
        }

        // Check for learned preset trigger mappings first
        if checkPresetTriggers(type: .programChange, channel: midiChannel, data1: Int(program), data2: 0, sourceName: sourceName) {
            return
        }

        // Legacy: External MIDI controller preset trigger (simple channel-based)
        if isExternalPresetTriggerEnabled && midiChannel == externalPresetTriggerChannel {
            // Check source filter if configured
            if let requiredSource = externalPresetTriggerSource {
                guard sourceName == requiredSource else { return }
            }

            DispatchQueue.main.async { [weak self] in
                self?.onExternalPresetTrigger?(Int(program))
            }
            print("MacMIDIEngine: External preset trigger to index \(program) from \(sourceName ?? "unknown")")
        }
    }

    private func processPitchBend(lsb: UInt8, msb: UInt8, channel: UInt8, sourceName: String?) {
        // TODO: Implement pitch bend forwarding
    }

    // MARK: - Remote Control (iOS)

    private func handleRemoteControlCC(cc: Int, value: Int) {
        // Channel 16 CCs are reserved for iOS remote control
        // CC 1-99: Channel volume (channel index = cc number)
        // CC 101-199: Channel mute (channel index = cc - 100)
        // CC 120 value 1: Request session sync

        guard let audioEngine = audioEngine else { return }

        if cc >= 1 && cc <= 99 {
            // Volume control
            let channelIndex = cc - 1
            if channelIndex < audioEngine.channelStrips.count {
                let volume = Float(value) / 127.0
                audioEngine.channelStrips[channelIndex].volume = volume
                print("MacMIDIEngine: Remote volume ch\(channelIndex) = \(volume)")
            }
        } else if cc >= 101 && cc <= 199 {
            // Mute control
            let channelIndex = cc - 101
            if channelIndex < audioEngine.channelStrips.count {
                let muted = value > 63
                audioEngine.channelStrips[channelIndex].isMuted = muted
                print("MacMIDIEngine: Remote mute ch\(channelIndex) = \(muted)")
            }
        } else if cc == 121 && value == 1 {
            // Pull presets request from iOS
            print("MacMIDIEngine: iOS requested preset pull")
            sendPresetsToiOS()
        }
    }

    // MARK: - iOS Preset Sync

    /// SysEx command bytes for Keyframe protocol
    /// Format: F0 7D 4B 46 <command> <data...> F7
    private enum SysExCommand: UInt8 {
        case presetData = 0x01        // Full preset list (response to pull request)
        case presetChanged = 0x02     // Current preset index changed
        case channelVolume = 0x03     // Channel volume changed
        case channelMute = 0x04       // Channel mute state changed
    }

    /// Broadcast current preset index to iOS
    /// Called when preset changes from external MIDI, setlist, or Mac UI
    func broadcastPresetChange(index: Int) {
        guard isNetworkSessionEnabled else { return }

        let networkDestinations = availableDestinations.filter { dest in
            dest.name.contains("Network") || dest.name.contains("Session")
        }

        guard !networkDestinations.isEmpty else { return }

        // Simple format: just the index as a single byte (0-127)
        let sysexData: [UInt8] = [0xF0, 0x7D, 0x4B, 0x46, SysExCommand.presetChanged.rawValue, UInt8(min(index, 127)), 0xF7]

        for dest in networkDestinations {
            sendSysEx(sysexData, to: dest.endpoint)
        }

        print("MacMIDIEngine: Broadcast preset change to iOS: index \(index)")
    }

    /// Broadcast channel volume change to iOS
    func broadcastVolumeChange(channelIndex: Int, volume: Float) {
        guard isNetworkSessionEnabled else { return }

        let networkDestinations = availableDestinations.filter { dest in
            dest.name.contains("Network") || dest.name.contains("Session")
        }

        guard !networkDestinations.isEmpty else { return }

        // Format: [channel index, volume 0-127]
        let volumeByte = UInt8(min(max(volume, 0), 1) * 127)
        let sysexData: [UInt8] = [0xF0, 0x7D, 0x4B, 0x46, SysExCommand.channelVolume.rawValue, UInt8(channelIndex), volumeByte, 0xF7]

        for dest in networkDestinations {
            sendSysEx(sysexData, to: dest.endpoint)
        }
    }

    /// Broadcast channel mute change to iOS
    func broadcastMuteChange(channelIndex: Int, isMuted: Bool) {
        guard isNetworkSessionEnabled else { return }

        let networkDestinations = availableDestinations.filter { dest in
            dest.name.contains("Network") || dest.name.contains("Session")
        }

        guard !networkDestinations.isEmpty else { return }

        // Format: [channel index, mute state (0 or 1)]
        let sysexData: [UInt8] = [0xF0, 0x7D, 0x4B, 0x46, SysExCommand.channelMute.rawValue, UInt8(channelIndex), isMuted ? 1 : 0, 0xF7]

        for dest in networkDestinations {
            sendSysEx(sysexData, to: dest.endpoint)
        }
    }

    /// Send all presets to iOS via SysEx
    /// Format: F0 7D 4B 46 <command> <json-data...> F7
    private func sendPresetsToiOS() {
        guard let sessionStore = sessionStore else {
            print("MacMIDIEngine: Cannot send presets - no session store")
            return
        }

        // Find the iOS device endpoint (Network MIDI source that sent the request)
        // For now, send to all Network MIDI destinations
        let networkSources = availableDestinations.filter { dest in
            dest.name.contains("Network") || dest.name.contains("Session")
        }

        guard !networkSources.isEmpty else {
            print("MacMIDIEngine: No Network MIDI destinations found for preset sync")
            return
        }

        // Create lightweight preset data for iOS
        let presets: [RemotePresetData] = sessionStore.currentSession.presets.enumerated().map { index, preset in
            RemotePresetData(
                index: index,
                name: preset.name,
                songName: preset.songName,
                bpm: preset.bpm != nil ? Int(preset.bpm!) : nil,
                rootNote: preset.rootNote?.midiValue,
                scale: preset.scale?.rawValue
            )
        }

        guard let jsonData = try? JSONEncoder().encode(presets) else {
            print("MacMIDIEngine: Failed to encode presets")
            return
        }

        // SysEx header: F0 7D (non-commercial) 4B 46 (KF = Keyframe) 01 (preset data)
        var sysexData: [UInt8] = [0xF0, 0x7D, 0x4B, 0x46, 0x01]

        // Encode JSON as 7-bit safe (split each byte into two 4-bit nibbles)
        for byte in jsonData {
            sysexData.append((byte >> 4) & 0x0F)
            sysexData.append(byte & 0x0F)
        }

        sysexData.append(0xF7)

        // Send to all network destinations
        for dest in networkSources {
            sendSysEx(sysexData, to: dest.endpoint)
        }

        print("MacMIDIEngine: Sent \(presets.count) presets to iOS (\(sysexData.count) bytes)")
    }

    private func sendSysEx(_ data: [UInt8], to destination: MIDIEndpointRef) {
        guard outputPort != 0 else { return }

        let bufferSize = data.count + 100
        let packetListPtr = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4)
            .assumingMemoryBound(to: MIDIPacketList.self)
        defer { packetListPtr.deallocate() }

        var packet = MIDIPacketListInit(packetListPtr)
        packet = MIDIPacketListAdd(packetListPtr, bufferSize, packet, 0, data.count, data)

        MIDISend(outputPort, destination, packetListPtr)
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

        guard let chordNotes = ChordEngine.processChordTrigger(
            inputNote: note,
            mapping: chordMapping,
            rootNote: currentRootNote,
            scaleType: currentScaleType,
            baseOctave: chordMapping.baseOctave
        ) else { return }

        let targetChannels = audioEngine.channelStrips.filter { $0.isChordPadTarget }

        let sourceHash = sourceName?.hashValue ?? 0
        let sourceKey = sourceHash ^ (Int(channel) << 8) ^ Int(note)

        if activeNotes[sourceKey] == nil {
            activeNotes[sourceKey] = [:]
        }

        for targetChannel in targetChannels {
            activeNotes[sourceKey]?[targetChannel.id] = chordNotes

            for chordNote in chordNotes {
                targetChannel.sendMIDI(noteOn: chordNote, velocity: velocity)
            }
        }

        updateLastMessage("Chord: \(chordNotes.map { String($0) }.joined(separator: ","))")
    }

    // MARK: - Song/Preset Changes

    func applySongSettings(_ song: Song) {
        currentRootNote = song.rootNote
        currentScaleType = song.scaleType
        filterMode = song.filterMode
    }

    // MARK: - Helpers

    private func updateLastMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastReceivedMessage = message
        }
    }
}

// MARK: - MIDI Source Info

struct MacMIDISourceInfo: Identifiable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String
    var isConnected: Bool
}

// MARK: - MIDI Destination Info

struct MacMIDIDestinationInfo: Identifiable, Equatable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String

    static func == (lhs: MacMIDIDestinationInfo, rhs: MacMIDIDestinationInfo) -> Bool {
        lhs.endpoint == rhs.endpoint
    }
}
