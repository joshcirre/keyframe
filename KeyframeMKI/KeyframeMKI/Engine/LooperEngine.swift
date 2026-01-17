import AVFoundation
import Combine

/// Looper state machine
enum LooperState: String {
    case empty       // No recording
    case recording   // Currently recording
    case playing     // Loop playing
    case stopped     // Loop exists but stopped
}

/// Loop length modes
enum LooperLengthMode: String, Codable, CaseIterable, Identifiable {
    case free = "Free"           // Stop when you press stop
    case bars4 = "4 Bars"        // Auto-stop at 4 bars
    case bars8 = "8 Bars"        // Auto-stop at 8 bars
    case bars16 = "16 Bars"      // Auto-stop at 16 bars

    var id: String { rawValue }

    var bars: Int? {
        switch self {
        case .free: return nil
        case .bars4: return 4
        case .bars8: return 8
        case .bars16: return 16
        }
    }
}

/// Simple looper that records from master output and plays back in a loop
/// Survives preset changes - only audio engine routes through here
final class LooperEngine: ObservableObject {
    // MARK: - Published State

    @Published var state: LooperState = .empty
    @Published var lengthMode: LooperLengthMode = .free
    @Published var recordingDuration: TimeInterval = 0
    @Published var playbackPosition: TimeInterval = 0
    @Published var volume: Float = 1.0

    // MARK: - Audio Nodes

    private var engine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode?
    private var looperMixer: AVAudioMixerNode?

    // MARK: - Recording State

    private var recordedBuffers: [AVAudioPCMBuffer] = []
    private var recordingStartTime: Date?
    private var loopDuration: TimeInterval = 0
    private var recordingFormat: AVAudioFormat?

    // Timer for bar-based auto-stop
    private var autoStopTimer: Timer?

    // Tempo for bar-based modes
    var currentBPM: Int = 120

    // MARK: - Initialization

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    // MARK: - Setup

    /// Set up looper nodes and connect to the audio graph
    /// Call this after the master mixer is created
    func setup(masterMixer: AVAudioMixerNode) {
        // Create looper nodes
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(mixer)

        // Get format from output (standard format for the engine)
        let format = engine.outputNode.inputFormat(forBus: 0)

        // Connect: player → looperMixer → masterMixer
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: masterMixer, format: format)

        playerNode = player
        looperMixer = mixer
        recordingFormat = format

