import Foundation
import Network

/// Bonjour browser for finding Keyframe Mac app
/// Automatically discovers and connects to Mac for remote control
final class KeyframeDiscovery: ObservableObject {

    static let shared = KeyframeDiscovery()

    // MARK: - Service Configuration

    /// Keyframe uses channel 16 for iOS remote control - won't conflict with instruments on 1-15
    static let remoteControlChannel: UInt8 = 16

    /// Bonjour service type for Keyframe discovery
    private let serviceType = "_keyframe._tcp"

    // MARK: - Published State

    @Published var isSearching = false
    @Published var discoveredMacs: [DiscoveredMac] = []
    @Published var connectedMac: DiscoveredMac?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    struct DiscoveredMac: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let endpoint: NWEndpoint

        static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
            lhs.name == rhs.name
        }
    }

    // MARK: - Private State

    private var browser: NWBrowser?
    private var connection: NWConnection?

    // MARK: - Callbacks

    /// Called when preset list is received from Mac
    var onPresetsReceived: (([[String: Any]]) -> Void)?

    /// Called when Mac changes preset
    var onPresetChanged: ((Int) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Browsing

    func startSearching() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                    print("KeyframeDiscovery: Searching for Mac...")
                case .failed(let error):
                    print("KeyframeDiscovery: Browse failed - \(error)")
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredMacs = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return DiscoveredMac(name: name, endpoint: result.endpoint)
                    }
                    return nil
                }

                // Auto-connect if only one Mac found
                if let mac = self?.discoveredMacs.first, self?.discoveredMacs.count == 1, self?.connection == nil {
                    self?.connect(to: mac)
                }

                print("KeyframeDiscovery: Found \(self?.discoveredMacs.count ?? 0) Mac(s)")
            }
        }

        browser?.start(queue: .main)
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    // MARK: - Connection

    func connect(to mac: DiscoveredMac) {
        // Disconnect existing connection
        disconnect()

        connectionStatus = .connecting

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        connection = NWConnection(to: mac.endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connectedMac = mac
                    self?.connectionStatus = .connected
                    print("KeyframeDiscovery: Connected to \(mac.name)")
                    self?.receiveData()
                    self?.requestPresets()

                case .failed(let error):
                    self?.connectionStatus = .error(error.localizedDescription)
                    self?.connectedMac = nil
                    print("KeyframeDiscovery: Connection failed - \(error)")

                case .cancelled:
                    self?.connectionStatus = .disconnected
                    self?.connectedMac = nil

                default:
                    break
                }
            }
        }

        connection?.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connectedMac = nil
        connectionStatus = .disconnected
    }

    // MARK: - Commands

    func requestPresets() {
        sendCommand(["command": "requestPresets"])
    }

    func ping() {
        sendCommand(["command": "ping"])
    }

    private func sendCommand(_ command: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: command) else { return }

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("KeyframeDiscovery: Send error - \(error)")
            }
        })
    }

    // MARK: - Receiving

    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleData(data)
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self?.connectionStatus = .disconnected
                    self?.connectedMac = nil
                }
            } else {
                // Continue receiving
                self?.receiveData()
            }
        }
    }

    private func handleData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            // Welcome message from Mac
            if let version = json["version"] as? Int {
                print("KeyframeDiscovery: Mac version \(version), channel \(json["midiChannel"] ?? "?")")
            }

            // Preset list
            if let presets = json["presets"] as? [[String: Any]] {
                self?.onPresetsReceived?(presets)
            }

            // Preset change notification
            if let presetIndex = json["presetChanged"] as? Int {
                self?.onPresetChanged?(presetIndex)
            }
        }
    }
}
