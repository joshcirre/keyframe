import Foundation
import Network

/// Bonjour service for Keyframe Mac app discovery
/// Allows iOS app to automatically find and connect to Mac
final class KeyframeDiscovery: ObservableObject {

    static let shared = KeyframeDiscovery()

    // MARK: - Service Configuration

    /// Bonjour service type for Keyframe discovery
    private let serviceType = "_keyframe._tcp"

    /// Service name (Mac's computer name)
    private var serviceName: String {
        Host.current().localizedName ?? "Keyframe Mac"
    }

    // MARK: - Published State

    @Published var isAdvertising = false
    @Published var connectedDevices: [String] = []
    @Published var hasConnectediOS = false

    // MARK: - Callbacks

    /// Called when iOS requests to select a preset
    var onPresetSelected: ((Int) -> Void)?

    /// Called when iOS changes master volume
    var onMasterVolumeChanged: ((Float) -> Void)?

    // MARK: - Private State

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // MARK: - Initialization

    private init() {
        startAdvertising()
    }

    deinit {
        stopAdvertising()
    }

    // MARK: - Bonjour Advertising

    func startAdvertising() {
        guard listener == nil else { return }

        do {
            // Create TCP listener with Bonjour advertising
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            listener = try NWListener(using: parameters)

            // Advertise via Bonjour
            listener?.service = NWListener.Service(
                name: serviceName,
                type: serviceType
            )

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        if let port = self?.listener?.port {
                            print("KeyframeDiscovery: Advertising on port \(port)")
                        }
                    case .failed(let error):
                        print("KeyframeDiscovery: Failed - \(error)")
                        self?.isAdvertising = false
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.start(queue: .main)
            print("KeyframeDiscovery: Started advertising as '\(serviceName)'")

        } catch {
            print("KeyframeDiscovery: Failed to start - \(error)")
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isAdvertising = false
        hasConnectediOS = false
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    if let endpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, _) = endpoint {
                        let deviceName = "\(host)"
                        self?.connectedDevices.append(deviceName)
                        self?.hasConnectediOS = true
                        print("KeyframeDiscovery: iOS device connected - \(deviceName)")
                    }
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connections.append(connection)
        connection.start(queue: .main)

        // Start receiving length-prefixed messages
        receiveMessage(from: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        // Update connected devices list
        connectedDevices = connections.compactMap { conn in
            if let endpoint = conn.currentPath?.remoteEndpoint,
               case .hostPort(let host, _) = endpoint {
                return "\(host)"
            }
            return nil
        }
        hasConnectediOS = !connections.isEmpty
    }

    // MARK: - Length-Prefixed Message Protocol

    private func receiveMessage(from connection: NWConnection) {
        // Read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, data.count == 4 {
                let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                self.receiveMessageBody(length: Int(length), from: connection)
            } else if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.removeConnection(connection)
                }
            } else {
                self.receiveMessage(from: connection)
            }
        }
    }

    private func receiveMessageBody(length: Int, from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.handleMessage(data, from: connection)
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.removeConnection(connection)
                }
            } else {
                self.receiveMessage(from: connection)
            }
        }
    }

    private func handleMessage(_ data: Data, from connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.processCommand(command, json: json, from: connection)
        }
    }

    private func processCommand(_ command: String, json: [String: Any], from connection: NWConnection) {
        switch command {
        case "requestPresets":
            print("KeyframeDiscovery: iOS requested presets")
            sendPresetsToConnection(connection)

        case "selectPreset":
            if let index = json["index"] as? Int {
                print("KeyframeDiscovery: iOS selected preset \(index)")
                onPresetSelected?(index)
            }

        case "setMasterVolume":
            if let value = json["value"] as? Double {
                print("KeyframeDiscovery: iOS set master volume to \(value)")
                onMasterVolumeChanged?(Float(value))
            }

        case "ping":
            sendMessage(["response": "pong"], to: connection)

        default:
            print("KeyframeDiscovery: Unknown command - \(command)")
        }
    }

    // MARK: - Sending Messages

    private func sendMessage(_ message: [String: Any], to connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message) else { return }

        // Add length prefix
        var length = UInt32(jsonData.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(jsonData)

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("KeyframeDiscovery: Send error - \(error)")
            }
        })
    }

    /// Send presets to a specific connection
    private func sendPresetsToConnection(_ connection: NWConnection) {
        let store = MacSessionStore.shared
        let presets = store.currentSession.presets

        // Convert to simple format for iOS
        let presetData: [[String: Any]] = presets.enumerated().map { index, preset in
            var data: [String: Any] = [
                "id": preset.id.uuidString,
                "name": preset.name,
                "order": index
            ]
            if let songName = preset.songName { data["songName"] = songName }
            if let rootNote = preset.rootNote { data["rootNote"] = rootNote.rawValue }
            if let scale = preset.scale { data["scale"] = scale.rawValue }
            if let bpm = preset.bpm { data["bpm"] = bpm }
            return data
        }

        let message: [String: Any] = [
            "presets": presetData,
            "activePresetIndex": store.currentPresetIndex as Any,
            "masterVolume": Double(store.currentSession.masterVolume)
        ]

        sendMessage(message, to: connection)
    }

    // MARK: - Broadcast to All Connected Devices

    /// Broadcast current state to all connected iOS devices
    func broadcastState() {
        let store = MacSessionStore.shared
        let presets = store.currentSession.presets

        let presetData: [[String: Any]] = presets.enumerated().map { index, preset in
            var data: [String: Any] = [
                "id": preset.id.uuidString,
                "name": preset.name,
                "order": index
            ]
            if let songName = preset.songName { data["songName"] = songName }
            if let rootNote = preset.rootNote { data["rootNote"] = rootNote.rawValue }
            if let scale = preset.scale { data["scale"] = scale.rawValue }
            if let bpm = preset.bpm { data["bpm"] = bpm }
            return data
        }

        let message: [String: Any] = [
            "presets": presetData,
            "activePresetIndex": store.currentPresetIndex as Any,
            "masterVolume": Double(store.currentSession.masterVolume)
        ]

        for connection in connections where connection.state == .ready {
            sendMessage(message, to: connection)
        }
    }

    /// Broadcast just the active preset change
    func broadcastActivePreset(_ index: Int) {
        let message: [String: Any] = ["activePresetIndex": index]
        for connection in connections where connection.state == .ready {
            sendMessage(message, to: connection)
        }
    }

    /// Broadcast master volume change
    func broadcastMasterVolume(_ volume: Float) {
        let message: [String: Any] = ["masterVolume": Double(volume)]
        for connection in connections where connection.state == .ready {
            sendMessage(message, to: connection)
        }
    }
}
