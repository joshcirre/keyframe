import AVFoundation
import AudioToolbox
import UIKit

/// Represents a single channel strip with instrument, effects, and mixing controls
@Observable
@MainActor
final class ChannelStrip: Identifiable {

    // MARK: - Properties

    let id = UUID()
    var index: Int
    var name: String
    var kind: ChannelKind = .instrument

    // MARK: - Audio Nodes

    private weak var engine: AVAudioEngine?
    private let mixer = AVAudioMixerNode()

    /// The instrument AUv3 (synthesizer/sampler)
    private(set) var instrument: AVAudioUnit?
    var instrumentInfo: AUv3Info?

    /// Live hardware input source for audio channels.
    @ObservationIgnored private var audioInputNode: AVAudioNode?

    /// Insert effects chain (up to 4)
    private(set) var effects: [AVAudioUnit] = []
    var effectInfos: [AUv3Info] = []
    let maxEffects = 4
    @ObservationIgnored private var effectParameterCache: [String: AUParameter] = [:]
    
    /// Observable bypass states (SwiftUI can't observe AVAudioUnit properties directly)
    var effectBypasses: [Bool] = []

    /// Output node for connecting to master
    var outputNode: AVAudioMixerNode { mixer }

    // MARK: - Channel Controls

    @ObservationIgnored var onMixerStateChanged: (() -> Void)?

    var volume: Float = 1.0 {
        didSet {
            if !isMuted {
                mixer.outputVolume = pow(volume, 2.2)
            }
            if oldValue != volume {
                onMixerStateChanged?()
            }
        }
    }

    var pan: Float = 0.0 {
        didSet {
            mixer.pan = pan
            if oldValue != pan {
                onMixerStateChanged?()
            }
        }
    }

    var isMuted: Bool = false {
        didSet {
            mixer.outputVolume = isMuted ? 0 : pow(volume, 2.2)
            if oldValue != isMuted {
                onMixerStateChanged?()
            }
        }
    }

    var isSoloed: Bool = false

    /// Intended hardware output pair for this channel. 0 = main output pair.
    var audioOutputPairIndex: Int = 0

    // MARK: - MIDI Settings

    /// MIDI channel this strip responds to (1-16, 0 = omni)
    var midiChannel: Int = 0

    /// MIDI source name this strip responds to (nil = any source, "__none__" = disabled)
    var midiSourceName: String? = "__none__"

    /// Whether scale filtering is applied to incoming MIDI
    var scaleFilterEnabled: Bool = true

    /// Whether this channel handles ChordPad chord triggers
    var isChordPadTarget: Bool = false

    /// Whether this channel handles Single Note (secondary zone) triggers
    var isSingleNoteTarget: Bool = false

    /// Octave transpose (-3 to +3 octaves, each octave = 12 semitones)
    var octaveTranspose: Int = 0

    // MARK: - CC to Parameter Mappings

    /// Maps MIDI CC numbers to AUParameter addresses for direct parameter control.
    /// When a CC has a mapping, we set the parameter value directly instead of
    /// (or in addition to) sending raw MIDI CC which most synths ignore.
    var ccParameterMappings: [CCParameterMapping] = []

    /// Cached parameter references for fast lookup during CC processing
    @ObservationIgnored private var ccParamCache: [UInt8: (param: AUParameter, minValue: Float, range: Float)] = [:]

    // MARK: - Metering

    var peakLevel: Float = -60.0
    @ObservationIgnored private var meterTap: Bool = false
    @ObservationIgnored nonisolated(unsafe) var pendingPeakLevel: Float = -60.0  // Written by audio thread, read by AudioEngine

    // MARK: - State

    var isInstrumentLoaded: Bool { instrument != nil }
    private(set) var isLoading: Bool = false

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

