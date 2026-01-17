import Foundation
import Network

/// Bonjour service for Keyframe Mac app discovery
/// Allows iOS app to automatically find and connect to Mac
final class KeyframeDiscovery: ObservableObject {

    static let shared = KeyframeDiscovery()

    // MARK: - Service Configuration

    /// Keyframe uses channel 16 for iOS remote control - won't conflict with instruments on 1-15
    static let remoteControlChannel: UInt8 = 16

    /// Bonjour service type for Keyframe discovery
    private let serviceType = "_keyframe._tcp"

    /// Service name (Mac's computer name)
    private var serviceName: String {
        Host.current().localizedName ?? "Keyframe Mac"
    }

    // MARK: - Published State

    @Published var isAdvertising = false
    @Published var connectedDevices: [String] = []

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
                        print("KeyframeDiscovery: iOS device connected - \(deviceName)")

                        // Send welcome message with MIDI channel info
                        self?.sendWelcome(to: connection)
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

        // Start receiving data
        receiveData(from: connection)
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
    }

    // MARK: - Data Exchange

    private func sendWelcome(to connection: NWConnection) {
        // Send configuration info to iOS
        let info: [String: Any] = [
            "version": 1,
            "name": serviceName,
            "midiChannel": Int(KeyframeDiscovery.remoteControlChannel),
            "capabilities": ["presets", "faders", "mutes"]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: info) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("KeyframeDiscovery: Send error - \(error)")
                }
            })
        }
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleData(data, from: connection)
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                // Continue receiving
                self?.receiveData(from: connection)
            }
        }
    }

    private func handleData(_ data: Data, from connection: NWConnection) {
        // Parse JSON messages from iOS
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return
        }

        switch command {
        case "requestPresets":
            // iOS is requesting preset list
            print("KeyframeDiscovery: iOS requested presets")
            // This would trigger MacMIDIEngine.sendPresetsToiOS()
            NotificationCenter.default.post(name: .keyframePresetSyncRequested, object: nil)

        case "ping":
            // Respond with pong
            let response = ["response": "pong"]
            if let data = try? JSONSerialization.data(withJSONObject: response) {
                connection.send(content: data, completion: .idempotent)
            }

        default:
            print("KeyframeDiscovery: Unknown command - \(command)")
        }
    }

    // MARK: - Broadcast to All Connected Devices

    func broadcastMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

        for connection in connections {
            connection.send(content: data, completion: .idempotent)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let keyframePresetSyncRequested = Notification.Name("keyframePresetSyncRequested")
}
