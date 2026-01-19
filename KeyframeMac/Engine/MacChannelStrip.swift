import AVFoundation
import AudioToolbox
import AppKit
import CoreAudioKit

/// Represents a single channel strip with instrument, effects, and mixing controls
/// Adapted from iOS ChannelStrip, using AppKit for plugin UI hosting
final class MacChannelStrip: ObservableObject, Identifiable {

    // MARK: - Properties

    let id = UUID()
    var index: Int
    var name: String

    // MARK: - Audio Nodes

    private weak var engine: AVAudioEngine?
    private let mixer = AVAudioMixerNode()

    /// The instrument AU (synthesizer/sampler)
    private(set) var instrument: AVAudioUnit? {
        didSet { objectWillChange.send() }
    }
    var instrumentInfo: MacAUInfo?

    /// Insert effects chain (up to 4)
    private(set) var effects: [AVAudioUnit] = [] {
        didSet { objectWillChange.send() }
    }
    var effectInfos: [MacAUInfo] = []
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

    @Published var midiChannel: Int = 0  // 0 = omni
    @Published var midiSourceName: String? = nil
    @Published var scaleFilterEnabled: Bool = false
    @Published var isChordPadTarget: Bool = false

    // MARK: - Spillover (smooth preset transitions)

    /// Set of currently active (held) MIDI notes
    private(set) var activeNotes: Set<UInt8> = []

    /// Pending volume to apply when all notes release
    var pendingVolume: Float?

    /// Pending mute state to apply when all notes release
    var pendingMute: Bool?

    /// Pending pan to apply when all notes release
    var pendingPan: Float?

    /// Check if this channel has notes being held
    var hasActiveNotes: Bool { !activeNotes.isEmpty }

    /// Check if there are pending state changes
    var hasPendingChanges: Bool {
        pendingVolume != nil || pendingMute != nil || pendingPan != nil
    }

    // MARK: - Metering

    @Published var peakLevel: Float = -60.0
    private var meterTap: Bool = false
    private var pendingPeakLevel: Float = -60.0
    private var meterUpdateTimer: Timer?

    // MARK: - State

    var isInstrumentLoaded: Bool { instrument != nil }
    @Published private(set) var isLoading: Bool = false

    // MARK: - Host Musical Context

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

        // NOTE: Metering tap is installed lazily when instrument is loaded
        // to avoid overhead on empty channels. See installMeteringTapIfNeeded()

