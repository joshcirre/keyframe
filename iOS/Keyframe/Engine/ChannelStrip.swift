import AVFoundation
import AudioToolbox
import UIKit

/// Represents a single channel strip with instrument, effects, and mixing controls
final class ChannelStrip: ObservableObject, Identifiable {
    
    // MARK: - Properties
    
    let id = UUID()
    var index: Int
    var name: String
    
    // MARK: - Audio Nodes
    
    private weak var engine: AVAudioEngine?
    private let mixer = AVAudioMixerNode()
    
    /// The instrument AUv3 (synthesizer/sampler)
    private(set) var instrument: AVAudioUnit? {
        didSet { objectWillChange.send() }
    }
    var instrumentInfo: AUv3Info?
    
    /// Insert effects chain (up to 4)
    private(set) var effects: [AVAudioUnit] = [] {
        didSet { objectWillChange.send() }
    }
    var effectInfos: [AUv3Info] = []
    let maxEffects = 4
    
    /// Output node for connecting to master
    var outputNode: AVAudioMixerNode { mixer }
    
    // MARK: - Channel Controls
    
    @Published var volume: Float = 1.0 {
        didSet {
            if !isMuted {
                mixer.outputVolume = volume
            }
        }
    }
    
    @Published var pan: Float = 0.0 {
        didSet {
            mixer.pan = pan
        }
    }
    
    @Published var isMuted: Bool = false {
        didSet {
            mixer.outputVolume = isMuted ? 0 : volume
        }
    }
    
    @Published var isSoloed: Bool = false
    
    // MARK: - MIDI Settings
    
    /// MIDI channel this strip responds to (1-16, 0 = omni)
    @Published var midiChannel: Int = 0
    
    /// MIDI source name this strip responds to (nil = any source, "__none__" = disabled)
    @Published var midiSourceName: String? = "__none__"
    
    /// Whether scale filtering is applied to incoming MIDI
    @Published var scaleFilterEnabled: Bool = true
    
    /// Whether this channel handles ChordPad chord triggers
    @Published var isChordPadTarget: Bool = false
    
    // MARK: - Metering

    @Published var peakLevel: Float = -60.0
    private var meterTap: Bool = false
    private var pendingPeakLevel: Float = -60.0  // Written by audio thread
    private var meterUpdateTimer: Timer?
    
    // MARK: - State

    var isInstrumentLoaded: Bool { instrument != nil }
    @Published private(set) var isLoading: Bool = false

    // MARK: - Host Musical Context

    /// Current tempo for this channel's plugins
    private var hostTempo: Double = 120.0
    private var hostIsPlaying: Bool = true

    // MARK: - Initialization
    
    init(engine: AVAudioEngine, index: Int) {
        self.engine = engine
        self.index = index
        self.name = "Channel \(index + 1)"
        
        setupMixer()
    }
    
    private func setupMixer() {
        guard let engine = engine else { return }

        engine.attach(mixer)
        mixer.outputVolume = volume
        mixer.pan = pan

        // Install metering tap
        let format = mixer.outputFormat(forBus: 0)
        if format.sampleRate > 0 {
            mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processMeterData(buffer)
            }
            meterTap = true
        }

