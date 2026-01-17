import Foundation
import Network
import Combine

/// Represents a preset synced from the Mac app
struct RemotePreset: Identifiable, Equatable {
    let id: UUID
    let name: String
    let songName: String?
    let rootNote: Int?
    let scale: String?
    let bpm: Int?
    let order: Int

    /// Initialize from JSON dictionary (handles type mismatches)
    init?(from dict: [String: Any]) {
        // ID can be String (from Mac) - convert to UUID
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        guard let name = dict["name"] as? String else { return nil }
        guard let order = dict["order"] as? Int else { return nil }

        self.id = id
        self.name = name
        self.order = order
        self.songName = dict["songName"] as? String
        self.rootNote = dict["rootNote"] as? Int
        self.scale = dict["scale"] as? String
        // BPM can be Int or Double from Mac
        if let bpmInt = dict["bpm"] as? Int {
            self.bpm = bpmInt
        } else if let bpmDouble = dict["bpm"] as? Double {
            self.bpm = Int(bpmDouble)
        } else {
            self.bpm = nil
        }
    }
}

/// Connection state for the remote
enum RemoteConnectionState: Equatable {
    case disconnected
    case searching
    case found(name: String)
    case connecting(name: String)
    case connected(name: String)
    case error(String)
}

/// Handles Bonjour discovery and TCP connection to Mac
final class KeyframeRemote: ObservableObject {

    static let shared = KeyframeRemote()

    // MARK: - Published State

    @Published var connectionState: RemoteConnectionState = .disconnected
    @Published var presets: [RemotePreset] = []
    @Published var activePresetIndex: Int?
    @Published var masterVolume: Float = 1.0
    @Published var macName: String?

    // MARK: - Private State

    private let serviceType = "_keyframe._tcp"
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var discoveredEndpoint: NWEndpoint?
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start searching for Mac
    func startSearching() {
        guard case .disconnected = connectionState else { return }

        connectionState = .searching
        startBrowsing()
    }

    /// Stop searching and disconnect
    func disconnect() {
        stopBrowsing()
        connection?.cancel()
        connection = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil

        connectionState = .disconnected
        presets = []
        activePresetIndex = nil
        macName = nil
    }

    /// Connect to a discovered Mac
    func connect() {
        guard let endpoint = discoveredEndpoint else { return }

        if case .found(let name) = connectionState {
            connectionState = .connecting(name: name)
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleConnectionState(state)
            }
        }

        connection?.start(queue: .main)
    }

    /// Select a preset (sends command to Mac)
    func selectPreset(at index: Int) {
        guard connection?.state == .ready else { return }

        let command: [String: Any] = [
            "command": "selectPreset",
            "index": index
        ]
        sendCommand(command)

        // Optimistically update local state
        activePresetIndex = index
    }

    /// Set master volume (sends command to Mac)
    func setMasterVolume(_ volume: Float) {
        guard connection?.state == .ready else { return }

        let command: [String: Any] = [
            "command": "setMasterVolume",
            "value": volume
        ]
        sendCommand(command)

        // Update local state
        masterVolume = volume
    }

    // MARK: - Bonjour Browsing

    private func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("KeyframeRemote: Browser ready")
                case .failed(let error):
                    print("KeyframeRemote: Browser failed - \(error)")
                    self?.connectionState = .error("Search failed")
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.handleBrowseResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        // Find first available Keyframe service
        if let result = results.first {
            switch result.endpoint {
            case .service(let name, _, _, _):
                discoveredEndpoint = result.endpoint
                macName = name
                print("KeyframeRemote: Found '\(name)' - auto-connecting...")

                // Auto-connect immediately when Mac is found
                connectionState = .connecting(name: name)
                connect()
            default:
                break
            }
        } else if case .searching = connectionState {
            // No services found yet, stay in searching state
        }
    }

    // MARK: - Connection Handling

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            let name = macName ?? "Mac"
            connectionState = .connected(name: name)
            print("KeyframeRemote: Connected to '\(name)'")

            // Stop browsing once connected
            stopBrowsing()

            // Start receiving data
            receiveData()

            // Request presets
            requestPresets()

            // Start ping timer
            startPingTimer()

        case .failed(let error):
            print("KeyframeRemote: Connection failed - \(error)")
            connectionState = .error("Connection failed")
            scheduleReconnect()

        case .cancelled:
            print("KeyframeRemote: Connection cancelled")

        case .waiting(let error):
            print("KeyframeRemote: Waiting - \(error)")

        default:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.startSearching()
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    // MARK: - Data Exchange

    private func requestPresets() {
        let command: [String: Any] = ["command": "requestPresets"]
        sendCommand(command)
    }

    private func sendPing() {
        let command: [String: Any] = ["command": "ping"]
        sendCommand(command)
    }

    private func sendCommand(_ command: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              connection?.state == .ready else { return }

        // Add length prefix for message framing
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        connection?.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("KeyframeRemote: Send error - \(error)")
            }
        })
    }

    private func receiveData() {
        // First read the 4-byte length prefix
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, data.count == 4 {
                let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                self.receiveMessage(length: Int(length))
            } else if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.handleDisconnect()
                }
            } else {
                // Continue receiving
                self.receiveData()
            }
        }
    }

    private func receiveMessage(length: Int) {
        connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.handleMessage(data)
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.handleDisconnect()
                }
            } else {
                // Continue receiving
                self.receiveData()
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.processMessage(json)
        }
    }

    private func processMessage(_ json: [String: Any]) {
        // Handle preset sync
        if let presetsData = json["presets"] as? [[String: Any]] {
            let decoded = presetsData.compactMap { RemotePreset(from: $0) }
            presets = decoded.sorted { $0.order < $1.order }
            print("KeyframeRemote: Received \(presets.count) presets")
        }

        // Handle active preset update
        if let index = json["activePresetIndex"] as? Int {
            activePresetIndex = index
        }

        // Handle master volume update
        if let volume = json["masterVolume"] as? Double {
            masterVolume = Float(volume)
        }

        // Handle pong
        if let response = json["response"] as? String, response == "pong" {
            // Connection is alive
        }
    }

    private func handleDisconnect() {
        connection = nil
        pingTimer?.invalidate()
        pingTimer = nil

        if case .connected = connectionState {
            connectionState = .error("Disconnected")
            scheduleReconnect()
        }
    }
}