        // Timer to read pending meter value (200ms = 5Hz to reduce CPU load)
        // Only updates if we have a metering tap installed
        meterUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.meterTap else { return }
            let pending = self.pendingPeakLevel
            let newLevel = max(pending, self.peakLevel - 6.0)
            // Only update if changed significantly to reduce SwiftUI updates
            if abs(self.peakLevel - newLevel) > 2.0 {
                self.peakLevel = newLevel.isFinite ? newLevel : -60
            }
        }
    }

    /// Install metering tap only when needed (when instrument is loaded)
    private func installMeteringTapIfNeeded() {
        guard !meterTap, let engine = engine else { return }

        let format = mixer.outputFormat(forBus: 0)
        if format.sampleRate > 0 {
            mixer.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.processMeterData(buffer)
            }
            meterTap = true
            print("MacChannelStrip \(index): Installed metering tap")
        }
    }

    /// Remove metering tap when instrument is unloaded
    private func removeMeteringTap() {
        guard meterTap else { return }
        mixer.removeTap(onBus: 0)
        meterTap = false
        peakLevel = -60
    }

    private func processMeterData(_ buffer: AVAudioPCMBuffer) {
        // Skip processing if muted (no audio to meter)
        guard !isMuted else {
            pendingPeakLevel = -60
            return
        }

        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        var maxSample: Float = 0

        // Sample every 32nd frame for efficiency (still accurate enough for meters)
        let stride = max(1, frameCount / 32)
        var frame = 0
        while frame < frameCount {
            let sample = abs(channelData[0][frame])
            if sample > maxSample {
                maxSample = sample
            }
            frame += stride
        }

        let db: Float
        if maxSample > 0.0001 && maxSample.isFinite {  // Threshold to avoid log(0)
            db = 20 * log10(maxSample)
        } else {
            db = -60
        }
        pendingPeakLevel = db.isFinite ? db : -60
    }

    // MARK: - Instrument Loading

    func loadInstrument(_ description: AudioComponentDescription, completion: @escaping (Bool, Error?) -> Void) {
        guard let engine = engine else {
            print("MacChannelStrip \(index): loadInstrument failed - no engine")
            completion(false, NSError(domain: "MacChannelStrip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not available"]))
            return
        }

        print("MacChannelStrip \(index): Loading instrument type=\(description.componentType) subtype=\(description.componentSubType)")
        isLoading = true
        unloadInstrument()

        AVAudioUnit.instantiate(with: description, options: []) { [weak self] audioUnit, error in
            guard let self = self else {
                print("MacChannelStrip: loadInstrument - self was deallocated")
                return
            }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    print("MacChannelStrip \(self.index): Failed to load instrument: \(error)")
                    completion(false, error)
                    return
                }

                guard let audioUnit = audioUnit else {
                    print("MacChannelStrip \(self.index): Instrument AudioUnit is nil")
                    completion(false, NSError(domain: "MacChannelStrip", code: 2, userInfo: [NSLocalizedDescriptionKey: "AudioUnit is nil"]))
                    return
                }

                self.instrument = audioUnit
                engine.attach(audioUnit)
                print("MacChannelStrip \(self.index): Attached instrument to engine")

                // Verify scheduleMIDIEventBlock is available
                if audioUnit.auAudioUnit.scheduleMIDIEventBlock != nil {
                    print("MacChannelStrip \(self.index): scheduleMIDIEventBlock is available")
                } else {
                    print("MacChannelStrip \(self.index): WARNING - scheduleMIDIEventBlock is nil!")
                }

                self.applyMusicalContext(to: audioUnit.auAudioUnit)
                self.rebuildAudioChain()

                // Install metering tap now that we have an instrument
                self.installMeteringTapIfNeeded()

                print("MacChannelStrip \(self.index): Loaded instrument successfully")
                completion(true, nil)
            }
        }
    }

    func unloadInstrument() {
        guard let instrument = instrument, let engine = engine else { return }

        // Close any open plugin window for this channel's instrument
        // This ensures the window is recreated with the new instrument's UI
        PluginWindowManager.shared.closeWindow(id: "instrument-\(id)")

        instrument.auAudioUnit.musicalContextBlock = nil
        instrument.auAudioUnit.transportStateBlock = nil

        engine.detach(instrument)
        self.instrument = nil
        self.instrumentInfo = nil

        // Remove metering tap when no instrument
        removeMeteringTap()

        rebuildAudioChain()
    }

    // MARK: - Effects Chain

    func addEffect(_ description: AudioComponentDescription, completion: @escaping (Bool, Error?) -> Void) {
        guard let engine = engine else {
            completion(false, NSError(domain: "MacChannelStrip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine not available"]))
            return
        }

        guard effects.count < maxEffects else {
            completion(false, NSError(domain: "MacChannelStrip", code: 3, userInfo: [NSLocalizedDescriptionKey: "Maximum effects reached"]))
            return
        }

        isLoading = true

        AVAudioUnit.instantiate(with: description, options: []) { [weak self] audioUnit, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    print("MacChannelStrip \(self.index): Failed to load effect: \(error)")
                    completion(false, error)
                    return
                }

                guard let audioUnit = audioUnit else {
                    completion(false, NSError(domain: "MacChannelStrip", code: 2, userInfo: [NSLocalizedDescriptionKey: "AudioUnit is nil"]))
                    return
                }

                self.effects.append(audioUnit)
                engine.attach(audioUnit)

                self.applyMusicalContext(to: audioUnit.auAudioUnit)
                self.rebuildAudioChain()

                print("MacChannelStrip \(self.index): Added effect (\(self.effects.count) total)")
                completion(true, nil)
            }
        }
    }

    func removeEffect(at index: Int) {
        guard index < effects.count, let engine = engine else { return }

        // Close any open plugin window for this effect
        PluginWindowManager.shared.closeWindow(id: "effect-\(id)-\(index)")

        let effect = effects.remove(at: index)
        if index < effectInfos.count {
            effectInfos.remove(at: index)
        }

        effect.auAudioUnit.musicalContextBlock = nil
        effect.auAudioUnit.transportStateBlock = nil

        engine.detach(effect)
        rebuildAudioChain()
    }

    func setEffectBypassed(_ bypassed: Bool, at index: Int) {
        guard index < effects.count else { return }
        effects[index].auAudioUnit.shouldBypassEffect = bypassed
    }

    func applyEffectBypasses(_ bypasses: [Bool]) {
        for (index, bypassed) in bypasses.enumerated() {
            if index < effects.count {
                effects[index].auAudioUnit.shouldBypassEffect = bypassed
            }
        }
    }

    // MARK: - Audio Chain Management

    private func rebuildAudioChain() {
        guard let engine = engine else {
            print("MacChannelStrip \(index): rebuildAudioChain failed - no engine")
            return
        }

        // Disconnect all existing connections
        if let instrument = instrument {
            engine.disconnectNodeOutput(instrument)
        }
        for effect in effects {
            engine.disconnectNodeOutput(effect)
        }
        engine.disconnectNodeInput(mixer)

        let format = engine.outputNode.inputFormat(forBus: 0)
        print("MacChannelStrip \(index): rebuildAudioChain with format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Build the chain: Instrument -> Effects -> Mixer
        var previousNode: AVAudioNode? = instrument

        for effect in effects {
            if let prev = previousNode {
                engine.connect(prev, to: effect, format: format)
                print("MacChannelStrip \(index): Connected \(type(of: prev)) -> \(type(of: effect))")
            }
            previousNode = effect
        }

        if let finalNode = previousNode {
            engine.connect(finalNode, to: mixer, format: format)
            print("MacChannelStrip \(index): Connected \(type(of: finalNode)) -> mixer")
        } else {
            print("MacChannelStrip \(index): No instrument to connect")
        }
    }

    // MARK: - Host Musical Context

    func updateMusicalContext(tempo: Double, isPlaying: Bool) {
        hostTempo = tempo
        hostIsPlaying = isPlaying
    }

    func applyMusicalContextToAllAUs() {
        if let instrument = instrument {
            applyMusicalContext(to: instrument.auAudioUnit)
        }
        for effect in effects {
            applyMusicalContext(to: effect.auAudioUnit)
        }
    }

    private func applyMusicalContext(to au: AUAudioUnit) {
        au.musicalContextBlock = { [weak self] (
            currentTempo: UnsafeMutablePointer<Double>?,
            timeSignatureNumerator: UnsafeMutablePointer<Double>?,
            timeSignatureDenominator: UnsafeMutablePointer<Int>?,
            currentBeatPosition: UnsafeMutablePointer<Double>?,
            sampleOffsetToNextBeat: UnsafeMutablePointer<Int>?,
            currentMeasureDownbeatPosition: UnsafeMutablePointer<Double>?
        ) -> Bool in
            guard let self = self else { return false }

            currentTempo?.pointee = self.hostTempo
            timeSignatureNumerator?.pointee = 4.0
            timeSignatureDenominator?.pointee = 4
            currentBeatPosition?.pointee = 0.0
            sampleOffsetToNextBeat?.pointee = 0
            currentMeasureDownbeatPosition?.pointee = 0.0

            return true
        }

        au.transportStateBlock = { [weak self] (
            transportStateFlags: UnsafeMutablePointer<AUHostTransportStateFlags>?,
            currentSamplePosition: UnsafeMutablePointer<Double>?,
            cycleStartBeatPosition: UnsafeMutablePointer<Double>?,
            cycleEndBeatPosition: UnsafeMutablePointer<Double>?
        ) -> Bool in
            guard let self = self else { return false }

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
    }

    // MARK: - MIDI Handling

    func sendMIDI(noteOn note: UInt8, velocity: UInt8) {
        guard let instrument = instrument else { return }

        // Track active note for spillover
        activeNotes.insert(note)

        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let data: [UInt8] = [0x90, note, velocity]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }
    }

    func sendMIDI(noteOff note: UInt8) {
        guard let instrument = instrument else { return }

        // Track note release for spillover
        activeNotes.remove(note)

        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            let data: [UInt8] = [0x80, note, 0]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }

        // Apply pending state changes when all notes are released
        if activeNotes.isEmpty && hasPendingChanges {
            applyPendingChanges()
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

    func sendMIDI(pitchBend lsb: UInt8, msb: UInt8) {
        guard let instrument = instrument else { return }

        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            // Pitch bend: 0xE0 + channel, LSB, MSB
            let data: [UInt8] = [0xE0, lsb, msb]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }
    }

    /// Send all notes off (MIDI panic)
    func sendAllNotesOff() {
        guard let instrument = instrument else { return }

        if let midiBlock = instrument.auAudioUnit.scheduleMIDIEventBlock {
            // CC 123 = All Notes Off
            let data: [UInt8] = [0xB0, 123, 0]
            data.withUnsafeBufferPointer { bufferPointer in
                midiBlock(AUEventSampleTimeImmediate, 0, 3, bufferPointer.baseAddress!)
            }
        }

        activeNotes.removeAll()

        // Apply any pending changes immediately
        if hasPendingChanges {
            applyPendingChanges()
        }
    }

    // MARK: - Spillover State Management

    /// Apply state changes with spillover support
    /// If notes are active, queue changes; otherwise apply immediately
    func applyStateWithSpillover(volume: Float? = nil, pan: Float? = nil, mute: Bool? = nil, spilloverEnabled: Bool = true) {
        if spilloverEnabled && hasActiveNotes {
            // Queue changes for when notes release
            if let v = volume { pendingVolume = v }
            if let p = pan { pendingPan = p }
            if let m = mute { pendingMute = m }
            print("MacChannelStrip \(index): Queued state changes (notes active)")
        } else {
            // Apply immediately
            if let v = volume { self.volume = v }
            if let p = pan { self.pan = p }
            if let m = mute { self.isMuted = m }
        }
    }

    /// Apply any pending state changes
    private func applyPendingChanges() {
        if let v = pendingVolume {
            self.volume = v
            pendingVolume = nil
        }
        if let p = pendingPan {
            self.pan = p
            pendingPan = nil
        }
        if let m = pendingMute {
            self.isMuted = m
            pendingMute = nil
        }
        print("MacChannelStrip \(index): Applied pending state changes")
    }

    /// Clear any pending state changes without applying
    func clearPendingChanges() {
        pendingVolume = nil
        pendingPan = nil
        pendingMute = nil
    }

    // MARK: - Plugin UI (macOS)

    /// Get the view controller for the instrument's UI
    func getInstrumentViewController(completion: @escaping (NSViewController?) -> Void) {
        guard let instrument = instrument else {
            completion(nil)
            return
        }

        instrument.auAudioUnit.requestViewController { viewController in
            DispatchQueue.main.async {
                completion(viewController as? NSViewController)
            }
        }
    }

    /// Get the view controller for an effect's UI
    func getEffectViewController(at index: Int, completion: @escaping (NSViewController?) -> Void) {
        guard index < effects.count else {
            completion(nil)
            return
        }

        effects[index].auAudioUnit.requestViewController { viewController in
            DispatchQueue.main.async {
                completion(viewController as? NSViewController)
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        guard let engine = engine else { return }

        meterUpdateTimer?.invalidate()
        meterUpdateTimer = nil

        if meterTap {
            mixer.removeTap(onBus: 0)
        }

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

        self.instrument = nil
        self.effects.removeAll()
    }

    // MARK: - State Restoration

    func restoreInstrumentState(_ data: Data) {
        guard let instrument = instrument else { return }

        do {
            let state = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSArray.self], from: data)
            if let dict = state as? [String: Any] {
                try instrument.auAudioUnit.fullState = dict
                print("MacChannelStrip: Restored instrument state")
            }
        } catch {
            print("MacChannelStrip: Failed to restore instrument state: \(error)")
        }
    }

    func restoreEffectState(_ data: Data, at index: Int) {
        guard index < effects.count else { return }
        let effect = effects[index]

        do {
            let state = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSArray.self], from: data)
            if let dict = state as? [String: Any] {
                try effect.auAudioUnit.fullState = dict
                print("MacChannelStrip: Restored effect \(index) state")
            }
        } catch {
            print("MacChannelStrip: Failed to restore effect state: \(error)")
        }
    }

    func saveInstrumentState() -> Data? {
        guard let instrument = instrument else { return nil }

        do {
            if let state = instrument.auAudioUnit.fullState {
                return try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false)
            }
        } catch {
            print("MacChannelStrip: Failed to save instrument state: \(error)")
        }
        return nil
    }

    func saveEffectState(at index: Int) -> Data? {
        guard index < effects.count else { return nil }
        let effect = effects[index]

        do {
            if let state = effect.auAudioUnit.fullState {
                return try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false)
            }
        } catch {
            print("MacChannelStrip: Failed to save effect state: \(error)")
        }
        return nil
    }
}

// MARK: - AU Info

struct MacAUInfo: Codable, Equatable {
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