        // Timer to read pending meter value (avoids main thread dispatch from audio thread)
        meterUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let pending = self.pendingPeakLevel
            let newLevel = max(pending, self.peakLevel - 2.0)
            // Guard against NaN propagation
            self.peakLevel = newLevel.isFinite ? newLevel : -60
        }
    }

    private func processMeterData(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        var maxSample: Float = 0

        // Use stride for better performance
        let stride = max(1, frameCount / 64)
        var frame = 0
        while frame < frameCount {
            let sample = abs(channelData[0][frame])
            if sample > maxSample {
                maxSample = sample
            }
            frame += stride
        }

        // Store for timer to read (no main thread dispatch from audio thread!)
        // Guard against NaN/Inf from corrupted audio data
        let db: Float
        if maxSample > 0 && maxSample.isFinite {
            db = 20 * log10(maxSample)
        } else {
            db = -60
        }
        pendingPeakLevel = db.isFinite ? db : -60
    }
    
    // MARK: - Instrument Loading
    
    /// Load an AUv3 instrument into this channel
    func loadInstrument(_ description: AudioComponentDescription, completion: @escaping (Bool, Error?) -> Void) {
        guard let engine = engine else {
            completion(false, NSError(domain: "ChannelStrip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not available"]))
            return
        }
        
        isLoading = true
        
        // Unload existing instrument first
        unloadInstrument()
        
        AVAudioUnit.instantiate(with: description, options: []) { [weak self] audioUnit, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("ChannelStrip \(self.index): Failed to load instrument: \(error)")
                    completion(false, error)
                    return
                }
                
                guard let audioUnit = audioUnit else {
                    completion(false, NSError(domain: "ChannelStrip", code: 2, userInfo: [NSLocalizedDescriptionKey: "AudioUnit is nil"]))
                    return
                }
                
                self.instrument = audioUnit
                engine.attach(audioUnit)

                // Apply musical context for tempo sync
                self.applyMusicalContext(to: audioUnit.auAudioUnit)

                // Connect instrument to first effect or directly to mixer
                self.rebuildAudioChain()

                print("ChannelStrip \(self.index): Loaded instrument")
                completion(true, nil)
            }
        }
    }
    
    /// Unload the current instrument
    func unloadInstrument() {
        guard let instrument = instrument, let engine = engine else { return }

        // Clear blocks before detaching to avoid dangling references
        instrument.auAudioUnit.musicalContextBlock = nil
        instrument.auAudioUnit.transportStateBlock = nil

        engine.detach(instrument)
        self.instrument = nil
        self.instrumentInfo = nil

        rebuildAudioChain()
    }
    
    // MARK: - Effects Chain
    
    /// Add an effect to the insert chain
    func addEffect(_ description: AudioComponentDescription, completion: @escaping (Bool, Error?) -> Void) {
        guard let engine = engine else {
            completion(false, NSError(domain: "ChannelStrip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not available"]))
            return
        }
        
        guard effects.count < maxEffects else {
            completion(false, NSError(domain: "ChannelStrip", code: 3, userInfo: [NSLocalizedDescriptionKey: "Maximum effects reached"]))
            return
        }
        
        isLoading = true
        
        AVAudioUnit.instantiate(with: description, options: []) { [weak self] audioUnit, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("ChannelStrip \(self.index): Failed to load effect: \(error)")
                    completion(false, error)
                    return
                }
                
                guard let audioUnit = audioUnit else {
                    completion(false, NSError(domain: "ChannelStrip", code: 2, userInfo: [NSLocalizedDescriptionKey: "AudioUnit is nil"]))
                    return
                }
                
                self.effects.append(audioUnit)
                engine.attach(audioUnit)

                // Apply musical context for tempo sync
                self.applyMusicalContext(to: audioUnit.auAudioUnit)

                self.rebuildAudioChain()

                // Verify mixer is still connected to something (its output should go to masterMixer)
                let mixerOutputConnections = engine.outputConnectionPoints(for: self.mixer, outputBus: 0)
                if mixerOutputConnections.isEmpty {
                    print("⚠️ ChannelStrip \(self.index): Mixer lost connection to master! Needs reconnect.")
                } else {
                    print("✅ ChannelStrip \(self.index): Mixer connected to \(mixerOutputConnections.count) output(s)")
                }

                print("ChannelStrip \(self.index): Added effect (\(self.effects.count) total)")
                completion(true, nil)
            }
        }
    }
    
    /// Remove an effect at index
    func removeEffect(at index: Int) {
        guard index < effects.count, let engine = engine else { return }

        let effect = effects.remove(at: index)
        effectInfos.remove(at: index)

        // Clear blocks before detaching to avoid dangling references
        effect.auAudioUnit.musicalContextBlock = nil
        effect.auAudioUnit.transportStateBlock = nil

        engine.detach(effect)

        rebuildAudioChain()
    }
    
    /// Toggle bypass on an effect
    func setEffectBypassed(_ bypassed: Bool, at index: Int) {
        guard index < effects.count else { return }
        effects[index].auAudioUnit.shouldBypassEffect = bypassed
    }
    
    /// Apply bypass states from preset
    func applyEffectBypasses(_ bypasses: [Bool]) {
        for (index, bypassed) in bypasses.enumerated() {
            if index < effects.count {
                effects[index].auAudioUnit.shouldBypassEffect = bypassed
            }
        }
    }
    
    // MARK: - Audio Chain Management

    /// Rebuild the audio signal chain after changes (also called by AudioEngine after stop/start)
    func rebuildAudioChain() {
        guard let engine = engine else {
            print("⚠️ ChannelStrip \(index): rebuildAudioChain - no engine!")
            return
        }

        print("🔧 ChannelStrip \(index): Rebuilding audio chain (instrument: \(instrument != nil), effects: \(effects.count))")

        // Disconnect existing connections from nodes we'll reconnect
        // Note: We don't disconnect mixer input - new connections will replace old ones
        if let instrument = instrument {
            engine.disconnectNodeOutput(instrument)
        }
        for effect in effects {
            engine.disconnectNodeOutput(effect)
        }

        // Build the chain: Instrument -> Effects -> Mixer
        // Use nil format to let AVAudioEngine auto-negotiate between nodes.
        // This avoids kAudioUnitErr_FormatNotSupported (-10868) crashes.
        var previousNode: AVAudioNode? = instrument

        for (i, effect) in effects.enumerated() {
            if let prev = previousNode {
                engine.connect(prev, to: effect, format: nil)
                print("   Connected \(type(of: prev)) → effect[\(i)]")
            } else {
                // No instrument yet - effect can't receive input
                // This is okay during async loading; chain will rebuild when instrument loads
                print("   ⚠️ Effect[\(i)] has no input source (instrument not loaded yet)")
            }
            previousNode = effect
        }

        // Connect final node to mixer
        if let finalNode = previousNode {
            engine.connect(finalNode, to: mixer, format: nil)
            print("   Connected \(type(of: finalNode)) → mixer")
        } else if instrument == nil && !effects.isEmpty {
            // Effects exist but no instrument - connect first effect to mixer anyway
            // so the chain is ready when instrument loads
            print("   ⚠️ No instrument - effects waiting for input")
        } else {
            print("   ⚠️ No nodes to connect to mixer")
        }

        print("🔧 ChannelStrip \(index): Chain rebuild complete")
    }

    // MARK: - Host Musical Context (Tempo Sync)

    /// Update the musical context (tempo, transport) for all hosted plugins
    /// Note: We only update the values here - the blocks read from these values
    /// and were set once when the AU was loaded. Don't re-apply blocks while
    /// audio is rendering as it causes race conditions.
    func updateMusicalContext(tempo: Double, isPlaying: Bool) {
        hostTempo = tempo
        hostIsPlaying = isPlaying
        // Blocks already reference hostTempo and hostIsPlaying via weak self
        // No need to re-apply them - that causes race conditions on the audio thread
    }

    /// Apply musical context blocks to a newly loaded AU (called once at load time)
    /// This should only be called when first loading an instrument/effect,
    /// NOT when tempo changes (use updateMusicalContext for that)
    func applyMusicalContextToAllAUs() {
        if let instrument = instrument {
            applyMusicalContext(to: instrument.auAudioUnit)
        }
        for effect in effects {
            applyMusicalContext(to: effect.auAudioUnit)
        }
    }

    /// Apply musical context block to a single AU
    private func applyMusicalContext(to au: AUAudioUnit) {
        // Create the musical context block that plugins will query
        au.musicalContextBlock = { [weak self] (
            currentTempo: UnsafeMutablePointer<Double>?,
            timeSignatureNumerator: UnsafeMutablePointer<Double>?,
            timeSignatureDenominator: UnsafeMutablePointer<Int>?,
            currentBeatPosition: UnsafeMutablePointer<Double>?,
            sampleOffsetToNextBeat: UnsafeMutablePointer<Int>?,
            currentMeasureDownbeatPosition: UnsafeMutablePointer<Double>?
        ) -> Bool in
            guard let self = self else { return false }

            // Provide tempo
            currentTempo?.pointee = self.hostTempo

            // 4/4 time signature
            timeSignatureNumerator?.pointee = 4.0
            timeSignatureDenominator?.pointee = 4

            // Beat position (simplified - real implementation would track this precisely)
            currentBeatPosition?.pointee = 0.0
            sampleOffsetToNextBeat?.pointee = 0
            currentMeasureDownbeatPosition?.pointee = 0.0

            return true
        }

        // Also set the transport state block
        au.transportStateBlock = { [weak self] (
            transportStateFlags: UnsafeMutablePointer<AUHostTransportStateFlags>?,
            currentSamplePosition: UnsafeMutablePointer<Double>?,
            cycleStartBeatPosition: UnsafeMutablePointer<Double>?,
            cycleEndBeatPosition: UnsafeMutablePointer<Double>?
        ) -> Bool in
            guard let self = self else { return false }

            // AUHostTransportStateFlags raw values:
            // Changed = 1, Moving = 2, Recording = 4, Cycling = 8
            var rawFlags: UInt = 1  // Changed
            if self.hostIsPlaying {
                rawFlags |= 2  // Moving (playing)
            }

            transportStateFlags?.pointee = AUHostTransportStateFlags(rawValue: rawFlags)
            currentSamplePosition?.pointee = 0
            cycleStartBeatPosition?.pointee = 0
            cycleEndBeatPosition?.pointee = 0

            return true
        }

        print("ChannelStrip \(index): Applied musical context (tempo: \(hostTempo) BPM)")
    }


    // MARK: - MIDI Handling
    
    /// Send MIDI note to the instrument
    func sendMIDI(noteOn note: UInt8, velocity: UInt8) {
        guard let instrument = instrument else { return }

        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let data: [UInt8] = [0x90, note, velocity]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }
    }
    
    func sendMIDI(noteOff note: UInt8) {
        guard let instrument = instrument else { return }
        
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let data: [UInt8] = [0x80, note, 0]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }
    }
    
    func sendMIDI(controlChange cc: UInt8, value: UInt8) {
        guard let instrument = instrument else { return }
        
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let data: [UInt8] = [0xB0, cc, value]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }
    }
    
    // MARK: - Plugin UI
    
    /// Get the view controller for the instrument's UI
    func getInstrumentViewController(completion: @escaping (UIViewController?) -> Void) {
        guard let instrument = instrument else {
            completion(nil)
            return
        }
        
        instrument.auAudioUnit.requestViewController { viewController in
            DispatchQueue.main.async {
                completion(viewController)
            }
        }
    }
    
    /// Get the view controller for an effect's UI
    func getEffectViewController(at index: Int, completion: @escaping (UIViewController?) -> Void) {
        guard index < effects.count else {
            completion(nil)
            return
        }
        
        effects[index].auAudioUnit.requestViewController { viewController in
            DispatchQueue.main.async {
                completion(viewController)
            }
        }
    }
    
    // MARK: - State Save/Restore
    
    /// Get the full state of this channel for saving
    func getState() -> ChannelStripState {
        var effectStates: [PluginState] = []
        
        for (index, effect) in effects.enumerated() {
            let info = index < effectInfos.count ? effectInfos[index] : nil
            let state = PluginState(
                audioComponentDescription: effect.audioComponentDescription,
                manufacturerName: info?.manufacturerName ?? "Unknown",
                pluginName: info?.name ?? "Unknown",
                presetData: try? effect.auAudioUnit.fullState as? Data,
                isBypassed: effect.auAudioUnit.shouldBypassEffect
            )
            effectStates.append(state)
        }
        
        var instrumentState: PluginState?
        if let instrument = instrument {
            instrumentState = PluginState(
                audioComponentDescription: instrument.audioComponentDescription,
                manufacturerName: instrumentInfo?.manufacturerName ?? "Unknown",
                pluginName: instrumentInfo?.name ?? "Unknown",
                presetData: try? instrument.auAudioUnit.fullState as? Data,
                isBypassed: false
            )
        }
        
        return ChannelStripState(
            id: id,
            name: name,
            instrument: instrumentState,
            effects: effectStates,
            volume: volume,
            pan: pan,
            isMuted: isMuted,
            midiChannel: midiChannel,
            scaleFilterEnabled: scaleFilterEnabled,
            isChordPadTarget: isChordPadTarget
        )
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        guard let engine = engine else { return }

        meterUpdateTimer?.invalidate()
        meterUpdateTimer = nil

        if meterTap {
            mixer.removeTap(onBus: 0)
        }

        // Clear musical context blocks before detaching to avoid dangling references
        if let instrument = instrument {
            instrument.auAudioUnit.musicalContextBlock = nil
            instrument.auAudioUnit.transportStateBlock = nil
            engine.detach(instrument)
        }

        for effect in effects {
            effect.auAudioUnit.musicalContextBlock = nil
            effect.auAudioUnit.transportStateBlock = nil
            engine.detach(effect)
        }

        engine.detach(mixer)

        // Clear references
        self.instrument = nil
        self.effects.removeAll()
    }
}

