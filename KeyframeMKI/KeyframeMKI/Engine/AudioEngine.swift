import AVFoundation
import AudioToolbox

/// Core audio engine that manages the entire audio graph
/// This is the heart of the Keyframe Performance Engine
final class AudioEngine: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AudioEngine()
    
    // MARK: - Published Properties
    
    @Published private(set) var isRunning = false
    @Published private(set) var cpuUsage: Float = 0.0
    @Published private(set) var peakLevel: Float = -60.0
    @Published var masterVolume: Float = 1.0 {
        didSet {
            masterMixer.outputVolume = masterVolume
        }
    }
    
    // MARK: - Audio Engine
    
    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    
    // MARK: - Channel Strips
    
    private(set) var channelStrips: [ChannelStrip] = []
    let maxChannels = 8
    
    // MARK: - Metering
    
    private var meteringTimer: Timer?
    
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
            // Configure for low-latency playback
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            
            // Request low latency buffer
            try session.setPreferredIOBufferDuration(0.005) // 5ms
            
            // Set preferred sample rate
            try session.setPreferredSampleRate(44100)
            
            try session.setActive(true)
            
            print("AudioEngine: Audio session configured")
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
        
        // Create initial channel strips (4 by default)
        for i in 0..<4 {
            let channel = ChannelStrip(engine: engine, index: i)
            channelStrips.append(channel)
            
            // Connect channel output to master mixer
            connectChannelToMaster(channel)
        }
        
        // Enable metering on master mixer
        masterMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            self?.processMeterData(buffer: buffer)
        }
        
        print("AudioEngine: Audio graph configured with \(channelStrips.count) channels")
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
            try AVAudioSession.sharedInstance().setActive(true)
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
        guard channelStrips.count < maxChannels else {
            print("AudioEngine: Maximum channels reached")
            return nil
        }
        
        let wasRunning = isRunning
        if wasRunning { stop() }
        
        let channel = ChannelStrip(engine: engine, index: channelStrips.count)
        channelStrips.append(channel)
        connectChannelToMaster(channel)
        
        if wasRunning { start() }
        
        return channel
    }
    
    func removeChannel(at index: Int) {
        guard index < channelStrips.count && channelStrips.count > 1 else { return }
        
        let wasRunning = isRunning
        if wasRunning { stop() }
        
        let channel = channelStrips.remove(at: index)
        channel.cleanup()
        
        // Re-index remaining channels
        for (i, ch) in channelStrips.enumerated() {
            ch.index = i
        }
        
        if wasRunning { start() }
    }
    
    func channel(at index: Int) -> ChannelStrip? {
        guard index < channelStrips.count else { return nil }
        return channelStrips[index]
    }
    
    // MARK: - Metering
    
    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCPUUsage()
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }
    
    private func processMeterData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        
        var maxSample: Float = 0
        
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = abs(channelData[channel][frame])
                if sample > maxSample {
                    maxSample = sample
                }
            }
        }
        
        // Convert to dB
        let db = maxSample > 0 ? 20 * log10(maxSample) : -60
        
        DispatchQueue.main.async { [weak self] in
            // Smooth the meter
            self?.peakLevel = max(db, (self?.peakLevel ?? -60) - 1.5)
        }
    }
    
    private func updateCPUUsage() {
        // Approximate CPU usage based on render time
        // This is a simplified approach
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            // This is a rough approximation
            DispatchQueue.main.async { [weak self] in
                self?.cpuUsage = min(100, Float(info.resident_size) / Float(1024 * 1024 * 100))
            }
        }
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
