import Foundation
import Network
import UIKit

/// Advertises the local iOS performance engine so another iPhone/iPad can control it.
@Observable
@MainActor
final class KeyframeRemoteHost {

    static let shared = KeyframeRemoteHost()

    private(set) var isAdvertising = false
    private(set) var connectedDeviceCount = 0

    var onPresetSelected: ((Int) -> Void)?
    var onMasterVolumeChanged: ((Float) -> Void)?

    private let serviceType = "_keyframe._tcp"
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    private var serviceName: String {
        let device = UIDevice.current
        let idiom = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "Keyframe \(idiom) - \(device.name)"
    }

    private init() {}

    func startAdvertising() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: serviceName, type: serviceType)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            self.listener = listener
            listener.start(queue: .main)
            print("KeyframeRemoteHost: Started advertising as '\(serviceName)'")
        } catch {
            print("KeyframeRemoteHost: Failed to start - \(error)")
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isAdvertising = false
        connectedDeviceCount = 0
    }

    func broadcastState() {
        let state = buildStateMessage()
        sendMessageToReadyConnections(state)
    }

    func broadcastActivePreset(_ index: Int?) {
        var message: [String: Any] = [:]
        if let index {
            message["activePresetIndex"] = index
        } else {
            message["activePresetIndex"] = NSNull()
        }
        sendMessageToReadyConnections(message)
    }

    func broadcastMasterVolume(_ volume: Float) {
        sendMessageToReadyConnections(["masterVolume": Double(volume)])
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isAdvertising = true
            if let port = listener?.port {
                print("KeyframeRemoteHost: Advertising on port \(port)")
            }
        case .failed(let error):
            print("KeyframeRemoteHost: Listener failed - \(error)")
            isAdvertising = false
        case .cancelled:
            isAdvertising = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        updateConnectionCount()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let connection else { return }
                switch state {
                case .ready:
                    print("KeyframeRemoteHost: Remote connected")
                    self?.sendMessage(self?.buildStateMessage() ?? [:], to: connection)
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receiveMessage(from: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        updateConnectionCount()
    }

    private func updateConnectionCount() {
        connectedDeviceCount = connections.filter { $0.state == .ready || $0.state == .preparing }.count
    }

    private func receiveMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            if let data, data.count == 4 {
                let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                Task { @MainActor in
                    self.receiveMessageBody(length: Int(length), from: connection)
                }
            } else if isComplete || error != nil {
                Task { @MainActor in
                    self.removeConnection(connection)
                }
            } else {
                Task { @MainActor in
                    self.receiveMessage(from: connection)
                }
            }
        }
    }

    private func receiveMessageBody(length: Int, from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            if let data, !data.isEmpty {
                Task { @MainActor in
                    self.handleMessage(data, from: connection)
                }
            }

            if isComplete || error != nil {
                Task { @MainActor in
                    self.removeConnection(connection)
                }
            } else {
                Task { @MainActor in
                    self.receiveMessage(from: connection)
                }
            }
        }
    }

    private func handleMessage(_ data: Data, from connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return
        }

        Task { @MainActor in
            processCommand(command, json: json, from: connection)
        }
    }

    private func processCommand(_ command: String, json: [String: Any], from connection: NWConnection) {
        switch command {
        case "requestPresets":
            sendMessage(buildStateMessage(), to: connection)
        case "selectPreset":
            if let index = json["index"] as? Int {
                onPresetSelected?(index)
            }
        case "setMasterVolume":
            if let value = json["value"] as? Double {
                onMasterVolumeChanged?(Float(value))
            }
        case "ping":
            sendMessage(["response": "pong"], to: connection)
        default:
            print("KeyframeRemoteHost: Unknown command - \(command)")
        }
    }

    private func sendMessageToReadyConnections(_ message: [String: Any]) {
        for connection in connections where connection.state == .ready {
            sendMessage(message, to: connection)
        }
    }

    private func sendMessage(_ message: [String: Any], to connection: NWConnection) {
        guard JSONSerialization.isValidJSONObject(message),
              let jsonData = try? JSONSerialization.data(withJSONObject: message) else {
            return
        }

        var length = UInt32(jsonData.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(jsonData)

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error {
                print("KeyframeRemoteHost: Send error - \(error)")
            }
        })
    }

    private func buildStateMessage() -> [String: Any] {
        let session = SessionStore.shared.currentSession
        let presets = session.songs.enumerated().map { index, song -> [String: Any] in
            var data: [String: Any] = [
                "id": song.id.uuidString,
                "name": song.name,
                "order": index
            ]

            if let songName = song.songName {
                data["songName"] = songName
            }
            data["rootNote"] = song.rootNote
            data["scale"] = song.scaleType.rawValue
            if let bpm = song.bpm {
                data["bpm"] = bpm
            }
            return data
        }

        var message: [String: Any] = [
            "presets": presets,
            "masterVolume": Double(AudioEngine.shared.masterVolume)
        ]

        if let activeSongId = session.activeSongId,
           let activeIndex = session.songs.firstIndex(where: { $0.id == activeSongId }) {
            message["activePresetIndex"] = activeIndex
        }

        return message
    }
}