// MARK: - AUv3 Info

/// Information about a loaded AUv3 plugin
struct AUv3Info: Codable, Equatable {
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32
    
    var isInstrument: Bool {
        componentType == kAudioUnitType_MusicDevice
    }
    
    var isEffect: Bool {
        componentType == kAudioUnitType_Effect || componentType == kAudioUnitType_MusicEffect
    }
}

// MARK: - Plugin State

/// Saved state of an AUv3 plugin
struct PluginState: Codable, Equatable {
    var audioComponentDescription: AudioComponentDescription
    var manufacturerName: String
    var pluginName: String
    var presetData: Data?
    var isBypassed: Bool
}

// MARK: - AudioComponentDescription Codable Extension

extension AudioComponentDescription: Codable {
    enum CodingKeys: String, CodingKey {
        case componentType, componentSubType, componentManufacturer, componentFlags, componentFlagsMask
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            componentType: try container.decode(UInt32.self, forKey: .componentType),
            componentSubType: try container.decode(UInt32.self, forKey: .componentSubType),
            componentManufacturer: try container.decode(UInt32.self, forKey: .componentManufacturer),
            componentFlags: try container.decode(UInt32.self, forKey: .componentFlags),
            componentFlagsMask: try container.decode(UInt32.self, forKey: .componentFlagsMask)
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(componentType, forKey: .componentType)
        try container.encode(componentSubType, forKey: .componentSubType)
        try container.encode(componentManufacturer, forKey: .componentManufacturer)
        try container.encode(componentFlags, forKey: .componentFlags)
        try container.encode(componentFlagsMask, forKey: .componentFlagsMask)
    }
}

// MARK: - AudioComponentDescription Equatable Extension

extension AudioComponentDescription: Equatable {
    public static func == (lhs: AudioComponentDescription, rhs: AudioComponentDescription) -> Bool {
        lhs.componentType == rhs.componentType &&
        lhs.componentSubType == rhs.componentSubType &&
        lhs.componentManufacturer == rhs.componentManufacturer &&
        lhs.componentFlags == rhs.componentFlags &&
        lhs.componentFlagsMask == rhs.componentFlagsMask
    }
}

// MARK: - Channel Strip State

/// Complete saved state of a channel strip
struct ChannelStripState: Codable, Equatable {
    var id: UUID
    var name: String
    var instrument: PluginState?
    var effects: [PluginState]
    var volume: Float
    var pan: Float
    var isMuted: Bool
    var midiChannel: Int
    var scaleFilterEnabled: Bool
    var isChordPadTarget: Bool
}

