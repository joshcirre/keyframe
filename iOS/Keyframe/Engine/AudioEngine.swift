import AVFoundation
import AudioToolbox
import QuartzCore

/// Core audio engine that manages the entire audio graph
/// This is the heart of the Keyframe Performance Engine
@Observable
@MainActor
final class AudioEngine {

    // MARK: - Singleton

    static let shared = AudioEngine()

    // MARK: - Observable Properties

    private(set) var isRunning = false
    private(set) var cpuUsage: Float = 0.0      // DSP load (0-100%)
    private(set) var peakLevel: Float = -60.0
    private(set) var isRestoringPlugins = false
    private(set) var restorationProgress: String = ""

    // Track pending plugin loads
    private var pendingPluginLoads = 0
    private let pluginLoadQueue = DispatchQueue(label: "com.keyframe.pluginLoad")
    var masterVolume: Float = 1.0 {
        didSet {
            masterMixer.outputVolume = masterVolume
        }
    }

    // MARK: - Host Transport / Tempo

    /// Current tempo in BPM (used by hosted plugins for sync)
    private(set) var currentTempo: Double = 120.0

    /// Whether transport is "playing" (for plugin sync)
    private(set) var isTransportPlaying: Bool = true

    /// Current beat position (advances with audio callback)
    private var currentBeatPosition: Double = 0.0
    private var lastRenderTime: Double = 0

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    // MARK: - Channel Strips

    private(set) var channelStrips: [ChannelStrip] = []
    
    // MARK: - Metering

    private var meteringTimer: Timer?
    private var cpuTimer: Timer?
    nonisolated(unsafe) private var pendingPeakLevel: Float = -60.0  // Updated from audio thread, read by timer
    
    // MARK: - Initialization
    
    private init() {
        setupAudioSession()
        setupAudioGraph()
        setupNotifications()
    }
    
    deinit {
        // Note: Can't call stop() from deinit due to MainActor isolation
        // Timer cleanup handled by ARC
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            // Configure for background audio playback
            // Using .playback category without .mixWithOthers ensures iOS keeps
            // the app running in background as the primary audio source
            try session.setCategory(.playback, mode: .default, options: [])

            // Request low latency buffer
            try session.setPreferredIOBufferDuration(0.012) // 12ms for stability

            // Set preferred sample rate
            try session.setPreferredSampleRate(44100)

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            print("AudioEngine: Audio session configured for background audio")
            print("  Sample Rate: \(session.sampleRate)")
            print("  Buffer Duration: \(session.ioBufferDuration * 1000)ms")

        } catch {
            print("AudioEngine: Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Audio Graph Setup
    
    private func setupAudioGraph() {
        // Attach master mixer to engine
        engine.attach(masterMixer)

        // Connect master mixer to output
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(masterMixer, to: engine.outputNode, format: outputFormat)

        // No default channels - they are created dynamically when added or restored from session

        // Enable metering on master mixer
        masterMixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
            self?.processMeterData(buffer: buffer)
        }

        print("AudioEngine: Audio graph configured (no default channels)")
    }
    
    private func connectChannelToMaster(_ channel: ChannelStrip) {
        // Use nil format to let AVAudioEngine negotiate - more robust for varied plugin chains
        engine.connect(channel.outputNode, to: masterMixer, format: nil)
    }

    /// Verify and fix channel connections to master mixer (call after modifying channel chains)
    func ensureChannelConnections() {
        for (index, channel) in channelStrips.enumerated() {
            let connections = engine.outputConnectionPoints(for: channel.outputNode, outputBus: 0)
            if connections.isEmpty {
                print("🔌 Channel \(index) disconnected from master - reconnecting...")
                engine.connect(channel.outputNode, to: masterMixer, format: nil)
            }
        }
    }

    /// Reconnect ALL channels to master (used after stop/start to restore connections)
    private func reconnectAllChannelsToMaster() {
        for (index, channel) in channelStrips.enumerated() {
            // Rebuild internal chain (Instrument → Effects → Mixer)
            channel.rebuildAudioChain()
            // Connect channel mixer to master using channel's format
            connectChannelToMaster(channel)
            print("🔌 Reconnected channel \(index) to master (rebuilt internal chain)")
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("AudioEngine: Route change - \(reason)")
        
        if reason == .oldDeviceUnavailable {
            // Headphones disconnected, etc.
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
        }
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("AudioEngine: Interruption began")
            stop()
        case .ended:
            print("AudioEngine: Interruption ended")
            // Always try to restart after interruption ends, with retry logic
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartAfterInterruption(retryCount: 0)
            }
        @unknown default:
            break
        }
    }