        // Install metering tap with nil format - let AVAudioEngine negotiate
        // Using smaller buffer (1024) for lower latency metering
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processMeterData(buffer)
        }
        meterTap = true
        // Note: Meter updates are driven by AudioEngine's consolidated timer
    }

    /// Called by AudioEngine's consolidated metering timer
    func updateMeterFromEngine() {
        let pending = pendingPeakLevel
        let newLevel = max(pending, peakLevel - 2.0)
        // Guard against NaN propagation
        peakLevel = newLevel.isFinite ? newLevel : -60
    }

    nonisolated private func processMeterData(_ buffer: AVAudioPCMBuffer) {
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

        kind = .instrument
        
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
                
                // Ensure channel stays connected to master after chain rebuild
                AudioEngine.shared.ensureChannelConnections()

                // Rebuild CC-to-parameter cache now that instrument is loaded
                self.rebuildCCParamCache()

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
        AudioEngine.shared.ensureChannelConnections()
    }

    /// Use the device/interface input as this channel's audio source.
    func useAudioInput(_ inputNode: AVAudioNode) {
        kind = .audioInput
        audioInputNode = inputNode

        if let instrument, let engine {
            instrument.auAudioUnit.musicalContextBlock = nil
            instrument.auAudioUnit.transportStateBlock = nil
            engine.detach(instrument)
            self.instrument = nil
            self.instrumentInfo = nil
        }

        midiSourceName = "__none__"
        scaleFilterEnabled = false
        isChordPadTarget = false
        isSingleNoteTarget = false
        rebuildAudioChain()
    }

    /// Use an AUv3 instrument as this channel's audio source.
    func useInstrumentSource() {
        kind = .instrument
        audioInputNode = nil
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
                self.effectBypasses.append(false)  // New effects start un-bypassed
                engine.attach(audioUnit)

                // Apply musical context for tempo sync
                self.applyMusicalContext(to: audioUnit.auAudioUnit)

                // Small delay to let the audio unit initialize before rebuilding chain
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.rebuildAudioChain()
                    AudioEngine.shared.ensureChannelConnections()
                    
                    // Verify mixer is still connected
                    let mixerOutputConnections = engine.outputConnectionPoints(for: self.mixer, outputBus: 0)
                    if mixerOutputConnections.isEmpty {
                        print("⚠️ ChannelStrip \(self.index): Mixer STILL disconnected after ensureChannelConnections!")
                    } else {
                        print("✅ ChannelStrip \(self.index): Mixer connected to \(mixerOutputConnections.count) output(s)")
                    }
                    
                    print("ChannelStrip \(self.index): Added effect (\(self.effects.count) total)")
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Remove an effect at index
    func removeEffect(at index: Int) {
        guard index < effects.count, let engine = engine else {
            print("⚠️ ChannelStrip \(self.index): removeEffect - invalid index \(index) (effects: \(effects.count))")
            return
        }

        print("🗑️ ChannelStrip \(self.index): Removing effect at index \(index)")

        let effect = effects.remove(at: index)
        effectParameterCache.removeAll()
        // effectInfos might be out of sync (e.g., during session restore), so check bounds
        if index < effectInfos.count {
            effectInfos.remove(at: index)
        }
        if index < effectBypasses.count {
            effectBypasses.remove(at: index)
        }

        // Clear blocks before detaching to avoid dangling references
        effect.auAudioUnit.musicalContextBlock = nil
        effect.auAudioUnit.transportStateBlock = nil

        engine.detach(effect)

        rebuildAudioChain()

        // CRITICAL: Reconnect mixer to master - rebuildAudioChain can disconnect it
        AudioEngine.shared.ensureChannelConnections()

        // Verify mixer is still connected to master
        let mixerOutputConnections = engine.outputConnectionPoints(for: mixer, outputBus: 0)
        if mixerOutputConnections.isEmpty {
            print("⚠️ ChannelStrip \(self.index): Mixer STILL disconnected after ensureChannelConnections!")
        } else {
            print("✅ ChannelStrip \(self.index): Effect removed, \(effects.count) remaining, mixer connected")
        }
    }

    /// Toggle bypass on an effect
    func setEffectBypassed(_ bypassed: Bool, at index: Int) {
        guard index < effects.count else {
            print("⚠️ ChannelStrip \(self.index): setEffectBypassed - invalid index \(index) (effects: \(effects.count))")
            return
        }
        
        let effect = effects[index]
        let auUnit = effect.auAudioUnit
        
        // Set bypass on the AUAudioUnit
        auUnit.shouldBypassEffect = bypassed
        
        // Verify it was set
        let actualBypass = auUnit.shouldBypassEffect
        
        // Update observable state so SwiftUI can react
        if index < effectBypasses.count {
            effectBypasses[index] = bypassed
        }
        
        print("🔇 ChannelStrip \(self.index): Effect[\(index)] bypass requested=\(bypassed), actual=\(actualBypass)")
        
        // If bypass didn't work, some AUv3s don't support it - log a warning
        if actualBypass != bypassed {
            print("⚠️ ChannelStrip \(self.index): Effect[\(index)] bypass not supported by this plugin")
        }
    }
    
    /// Apply bypass states from preset
    func applyEffectBypasses(_ bypasses: [Bool]) {
        for (index, bypassed) in bypasses.enumerated() {
            if index < effects.count {
                effects[index].auAudioUnit.shouldBypassEffect = bypassed
                // Update observable state
                if index < effectBypasses.count {
                    effectBypasses[index] = bypassed
                }
            }
        }
    }
    
    // MARK: - Audio Chain Management

    /// Verify the full strip chain reaches the channel mixer.
    func hasCompleteAudioChain() -> Bool {
        guard let engine = engine else { return false }

        let mixerConnectedToMaster = !engine.outputConnectionPoints(for: mixer, outputBus: 0).isEmpty
        guard mixerConnectedToMaster else { return false }

        if instrument == nil && effects.isEmpty {
            return kind == .instrument
        }

        guard let sourceNode = sourceNode else { return false }
        var previousNode: AVAudioNode? = sourceNode

        for effect in effects {
            guard let prev = previousNode else { return false }

            let connections = engine.outputConnectionPoints(for: prev, outputBus: 0)
            let isConnectedToEffect = connections.contains { $0.node === effect }
            guard isConnectedToEffect else { return false }

            previousNode = effect
        }

        guard let finalNode = previousNode else { return false }

        let finalConnections = engine.outputConnectionPoints(for: finalNode, outputBus: 0)
        return finalConnections.contains { $0.node === mixer }
    }

    /// Rebuild the audio signal chain after changes (also called by AudioEngine after stop/start)
    func rebuildAudioChain() {
        guard let engine = engine else {
            print("⚠️ ChannelStrip \(index): rebuildAudioChain - no engine!")
            return
        }

        print("🔧 ChannelStrip \(index): Rebuilding audio chain (kind: \(kind.rawValue), instrument: \(instrument != nil), effects: \(effects.count))")

        // Disconnect existing connections from nodes we'll reconnect
        // Hardware input is a shared I/O node. AVAudioEngine can retain stale
        // source mixer connections unless the input node output is cleared.
        if kind == .audioInput, let audioInputNode {
            engine.disconnectNodeOutput(audioInputNode)
        }
        engine.disconnectNodeInput(mixer)
        if let instrument = instrument {
            engine.disconnectNodeOutput(instrument)
        }
        for effect in effects {
            engine.disconnectNodeInput(effect)
            engine.disconnectNodeOutput(effect)
        }

        // Build the chain: Source -> Effects -> Mixer
        // Use nil format to let AVAudioEngine auto-negotiate between nodes.
        // This avoids kAudioUnitErr_FormatNotSupported (-10868) crashes.
        var previousNode: AVAudioNode? = sourceNode

        for (i, effect) in effects.enumerated() {
            if let prev = previousNode {
                if connect(prev, to: effect, engine: engine) {
                    print("   Connected \(type(of: prev)) → effect[\(i)]")
                    previousNode = effect
                } else {
                    print("   ⚠️ Skipped effect[\(i)] connection: source format is not ready")
                    previousNode = nil
                }
            } else {
                // No source yet - effect can't receive input
                // This is okay during async loading; chain will rebuild when the source loads
                print("   ⚠️ Effect[\(i)] has no input source yet")
                previousNode = nil
            }
        }

        // Connect final node to mixer
        if let finalNode = previousNode {
            if connect(finalNode, to: mixer, engine: engine) {
                print("   Connected \(type(of: finalNode)) → mixer")
            } else {
                print("   ⚠️ Skipped mixer connection: source format is not ready")
            }
        } else if !effects.isEmpty {
            print("   ⚠️ No source - effects waiting for input")
        } else {
            print("   ⚠️ No nodes to connect to mixer")
        }

        // Debug: Verify the entire chain is connected
        debugVerifyChain(engine: engine)

        print("🔧 ChannelStrip \(index): Chain rebuild complete")
    }

    private var sourceNode: AVAudioNode? {
        kind == .audioInput ? audioInputNode : instrument
    }

    private func connectionFormat(from node: AVAudioNode) -> AVAudioFormat? {
        if node === audioInputNode {
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                print("   ⚠️ Audio input format not ready: \(format.sampleRate)Hz / \(format.channelCount)ch")
                return nil
            }
            return format
        }
        return nil
    }

    private func connect(_ source: AVAudioNode, to destination: AVAudioNode, engine: AVAudioEngine) -> Bool {
        let format = connectionFormat(from: source)
        if source === audioInputNode, format == nil {
            return false
        }

        engine.connect(source, to: destination, format: format)
        return true
    }
    
    /// Debug helper to verify the audio chain is fully connected
    private func debugVerifyChain(engine: AVAudioEngine) {
        print("   📊 Chain verification for channel \(index):")
        
        // Check instrument output
        if let instrument = instrument {
            let instrOutput = engine.outputConnectionPoints(for: instrument, outputBus: 0)
            if instrOutput.isEmpty {
                print("   ❌ Instrument has NO output connection!")
            } else {
                let targetName = instrOutput.first.map { String(describing: type(of: $0.node ?? mixer)) } ?? "?"
                print("   ✓ Instrument → \(targetName)")
            }
        }
        
        // Check each effect output
        for (i, effect) in effects.enumerated() {
            let effectOutput = engine.outputConnectionPoints(for: effect, outputBus: 0)
            if effectOutput.isEmpty {
                print("   ❌ Effect[\(i)] has NO output connection!")
            } else {
                let targetName = effectOutput.first.map { String(describing: type(of: $0.node ?? mixer)) } ?? "?"
                print("   ✓ Effect[\(i)] → \(targetName)")
            }
        }
        
        // Check mixer input count
        let mixerInputCount = mixer.numberOfInputs
        print("   📥 Mixer has \(mixerInputCount) input bus(es)")
        
        // Check mixer output
        let mixerOutput = engine.outputConnectionPoints(for: mixer, outputBus: 0)
        if mixerOutput.isEmpty {
            print("   ❌ Mixer has NO output to master!")
        } else {
            print("   ✓ Mixer → masterMixer")
        }
    }

    // MARK: - Host Musical Context (Tempo Sync)

    /// Update the musical context (tempo, transport) for all hosted plugins
    /// Note: We only update the values here - the blocks read from these values
    /// and were set once when the AU was loaded. Don't re-apply blocks while
    /// audio is rendering as it causes race conditions.
    func updateMusicalContext(tempo: Double, isPlaying: Bool) {
        hostTempo = tempo
        hostIsPlaying = isPlaying
        print("ChannelStrip \(index): Musical context updated - tempo: \(tempo) BPM, playing: \(isPlaying)")
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
    
    /// Send MIDI note to the instrument (stack-allocated to avoid per-event heap allocation)
    func sendMIDI(noteOn note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard let instrument = instrument else { return }
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let statusByte = 0x90 | (channel & 0x0F)
            var bytes: (UInt8, UInt8, UInt8) = (UInt8(statusByte), note, velocity)
            withUnsafeBytes(of: &bytes) { raw in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
    
    func sendMIDI(noteOff note: UInt8, channel: UInt8 = 0) {
        guard let instrument = instrument else { return }
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            var bytes: (UInt8, UInt8, UInt8) = (0x80 | (channel & 0x0F), note, 0)
            withUnsafeBytes(of: &bytes) { raw in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
    
    func sendMIDI(controlChange cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        guard let instrument = instrument else { return }

        // Check for CC-to-parameter mapping — set the parameter directly
        if let cached = ccParamCache[cc] {
            let normalized = Float(value) / 127.0
            let paramValue = cached.minValue + normalized * cached.range
            cached.param.setValue(paramValue, originator: nil)
        }

        // Also send as raw MIDI CC (some synths do handle certain CCs natively)
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            var bytes: (UInt8, UInt8, UInt8) = (0xB0 | (channel & 0x0F), cc, value)
            withUnsafeBytes(of: &bytes) { raw in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
    
    func sendMIDI(pitchBend lsb: UInt8, msb: UInt8, channel: UInt8 = 0) {
        guard let instrument = instrument else { return }
        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let statusByte = 0xE0 | (channel & 0x0F)
            var bytes: (UInt8, UInt8, UInt8) = (UInt8(statusByte), lsb, msb)
            withUnsafeBytes(of: &bytes) { raw in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
    
    // MARK: - CC Parameter Mapping

    /// Rebuild the CC-to-parameter cache from saved mappings.
    /// Called after instrument load or when mappings change.
    func rebuildCCParamCache() {
        ccParamCache.removeAll()
        guard let paramTree = instrument?.auAudioUnit.parameterTree else { return }

        for mapping in ccParameterMappings {
            if let param = paramTree.parameter(withAddress: mapping.parameterAddress) {
                ccParamCache[UInt8(mapping.cc)] = (
                    param: param,
                    minValue: param.minValue,
                    range: param.maxValue - param.minValue
                )
            }
        }
        print("ChannelStrip \(index): CC param cache rebuilt (\(ccParamCache.count) mappings)")
    }

    /// Get all available parameters from the loaded instrument (for mapping UI)
    func getInstrumentParameters() -> [AUParameterInfo] {
        guard let paramTree = instrument?.auAudioUnit.parameterTree else { return [] }
        return collectParameters(from: paramTree)
    }

    /// Get writable parameters exposed by an effect insert.
    func getEffectParameters(at index: Int) -> [AUParameterInfo] {
        guard effects.indices.contains(index),
              let parameterTree = effects[index].auAudioUnit.parameterTree else { return [] }
        return collectParameters(from: parameterTree).filter(\.isWritable)
    }

    /// Set an effect parameter from a normalized MIDI value. The persistent key path is
    /// preferred; the address only supports older mappings and plugins with stable addresses.
    @discardableResult
    func setEffectParameter(
        at index: Int,
        keyPath: String?,
        fallbackAddress: AUParameterAddress?,
        normalizedValue: Float,
        outputMinimum: Float,
        outputMaximum: Float
    ) -> Bool {
        guard effects.indices.contains(index),
              let parameterTree = effects[index].auAudioUnit.parameterTree else { return false }

        let cacheKey = "\(index):\(keyPath ?? fallbackAddress.map(String.init) ?? "unknown")"
        guard let parameter = effectParameterCache[cacheKey]
                ?? resolveParameter(in: parameterTree, keyPath: keyPath, fallbackAddress: fallbackAddress),
              parameter.flags.contains(.flag_IsWritable) else { return false }
        effectParameterCache[cacheKey] = parameter

        let clampedInput = min(max(normalizedValue, 0), 1)
        let normalizedOutput = outputMinimum + clampedInput * (outputMaximum - outputMinimum)
        let clampedOutput = min(max(normalizedOutput, 0), 1)
        let value = parameter.minValue + clampedOutput * (parameter.maxValue - parameter.minValue)
        parameter.setValue(value, originator: nil)
        return true
    }

    private func resolveParameter(
        in tree: AUParameterTree,
        keyPath: String?,
        fallbackAddress: AUParameterAddress?
    ) -> AUParameter? {
        if let keyPath,
           let parameter = collectParameterNodes(from: tree).first(where: { $0.keyPath == keyPath }) {
            return parameter
        }
        if let fallbackAddress {
            return tree.parameter(withAddress: fallbackAddress)
        }
        return nil
    }

    private func collectParameterNodes(from group: AUParameterGroup) -> [AUParameter] {
        group.children.flatMap { node -> [AUParameter] in
            if let parameter = node as? AUParameter { return [parameter] }
            if let subgroup = node as? AUParameterGroup { return collectParameterNodes(from: subgroup) }
            return []
        }
    }

    private func collectParameters(from group: AUParameterGroup) -> [AUParameterInfo] {
        var result: [AUParameterInfo] = []
        for node in group.children {
            if let param = node as? AUParameter {
                result.append(AUParameterInfo(
                    address: param.address,
                    keyPath: param.keyPath,
                    identifier: param.identifier,
                    displayName: param.displayName,
                    groupName: group.displayName,
                    minValue: param.minValue,
                    maxValue: param.maxValue,
                    unit: param.unitName ?? "",
                    isWritable: param.flags.contains(.flag_IsWritable)
                ))
            } else if let subGroup = node as? AUParameterGroup {
                result.append(contentsOf: collectParameters(from: subGroup))
            }
        }
        return result
    }

    private func collectParameters(from tree: AUParameterTree) -> [AUParameterInfo] {
        var result: [AUParameterInfo] = []
        for node in tree.children {
            if let param = node as? AUParameter {
                result.append(AUParameterInfo(
                    address: param.address,
                    keyPath: param.keyPath,
                    identifier: param.identifier,
                    displayName: param.displayName,
                    groupName: nil,
                    minValue: param.minValue,
                    maxValue: param.maxValue,
                    unit: param.unitName ?? "",
                    isWritable: param.flags.contains(.flag_IsWritable)
                ))
            } else if let group = node as? AUParameterGroup {
                result.append(contentsOf: collectParameters(from: group))
            }
        }
        return result
    }

    /// Add a CC-to-parameter mapping
    func addCCMapping(cc: Int, parameterAddress: AUParameterAddress, parameterName: String) {
        // Remove existing mapping for this CC
        ccParameterMappings.removeAll { $0.cc == cc }
        ccParameterMappings.append(CCParameterMapping(
            cc: cc,
            parameterAddress: parameterAddress,
            parameterName: parameterName
        ))
        rebuildCCParamCache()
    }

    /// Remove a CC mapping
    func removeCCMapping(cc: Int) {
        ccParameterMappings.removeAll { $0.cc == cc }
        ccParamCache.removeValue(forKey: UInt8(cc))
    }

    /// Start observing parameter changes for "learn" mode.
    /// Returns a token that must be passed to stopParameterLearn().
    func startParameterLearn() -> AUParameterObserverToken? {
        guard let paramTree = instrument?.auAudioUnit.parameterTree else { return nil }

        let token = paramTree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async {
                guard let self else { return }
                // Find the parameter info
                if let param = paramTree.parameter(withAddress: address) {
                    self.onParameterLearned?(param.address, param.displayName)
                }
            }
        })
        return token
    }

    func stopParameterLearn(token: AUParameterObserverToken?) {
        guard let token, let paramTree = instrument?.auAudioUnit.parameterTree else { return }
        paramTree.removeParameterObserver(token)
    }

    /// Callback for parameter learn mode
    var onParameterLearned: ((AUParameterAddress, String) -> Void)?

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
                presetData: serializeAUState(effect.auAudioUnit.fullState),
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
                presetData: serializeAUState(instrument.auAudioUnit.fullState),
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
            isChordPadTarget: isChordPadTarget,
            isSingleNoteTarget: isSingleNoteTarget,
            octaveTranspose: octaveTranspose,
            ccParameterMappings: ccParameterMappings
        )
    }
    
    /// Serialize AU fullState dictionary to Data for persistence
    private func serializeAUState(_ state: [String: Any]?) -> Data? {
        guard let state = state else { return nil }
        do {
            return try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
        } catch {
            print("ChannelStrip \(index): Failed to serialize AU state: \(error)")
            return nil
        }
    }
    
    /// Deserialize Data back to AU fullState dictionary
    private func deserializeAUState(_ data: Data?) -> [String: Any]? {
        guard let data = data else { return nil }
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            return plist as? [String: Any]
        } catch {
            print("ChannelStrip \(index): Failed to deserialize AU state: \(error)")
            return nil
        }
    }
    
    /// Restore the instrument's full state (preset) from saved data
    func restoreInstrumentState(_ presetData: Data?) {
        guard let instrument = instrument,
              let state = deserializeAUState(presetData) else { return }
        
        instrument.auAudioUnit.fullState = state
        print("ChannelStrip \(index): Restored instrument preset state")
    }
    
    /// Restore an effect's full state (preset) from saved data
    func restoreEffectState(_ presetData: Data?, at effectIndex: Int) {
        guard effectIndex < effects.count,
              let state = deserializeAUState(presetData) else { return }
        
        effects[effectIndex].auAudioUnit.fullState = state
        print("ChannelStrip \(index): Restored effect[\(effectIndex)] preset state")
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        guard let engine = engine else { return }

        if meterTap {
            mixer.removeTap(onBus: 0)
            meterTap = false
        }

        engine.disconnectNodeInput(mixer)
        engine.disconnectNodeOutput(mixer)

        if kind == .audioInput, let audioInputNode {
            engine.disconnectNodeOutput(audioInputNode)
        }

        // Clear musical context blocks before detaching to avoid dangling references
        if let instrument = instrument {
            instrument.auAudioUnit.musicalContextBlock = nil
            instrument.auAudioUnit.transportStateBlock = nil
            engine.disconnectNodeOutput(instrument)
            engine.detach(instrument)
        }

        for effect in effects {
            effect.auAudioUnit.musicalContextBlock = nil
            effect.auAudioUnit.transportStateBlock = nil
            engine.disconnectNodeInput(effect)
            engine.disconnectNodeOutput(effect)
            engine.detach(effect)
        }

        engine.detach(mixer)

        // Clear references
        self.instrument = nil
        self.instrumentInfo = nil
        self.audioInputNode = nil
        self.effects.removeAll()
        self.effectInfos.removeAll()
        self.effectBypasses.removeAll()
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

// MARK: - CC Parameter Mapping

/// Maps a MIDI CC number to an AUv3 parameter address
struct CCParameterMapping: Codable, Equatable, Identifiable {
    var id = UUID()
    var cc: Int                             // MIDI CC number (0-127)
    var parameterAddress: AUParameterAddress // AUParameter address in the instrument
    var parameterName: String               // Display name for UI
}

/// Info about an available AUParameter (for mapping picker UI)
struct AUParameterInfo: Identifiable {
    let address: AUParameterAddress
    let keyPath: String
    let identifier: String
    let displayName: String
    let groupName: String?
    let minValue: Float
    let maxValue: Float
    let unit: String
    let isWritable: Bool

    var id: String { keyPath }

    var fullDisplayName: String {
        if let group = groupName, !group.isEmpty {
            return "\(group) > \(displayName)"
        }
        return displayName
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
    var isSingleNoteTarget: Bool
    var octaveTranspose: Int
    var ccParameterMappings: [CCParameterMapping] = []
}