        print("LooperEngine: Setup complete - format: \(format)")
    }

    // MARK: - Recording

    /// Start recording from the master output
    /// Note: Recording buffers are fed via feedRecordingBuffer() from AudioEngine's existing tap
    func startRecording() {
        guard state == .empty || state == .stopped else {
            print("LooperEngine: Cannot start recording - invalid state")
            return
        }

        // Clear previous recording
        recordedBuffers.removeAll()
        loopDuration = 0
        recordingStartTime = Date()
        recordingDuration = 0

        state = .recording
        print("LooperEngine: Recording started")

        // If bar-based mode, schedule auto-stop
        if let bars = lengthMode.bars {
            scheduleAutoStop(bars: bars)
        }
    }

    /// Feed audio buffer from external tap (called by AudioEngine's metering tap)
    func feedRecordingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .recording else { return }
        processRecordingBuffer(buffer)
    }

    /// Stop recording and prepare the loop
    func stopRecording() {
        guard state == .recording else { return }

        // Cancel any pending auto-stop
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        // Calculate loop duration
        if let startTime = recordingStartTime {
            loopDuration = Date().timeIntervalSince(startTime)
        }

        state = .stopped
        print("LooperEngine: Recording stopped - duration: \(loopDuration)s, buffers: \(recordedBuffers.count)")

        // Immediately start playing if we have content
        if !recordedBuffers.isEmpty {
            startPlayback()
        }
    }

    /// Process incoming audio buffer during recording
    private func processRecordingBuffer(_ buffer: AVAudioPCMBuffer) {
        // Copy buffer (audio thread safe)
        guard let format = buffer.format as AVAudioFormat?,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity) else {
            return
        }

        copy.frameLength = buffer.frameLength

        // Copy float channel data
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(buffer.frameLength)
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Float>.size)
            }
        }

        recordedBuffers.append(copy)

        // Update duration on main thread
        DispatchQueue.main.async { [weak self] in
            if let startTime = self?.recordingStartTime {
                self?.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    // MARK: - Playback

    /// Start loop playback
    func startPlayback() {
        guard state == .stopped, !recordedBuffers.isEmpty else {
            print("LooperEngine: Cannot start playback - no content or wrong state")
            return
        }
        guard let player = playerNode else { return }

        // Create a single buffer from all recorded buffers for smoother looping
        if let combinedBuffer = combineBuffers() {
            // Schedule the combined buffer for looping
            player.scheduleBuffer(combinedBuffer, at: nil, options: .loops)
            player.play()
            state = .playing
            print("LooperEngine: Playback started - loop duration: \(loopDuration)s")
        }
    }

    /// Stop loop playback
    func stopPlayback() {
        guard state == .playing else { return }
        playerNode?.stop()
        state = .stopped
        playbackPosition = 0
        print("LooperEngine: Playback stopped")
    }

    /// Combine all recorded buffers into a single buffer for looping
    private func combineBuffers() -> AVAudioPCMBuffer? {
        guard !recordedBuffers.isEmpty,
              let format = recordingFormat else { return nil }

        // Calculate total frame count
        let totalFrames = recordedBuffers.reduce(0) { $0 + AVAudioFrameCount($1.frameLength) }

        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return nil
        }

        combined.frameLength = totalFrames

        // Copy all buffers into the combined buffer
        var currentFrame: AVAudioFramePosition = 0
        let channelCount = Int(format.channelCount)

        for buffer in recordedBuffers {
            let frameCount = Int(buffer.frameLength)

            if let src = buffer.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<channelCount {
                    let dstOffset = dst[ch].advanced(by: Int(currentFrame))
                    memcpy(dstOffset, src[ch], frameCount * MemoryLayout<Float>.size)
                }
            }

            currentFrame += AVAudioFramePosition(frameCount)
        }

        return combined
    }

    // MARK: - Clear

    /// Clear the loop and reset to empty state
    func clear() {
        // Stop everything
        playerNode?.stop()
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        // Clear buffers
        recordedBuffers.removeAll()
        loopDuration = 0
        recordingDuration = 0
        playbackPosition = 0
        recordingStartTime = nil

        state = .empty
        print("LooperEngine: Cleared")
    }

    // MARK: - Toggle

    /// Toggle recording/playback (main action button)
    func toggle() {
        switch state {
        case .empty:
            startRecording()
        case .recording:
            stopRecording()
        case .playing:
            stopPlayback()
        case .stopped:
            startPlayback()
        }
    }

    // MARK: - Bar-based Timing

    /// Schedule auto-stop for bar-based recording
    private func scheduleAutoStop(bars: Int) {
        let beatsPerBar = 4
        let secondsPerBeat = 60.0 / Double(currentBPM)
        let duration = Double(bars * beatsPerBar) * secondsPerBeat

        print("LooperEngine: Auto-stop scheduled in \(duration)s (\(bars) bars at \(currentBPM) BPM)")

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.state == .recording {
                    self?.stopRecording()
                }
            }
        }
    }

    // MARK: - Volume

    /// Set looper playback volume
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        looperMixer?.outputVolume = volume
    }

    // MARK: - Display Helpers

    /// Formatted duration string
    var durationString: String {
        let duration = state == .recording ? recordingDuration : loopDuration
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Status text for UI
    var statusText: String {
        switch state {
        case .empty:
            return "READY"
        case .recording:
            return "REC"
        case .playing:
            return "PLAY"
        case .stopped:
            return "STOP"
        }
    }
}
