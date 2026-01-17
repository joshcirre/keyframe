import AVFoundation
import AudioToolbox
import QuartzCore

/// Core audio engine that manages the entire audio graph
/// This is the heart of the Keyframe Performance Engine
final class AudioEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = AudioEngine()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var cpuUsage: Float = 0.0      // DSP load (0-100%)
    @Published private(set) var peakLevel: Float = -60.0
    @Published private(set) var isRestoringPlugins = false
    @Published private(set) var restorationProgress: String = ""

    // Track pending plugin loads
    private var pendingPluginLoads = 0
    private let pluginLoadQueue = DispatchQueue(label: "com.keyframe.pluginLoad")
    @Published var masterVolume: Float = 1.0 {
        didSet {
            masterMixer.outputVolume = masterVolume
        }
    }

    // MARK: - Host Transport / Tempo

    /// Current tempo in BPM (used by hosted plugins for sync)
    @Published private(set) var currentTempo: Double = 120.0

    /// Whether transport is "playing" (for plugin sync)
    @Published private(set) var isTransportPlaying: Bool = true

    /// Current beat position (advances with audio callback)
    private var currentBeatPosition: Double = 0.0
    private var lastRenderTime: Double = 0

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    // MARK: - Channel Strips

    private(set) var channelStrips: [ChannelStrip] = []

    // MARK: - Looper

    private(set) var looper: LooperEngine?
    
    // MARK: - Metering

    private var meteringTimer: Timer?
    private var pendingPeakLevel: Float = -60.0  // Updated from audio thread, read by timer
    
    // MARK: - Initialization
    
    private init() {
        setupAudioSession()
        setupAudioGraph()
        setupNotifications()
    }
    
    deinit {
        stop()
        meteringTimer?.invalidate()
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
            try session.setPreferredIOBufferDuration(0.005) // 5ms

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
        masterMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            self?.processMeterData(buffer: buffer)
        }

        // Set up looper (records from and plays into master mixer)
        let looperEngine = LooperEngine(engine: engine)
        looperEngine.setup(masterMixer: masterMixer)
        self.looper = looperEngine

        print("AudioEngine: Audio graph configured with looper (no default channels)")
    }
    
    private func connectChannelToMaster(_ channel: ChannelStrip) {
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(channel.outputNode, to: masterMixer, format: format)
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
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    start()
                }
            }
        @unknown default:
            break
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
        let wasRunning = isRunning
        if wasRunning { stop() }
        
        let channel = ChannelStrip(engine: engine, index: channelStrips.count)
        channelStrips.append(channel)
        connectChannelToMaster(channel)
        
        if wasRunning { start() }
        
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

            // Restore instrument if configured
            if let instrumentConfig = config.instrument {
                DispatchQueue.main.async {
                    self.restorationProgress = "Loading \(instrumentConfig.name)..."
                }
                print("AudioEngine: Restoring instrument '\(instrumentConfig.name)' on channel \(index)")
                strip.loadInstrument(instrumentConfig.audioComponentDescription) { success, error in
                    if success {
                        print("AudioEngine: Successfully loaded '\(instrumentConfig.name)' on channel \(index)")
                    } else {
                        print("AudioEngine: Failed to load '\(instrumentConfig.name)': \(error?.localizedDescription ?? "unknown")")
                    }
                    markPluginLoaded(instrumentConfig.name, success)
                }
            }

            // Restore effects if configured
            for effectConfig in config.effects {
                print("AudioEngine: Restoring effect '\(effectConfig.name)' on channel \(index)")
                strip.addEffect(effectConfig.audioComponentDescription) { success, error in
                    if success {
                        print("AudioEngine: Successfully loaded effect '\(effectConfig.name)' on channel \(index)")
                    } else {
                        print("AudioEngine: Failed to load effect '\(effectConfig.name)': \(error?.localizedDescription ?? "unknown")")
                    }
                    markPluginLoaded(effectConfig.name, success)
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
        // Update every 250ms for stability and lower overhead
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateDSPLoad()

            // Read the pending peak level (written by audio thread)
            // and apply smoothing/decay (faster decay for longer interval)
            let pending = self.pendingPeakLevel
            self.peakLevel = max(pending, self.peakLevel - 6.0)
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }
    
    private func processMeterData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        // Feed buffer to looper if it's recording
        looper?.feedRecordingBuffer(buffer)

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