    private func restartAfterInterruption(retryCount: Int) {
        guard !isRunning else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
            isRunning = true
            startMetering()
            print("AudioEngine: Restarted after interruption (attempt \(retryCount + 1))")
        } catch {
            print("AudioEngine: Failed to restart (attempt \(retryCount + 1)): \(error)")
            // Retry up to 3 times with increasing delay
            if retryCount < 3 {
                let delay = Double(retryCount + 1) * 0.5
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.restartAfterInterruption(retryCount: retryCount + 1)
                }
            }
        }
    }
    
    // MARK: - Engine Control
    
    func start() {
        guard !isRunning else { return }

        do {
            // Ensure audio session is active for background audio
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
            isRunning = true
            startMetering()
            print("AudioEngine: Started")
        } catch {
            print("AudioEngine: Failed to start: \(error)")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        engine.stop()
        isRunning = false
        stopMetering()
        print("AudioEngine: Stopped")
    }
    
    func restart() {
        stop()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start()
        }
    }
    
    // MARK: - Channel Management
    
    func addChannel() -> ChannelStrip? {
        // Debug: Log existing channel states before adding
        print("🎛️ addChannel: Before - \(channelStrips.count) strips exist")
        for (i, strip) in channelStrips.enumerated() {
            print("  [\(i)] midiSource='\(strip.midiSourceName ?? "nil")' midiCh=\(strip.midiChannel)")
        }

        // Create new channel and connect to master (don't stop engine - it breaks AUv3 plugins)
        let channel = ChannelStrip(engine: engine, index: channelStrips.count)
        channelStrips.append(channel)
        connectChannelToMaster(channel)

        // Debug: Log channel states after adding
        print("🎛️ addChannel: After - \(channelStrips.count) strips exist")
        for (i, strip) in channelStrips.enumerated() {
            print("  [\(i)] midiSource='\(strip.midiSourceName ?? "nil")' midiCh=\(strip.midiChannel)")
        }

        return channel
    }
    
    func removeChannel(at index: Int) {
        guard index < channelStrips.count else { return }

        let wasRunning = isRunning
        if wasRunning { stop() }

        let channel = channelStrips.remove(at: index)
        channel.cleanup()

        // Re-index remaining channels
        for (i, ch) in channelStrips.enumerated() {
            ch.index = i
        }

        if wasRunning { start() }
        print("AudioEngine: Removed channel at index \(index), \(channelStrips.count) remaining")
    }

    /// Remove all channels (for session reset)
    func removeAllChannels() {
        let wasRunning = isRunning
        if wasRunning { stop() }

        for channel in channelStrips {
            channel.cleanup()
        }
        channelStrips.removeAll()

        if wasRunning { start() }
        print("AudioEngine: Removed all channels")
    }

    func channel(at index: Int) -> ChannelStrip? {
        guard index < channelStrips.count else { return nil }
        return channelStrips[index]
    }

    /// Restore instruments and effects from saved channel configurations
    func restorePlugins(from configs: [ChannelConfiguration], completion: (() -> Void)? = nil) {
        print("AudioEngine: Restoring plugins from \(configs.count) channel configs, \(channelStrips.count) strips exist")

        // Ensure we have enough channel strips for all configs
        while channelStrips.count < configs.count {
            print("AudioEngine: Adding channel strip to match config count")
            _ = addChannel()
        }

        // Count total plugins to load (only for channels that exist)
        var totalPlugins = 0
        for (index, config) in configs.enumerated() {
            guard index < channelStrips.count else { continue }
            if config.instrument != nil { totalPlugins += 1 }
            totalPlugins += config.effects.count
        }

        // If no plugins to restore, we're done
        if totalPlugins == 0 {
            print("AudioEngine: No plugins to restore")
            completion?()
            return
        }

        // Set loading state
        DispatchQueue.main.async {
            self.isRestoringPlugins = true
            self.restorationProgress = "Loading plugins..."
        }

        pluginLoadQueue.sync {
            pendingPluginLoads = totalPlugins
        }

        var loadedCount = 0

        let markPluginLoaded: (String, Bool) -> Void = { [weak self] name, success in
            guard let self = self else { return }

            self.pluginLoadQueue.sync {
                self.pendingPluginLoads -= 1
                loadedCount += 1
            }

            let remaining = self.pluginLoadQueue.sync { self.pendingPluginLoads }

            DispatchQueue.main.async {
                self.restorationProgress = "Loaded \(loadedCount)/\(totalPlugins): \(name)"
            }

            if remaining == 0 {
                DispatchQueue.main.async {
                    self.isRestoringPlugins = false
                    self.restorationProgress = ""
                    print("AudioEngine: All plugins restored")
                    completion?()
                }
            }
        }

        for (index, config) in configs.enumerated() {
            guard index < channelStrips.count else { continue }
            let strip = channelStrips[index]
            let effectConfigs = config.effects

            // Load instrument FIRST, then effects (effects need instrument to connect to)
            if let instrumentConfig = config.instrument {
                DispatchQueue.main.async {
                    self.restorationProgress = "Loading \(instrumentConfig.name)..."
                }
                print("AudioEngine: Restoring instrument '\(instrumentConfig.name)' on channel \(index)")
                strip.loadInstrument(instrumentConfig.audioComponentDescription) { success, error in
                    if success {
                        print("AudioEngine: Successfully loaded '\(instrumentConfig.name)' on channel \(index)")
                        // Restore instrument preset state
                        strip.restoreInstrumentState(instrumentConfig.presetData)
                    } else {
                        print("AudioEngine: Failed to load '\(instrumentConfig.name)': \(error?.localizedDescription ?? "unknown")")
                    }
                    markPluginLoaded(instrumentConfig.name, success)

                    // Now load effects AFTER instrument is ready
                    for (effectIndex, effectConfig) in effectConfigs.enumerated() {
                        print("AudioEngine: Restoring effect '\(effectConfig.name)' on channel \(index)")
                        strip.addEffect(effectConfig.audioComponentDescription) { success, error in
                            if success {
                                print("AudioEngine: Successfully loaded effect '\(effectConfig.name)' on channel \(index)")
                                // Restore effect preset state
                                strip.restoreEffectState(effectConfig.presetData, at: effectIndex)
                                // Restore bypass state
                                if effectConfig.isBypassed {
                                    strip.setEffectBypassed(true, at: effectIndex)
                                }
                            } else {
                                print("AudioEngine: Failed to load effect '\(effectConfig.name)': \(error?.localizedDescription ?? "unknown")")
                            }
                            markPluginLoaded(effectConfig.name, success)
                        }
                    }
                }
            } else {
                // No instrument - load effects anyway (they just won't have input)
                for (effectIndex, effectConfig) in effectConfigs.enumerated() {
                    print("AudioEngine: Restoring effect '\(effectConfig.name)' on channel \(index) (no instrument)")
                    strip.addEffect(effectConfig.audioComponentDescription) { success, error in
                        if success {
                            print("AudioEngine: Successfully loaded effect '\(effectConfig.name)' on channel \(index)")
                            // Restore effect preset state
                            strip.restoreEffectState(effectConfig.presetData, at: effectIndex)
                            // Restore bypass state
                            if effectConfig.isBypassed {
                                strip.setEffectBypassed(true, at: effectIndex)
                            }
                        } else {
                            print("AudioEngine: Failed to load effect '\(effectConfig.name)': \(error?.localizedDescription ?? "unknown")")
                        }
                        markPluginLoaded(effectConfig.name, success)
                    }
                }
            }
        }
    }

    // MARK: - Tempo / Host Transport

    /// Set the host tempo (BPM) for all hosted plugins
    func setTempo(_ bpm: Double) {
        currentTempo = bpm
        print("AudioEngine: Tempo set to \(bpm) BPM")

        // Update musical context on all channel strips
        for strip in channelStrips {
            strip.updateMusicalContext(tempo: bpm, isPlaying: isTransportPlaying)
        }
    }

    /// Set transport state (playing/stopped)
    func setTransportPlaying(_ playing: Bool) {
        isTransportPlaying = playing
        if playing {
            currentBeatPosition = 0
        }

        for strip in channelStrips {
            strip.updateMusicalContext(tempo: currentTempo, isPlaying: playing)
        }
    }

    /// Create a musical context block for hosted AUs
    func createMusicalContextBlock() -> AUHostMusicalContextBlock {
        return { [weak self] (
            currentTempo: UnsafeMutablePointer<Double>?,
            timeSignatureNumerator: UnsafeMutablePointer<Double>?,
            timeSignatureDenominator: UnsafeMutablePointer<Int>?,
            currentBeatPosition: UnsafeMutablePointer<Double>?,
            sampleOffsetToNextBeat: UnsafeMutablePointer<Int>?,
            currentMeasureDownbeatPosition: UnsafeMutablePointer<Double>?
        ) -> Bool in
            guard let self = self else { return false }

            currentTempo?.pointee = self.currentTempo
            timeSignatureNumerator?.pointee = 4.0
            timeSignatureDenominator?.pointee = 4
            currentBeatPosition?.pointee = self.currentBeatPosition
            sampleOffsetToNextBeat?.pointee = 0
            currentMeasureDownbeatPosition?.pointee = floor(self.currentBeatPosition / 4.0) * 4.0

            return true
        }
    }

    // MARK: - Metering

    private func startMetering() {
        // Consolidated timer for all metering (master + channels)
        // 50ms interval for smooth channel meter animation
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                // Update master level (with slower decay for 50ms interval)
                let pending = self.pendingPeakLevel
                self.peakLevel = max(pending, self.peakLevel - 1.0)

                // Update all channel strip meters
                for channel in self.channelStrips {
                    channel.updateMeterFromEngine()
                }
            }
        }

        // Separate slower timer for CPU load (expensive to compute)
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDSPLoad()
            }
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        cpuTimer?.invalidate()
        cpuTimer = nil
    }
    
    nonisolated private func processMeterData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        var maxSample: Float = 0

        // Use stride for better performance with large buffers
        let stride = max(1, frameCount / 64)  // Sample ~64 points per buffer

        for channel in 0..<channelCount {
            var frame = 0
            while frame < frameCount {
                let sample = abs(channelData[channel][frame])
                if sample > maxSample {
                    maxSample = sample
                }
                frame += stride
            }
        }

        // Convert to dB and store for timer to read (no main thread dispatch!)
        let db = maxSample > 0 ? 20 * log10(maxSample) : -60
        pendingPeakLevel = db
    }

    private func updateDSPLoad() {
        // Get actual CPU usage for this process (reflects audio rendering work)
        let load = getProcessCPUUsage()

        // Smoothing for stable readings
        let smoothed = self.cpuUsage * 0.7 + load * 0.3

        self.cpuUsage = min(100, max(0, smoothed))
    }

    /// Get CPU usage for the current process
    private func getProcessCPUUsage() -> Float {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t()

        let task = mach_task_self_

        guard task_threads(task, &threadsList, &threadsCount) == KERN_SUCCESS,
              let threads = threadsList else {
            return 0
        }

        var totalCPU: Float = 0

        for i in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let result = withUnsafeMutablePointer(to: &threadInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) { intPtr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &threadInfoCount)
                }
            }

            if result == KERN_SUCCESS && threadInfo.flags != TH_FLAGS_IDLE {
                totalCPU += Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE) * 100.0
            }
        }

        // Deallocate the thread list
        let size = vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(task, vm_address_t(bitPattern: threads), size)

        return totalCPU
    }
    
    // MARK: - Preset Application
    
    /// Apply a song's channel states directly (no MIDI CC needed!)
    func applyChannelStates(_ states: [ChannelPresetState]) {
        for state in states {
            if let channel = channelStrips.first(where: { $0.id == state.channelId }) {
                applyStateToChannel(state, channel: channel)
            }
        }
    }
    
    /// Apply channel states by matching config IDs (for when ChannelStrip IDs don't match)
    func applyChannelStates(_ states: [ChannelPresetState], configs: [ChannelConfiguration]) {
        for state in states {
            // Find the config index that matches this state's channelId
            if let configIndex = configs.firstIndex(where: { $0.id == state.channelId }),
               configIndex < channelStrips.count {
                let channel = channelStrips[configIndex]
                applyStateToChannel(state, channel: channel)
                print("Applied preset to channel \(configIndex): vol=\(state.volume ?? -1), mute=\(state.muted ?? false)")
            }
        }
    }
    
    private func applyStateToChannel(_ state: ChannelPresetState, channel: ChannelStrip) {
        if let volume = state.volume {
            channel.volume = volume
        }
        if let pan = state.pan {
            channel.pan = pan
        }
        if let muted = state.muted {
            channel.isMuted = muted
        }
        if let bypasses = state.effectBypasses {
            channel.applyEffectBypasses(bypasses)
        }
    }
}

// MARK: - Channel Preset State

/// Represents the state of a channel for a preset/song
struct ChannelPresetState: Codable, Equatable {
    var channelId: UUID
    var volume: Float?       // nil = don't change
    var pan: Float?
    var muted: Bool?
    var effectBypasses: [Bool]?
    
    init(channelId: UUID, volume: Float? = nil, pan: Float? = nil, muted: Bool? = nil, effectBypasses: [Bool]? = nil) {
        self.channelId = channelId
        self.volume = volume
        self.pan = pan
        self.muted = muted
        self.effectBypasses = effectBypasses
    }
}
