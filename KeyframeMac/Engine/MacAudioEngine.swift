import AVFoundation
import AudioToolbox
import CoreAudio
import QuartzCore

/// Core audio engine for macOS - manages the entire audio graph
/// Adapted from iOS AudioEngine, removing AVAudioSession (not needed on macOS)
final class MacAudioEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = MacAudioEngine()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var cpuUsage: Float = 0.0
    @Published private(set) var peakLevel: Float = -60.0
    @Published private(set) var isRestoringPlugins = false
    @Published private(set) var restorationProgress: String = ""

    /// Set restoration state (for external progress tracking)
    func setRestorationState(_ isRestoring: Bool, progress: String) {
        DispatchQueue.main.async {
            self.isRestoringPlugins = isRestoring
            self.restorationProgress = progress
        }
    }

    // Audio Device Selection
    @Published private(set) var availableOutputDevices: [AudioDeviceInfo] = []
    @Published var selectedOutputDeviceID: AudioDeviceID? {
        didSet {
            if let deviceID = selectedOutputDeviceID {
                setOutputDevice(deviceID)
                saveOutputDeviceSelection()
            }
        }
    }

    private var pendingPluginLoads = 0
    private let pluginLoadQueue = DispatchQueue(label: "com.keyframe.mac.pluginLoad")
    private let outputDeviceKey = "mac.selectedOutputDevice"

    /// Callback when master volume changes (for iOS sync)
    var onMasterVolumeChanged: ((Float) -> Void)?

    @Published var masterVolume: Float = 1.0 {
        didSet {
            masterMixer.outputVolume = masterVolume
            // Broadcast to iOS (if callback is set)
            onMasterVolumeChanged?(masterVolume)
        }
    }

    // MARK: - Host Transport / Tempo

    @Published private(set) var currentTempo: Double = 120.0
    @Published private(set) var isTransportPlaying: Bool = true

    private var currentBeatPosition: Double = 0.0
    private var lastRenderTime: Double = 0

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    // MARK: - Channel Strips

    private(set) var channelStrips: [MacChannelStrip] = []

    // MARK: - Backing Track Player

    private var trackPlayerNode: AVAudioPlayerNode?
    private var trackAudioFile: AVAudioFile?
    private var trackMixerNode: AVAudioMixerNode?
    private var currentBackingTrack: BackingTrack?

    @Published private(set) var isBackingTrackPlaying = false
    @Published private(set) var backingTrackPosition: Double = 0
    @Published private(set) var backingTrackDuration: Double = 0

    private var backingTrackTimer: Timer?

    // MARK: - Metering

    private var meteringTimer: Timer?
    private var pendingPeakLevel: Float = -60.0

    // MARK: - Initialization

    private init() {
        setupAudioGraph()
        refreshOutputDevices()
        restoreOutputDeviceSelection()
    }

    deinit {
        stop()
        meteringTimer?.invalidate()
    }

    // MARK: - Audio Graph Setup

    private func setupAudioGraph() {
        // Attach master mixer to engine
        engine.attach(masterMixer)

        // Connect master mixer to output
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(masterMixer, to: engine.outputNode, format: outputFormat)

        // Enable metering on master mixer
        masterMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            self?.processMeterData(buffer: buffer)
        }

        print("MacAudioEngine: Audio graph configured")
    }

    private func connectChannelToMaster(_ channel: MacChannelStrip) {
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(channel.outputNode, to: masterMixer, format: format)
    }

    // MARK: - Engine Control

    func start() {
        guard !isRunning else { return }

        do {
            try engine.start()
            isRunning = true
            startMetering()
            print("MacAudioEngine: Started")
        } catch {
            print("MacAudioEngine: Failed to start: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }

        engine.stop()
        isRunning = false
        stopMetering()
        print("MacAudioEngine: Stopped")
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start()
        }
    }

    /// Send all notes off to all channels (panic button)
    func panicAllNotesOff() {
        for channel in channelStrips {
            for note: UInt8 in 0...127 {
                channel.sendMIDI(noteOff: note)
            }
        }
        print("MacAudioEngine: Panic - all notes off")
    }

    // MARK: - Channel Management

    func addChannel() -> MacChannelStrip? {
        let wasRunning = isRunning
        if wasRunning { stop() }

        let channel = MacChannelStrip(engine: engine, index: channelStrips.count)
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
        print("MacAudioEngine: Removed channel at index \(index), \(channelStrips.count) remaining")
    }

    func removeAllChannels() {
        let wasRunning = isRunning
        if wasRunning { stop() }

        for channel in channelStrips {
            channel.cleanup()
        }
        channelStrips.removeAll()

        if wasRunning { start() }
        print("MacAudioEngine: Removed all channels")
    }

    func channel(at index: Int) -> MacChannelStrip? {
        guard index < channelStrips.count else { return nil }
        return channelStrips[index]
    }

    // MARK: - Plugin Restoration

    func restorePlugins(from configs: [MacChannelConfiguration], completion: (() -> Void)? = nil) {
        print("MacAudioEngine: Restoring plugins from \(configs.count) channel configs")

        // Ensure we have enough channel strips
        while channelStrips.count < configs.count {
            _ = addChannel()
        }

        // Count total plugins to load
        var totalPlugins = 0
        for (index, config) in configs.enumerated() {
            guard index < channelStrips.count else { continue }
            if config.instrument != nil { totalPlugins += 1 }
            totalPlugins += config.effects.count
        }

        if totalPlugins == 0 {
            print("MacAudioEngine: No plugins to restore")
            completion?()
            return
        }

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
                    print("MacAudioEngine: All plugins restored")
                    completion?()
                }
            }
        }

        for (index, config) in configs.enumerated() {
            guard index < channelStrips.count else { continue }
            let strip = channelStrips[index]

            if let instrumentConfig = config.instrument {
                DispatchQueue.main.async {
                    self.restorationProgress = "Loading \(instrumentConfig.name)..."
                }
                strip.loadInstrument(instrumentConfig.audioComponentDescription) { success, error in
                    markPluginLoaded(instrumentConfig.name, success)
                }
            }

            for effectConfig in config.effects {
                strip.addEffect(effectConfig.audioComponentDescription) { success, error in
                    markPluginLoaded(effectConfig.name, success)
                }
            }
        }
    }

    // MARK: - Tempo / Host Transport

    func setTempo(_ bpm: Double) {
        currentTempo = bpm
        print("MacAudioEngine: Tempo set to \(bpm) BPM")

        for strip in channelStrips {
            strip.updateMusicalContext(tempo: bpm, isPlaying: isTransportPlaying)
        }
    }

    func setTransportPlaying(_ playing: Bool) {
        isTransportPlaying = playing
        if playing {
            currentBeatPosition = 0
        }

        for strip in channelStrips {
            strip.updateMusicalContext(tempo: currentTempo, isPlaying: playing)
        }
    }

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
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateDSPLoad()

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

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        var maxSample: Float = 0
        let stride = max(1, frameCount / 64)

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

        let db = maxSample > 0 ? 20 * log10(maxSample) : -60
        pendingPeakLevel = db
    }

    private func updateDSPLoad() {
        let load = getProcessCPUUsage()
        let smoothed = self.cpuUsage * 0.7 + load * 0.3
        self.cpuUsage = min(100, max(0, smoothed))
    }

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

        let size = vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(task, vm_address_t(bitPattern: threads), size)

        return totalCPU
    }

    // MARK: - Preset Application

    func applyChannelStates(_ states: [MacChannelPresetState]) {
        for state in states {
            if let channel = channelStrips.first(where: { $0.id == state.channelId }) {
                applyStateToChannel(state, channel: channel)
            }
        }
    }

    func applyChannelStates(_ states: [MacChannelPresetState], configs: [MacChannelConfiguration]) {
        for state in states {
            if let configIndex = configs.firstIndex(where: { $0.id == state.channelId }),
               configIndex < channelStrips.count {
                let channel = channelStrips[configIndex]
                applyStateToChannel(state, channel: channel)
            }
        }
    }

    private func applyStateToChannel(_ state: MacChannelPresetState, channel: MacChannelStrip) {
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

    // MARK: - Audio Output Device Selection

    func refreshOutputDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("MacAudioEngine: Failed to get device list size: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            print("MacAudioEngine: Failed to get device list: \(status)")
            return
        }

        var outputDevices: [AudioDeviceInfo] = []

        for deviceID in deviceIDs {
            // Check if device has output channels
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            var outputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &outputAddress, 0, nil, &outputSize)

            if status == noErr && outputSize > 0 {
                let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPtr.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &outputAddress, 0, nil, &outputSize, bufferListPtr)

                if status == noErr {
                    let bufferList = bufferListPtr.pointee
                    let channelCount = bufferList.mBuffers.mNumberChannels

                    if channelCount > 0 {
                        if let name = getDeviceName(deviceID) {
                            let uid = getDeviceUID(deviceID)
                            outputDevices.append(AudioDeviceInfo(
                                id: deviceID,
                                name: name,
                                uid: uid,
                                isOutput: true
                            ))
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.availableOutputDevices = outputDevices
            print("MacAudioEngine: Found \(outputDevices.count) output devices")
        }
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        if status == noErr, let name = name {
            return name as String
        }
        return nil
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        if status == noErr, let uid = uid {
            return uid as String
        }
        return nil
    }

    private func setOutputDevice(_ deviceID: AudioDeviceID) {
        let wasRunning = isRunning
        if wasRunning { stop() }

        do {
            let audioUnit = engine.outputNode.audioUnit!

            var deviceIDVar = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceIDVar,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if status == noErr {
                print("MacAudioEngine: Output device set to ID \(deviceID)")
            } else {
                print("MacAudioEngine: Failed to set output device: \(status)")
            }
        }

        if wasRunning { start() }
    }

    private func saveOutputDeviceSelection() {
        guard let deviceID = selectedOutputDeviceID,
              let device = availableOutputDevices.first(where: { $0.id == deviceID }) else { return }

        UserDefaults.standard.set(device.uid, forKey: outputDeviceKey)
    }

    private func restoreOutputDeviceSelection() {
        guard let savedUID = UserDefaults.standard.string(forKey: outputDeviceKey) else { return }

        // Delay slightly to allow device list to populate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            if let device = self.availableOutputDevices.first(where: { $0.uid == savedUID }) {
                self.selectedOutputDeviceID = device.id
                print("MacAudioEngine: Restored output device '\(device.name)'")
            }
        }
    }

    // MARK: - Backing Track Player

    /// Load a backing track for playback
    func loadBackingTrack(_ track: BackingTrack) {
        stopBackingTrack()

        guard let url = track.resolveBookmark() else {
            print("MacAudioEngine: Failed to resolve backing track bookmark")
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            trackAudioFile = audioFile
            currentBackingTrack = track

            // Calculate duration
            let sampleRate = audioFile.processingFormat.sampleRate
            let frameCount = Double(audioFile.length)
            backingTrackDuration = frameCount / sampleRate

            // Setup player node if needed
            if trackPlayerNode == nil {
                setupTrackPlayer()
            }

            print("MacAudioEngine: Loaded backing track '\(track.name)' (\(String(format: "%.1f", backingTrackDuration))s)")

        } catch {
            print("MacAudioEngine: Failed to load backing track: \(error)")
        }
    }

    /// Load and immediately start playing a backing track
    func loadAndPlayBackingTrack(_ track: BackingTrack) {
        loadBackingTrack(track)
        playBackingTrack()
    }

    private func setupTrackPlayer() {
        let playerNode = AVAudioPlayerNode()
        let mixerNode = AVAudioMixerNode()

        engine.attach(playerNode)
        engine.attach(mixerNode)

        // Connect player -> track mixer -> master mixer
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: masterMixer, format: format)

        trackPlayerNode = playerNode
        trackMixerNode = mixerNode
    }

    /// Start or resume backing track playback
    func playBackingTrack() {
        guard let playerNode = trackPlayerNode,
              let audioFile = trackAudioFile else { return }

        if isBackingTrackPlaying {
            // Pause
            playerNode.pause()
            isBackingTrackPlaying = false
            stopBackingTrackTimer()
        } else {
            // Play
            if playerNode.isPlaying {
                playerNode.play()
            } else {
                // Schedule the file
                playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleTrackPlaybackComplete()
                    }
                }
                playerNode.play()
            }

            isBackingTrackPlaying = true
            startBackingTrackTimer()

            // Apply volume from track settings
            if let track = currentBackingTrack {
                trackMixerNode?.outputVolume = track.volume
            }
        }
    }

    /// Stop backing track playback
    func stopBackingTrack() {
        trackPlayerNode?.stop()
        isBackingTrackPlaying = false
        backingTrackPosition = 0
        stopBackingTrackTimer()
    }

    /// Seek to a position in the backing track
    func seekBackingTrack(to seconds: Double) {
        guard let playerNode = trackPlayerNode,
              let audioFile = trackAudioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(seconds * sampleRate)

        playerNode.stop()

        // Schedule from the new position
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: framePosition,
            frameCount: AVAudioFrameCount(audioFile.length - framePosition),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTrackPlaybackComplete()
            }
        }

        backingTrackPosition = seconds

        if isBackingTrackPlaying {
            playerNode.play()
        }
    }

    private func handleTrackPlaybackComplete() {
        // Check if looping is enabled
        if let track = currentBackingTrack, track.loopEnabled {
            seekBackingTrack(to: 0)
            playBackingTrack()
        } else {
            isBackingTrackPlaying = false
            backingTrackPosition = 0
            stopBackingTrackTimer()
        }
    }

    private func startBackingTrackTimer() {
        backingTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateBackingTrackPosition()
        }
    }

    private func stopBackingTrackTimer() {
        backingTrackTimer?.invalidate()
        backingTrackTimer = nil
    }

    private func updateBackingTrackPosition() {
        guard let playerNode = trackPlayerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let audioFile = trackAudioFile else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        backingTrackPosition = Double(playerTime.sampleTime) / sampleRate
    }

    /// Update backing track volume
    func setBackingTrackVolume(_ volume: Float) {
        trackMixerNode?.outputVolume = volume
        currentBackingTrack?.volume = volume
    }
}

// MARK: - Audio Device Info

struct AudioDeviceInfo: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String?
    let isOutput: Bool

    static func == (lhs: AudioDeviceInfo, rhs: AudioDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Channel Preset State

struct MacChannelPresetState: Codable, Equatable {
    var channelId: UUID
    var volume: Float?
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
