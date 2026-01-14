import AVFoundation
import AudioToolbox

/// Manages AU plugin discovery for macOS
/// Similar to iOS AUv3HostManager but for desktop plugins
final class MacPluginManager: ObservableObject {

    // MARK: - Singleton

    static let shared = MacPluginManager()

    // MARK: - Published Properties

    @Published private(set) var availableInstruments: [MacPluginInfo] = []
    @Published private(set) var availableEffects: [MacPluginInfo] = []
    @Published private(set) var isScanning: Bool = false

    // MARK: - Initialization

    private init() {
        scanForPlugins()
    }

    // MARK: - Plugin Scanning

    func scanForPlugins() {
        isScanning = true

        Task {
            // Scan for instruments (Music Devices)
            let instrumentDesc = AudioComponentDescription(
                componentType: kAudioUnitType_MusicDevice,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )

            let instruments = await scanComponents(matching: instrumentDesc)

            // Scan for effects
            let effectDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )

            let effects = await scanComponents(matching: effectDesc)

            // Also scan for Music Effects (tempo-synced effects)
            let musicEffectDesc = AudioComponentDescription(
                componentType: kAudioUnitType_MusicEffect,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )

            let musicEffects = await scanComponents(matching: musicEffectDesc)

            await MainActor.run {
                self.availableInstruments = instruments.sorted { $0.name < $1.name }
                self.availableEffects = (effects + musicEffects).sorted { $0.name < $1.name }
                self.isScanning = false
                print("MacPluginManager: Found \(self.availableInstruments.count) instruments, \(self.availableEffects.count) effects")
            }
        }
    }

    private func scanComponents(matching description: AudioComponentDescription) async -> [MacPluginInfo] {
        // On macOS, use synchronous component enumeration
        let components = AVAudioUnitComponentManager.shared().components(matching: description)

        return components.map { component in
            MacPluginInfo(
                name: component.name,
                manufacturerName: component.manufacturerName,
                audioComponentDescription: component.audioComponentDescription,
                hasCustomView: component.hasCustomView,
                isSandboxSafe: component.isSandboxSafe
            )
        }
    }

    // MARK: - Plugin Lookup

    func findInstrument(named name: String) -> MacPluginInfo? {
        availableInstruments.first { $0.name == name }
    }

    func findEffect(named name: String) -> MacPluginInfo? {
        availableEffects.first { $0.name == name }
    }

    func findPlugin(matching description: AudioComponentDescription) -> MacPluginInfo? {
        let allPlugins = availableInstruments + availableEffects
        return allPlugins.first { plugin in
            plugin.audioComponentDescription.componentType == description.componentType &&
            plugin.audioComponentDescription.componentSubType == description.componentSubType &&
            plugin.audioComponentDescription.componentManufacturer == description.componentManufacturer
        }
    }
}

// MARK: - Plugin Info

struct MacPluginInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let manufacturerName: String
    let audioComponentDescription: AudioComponentDescription
    let hasCustomView: Bool
    let isSandboxSafe: Bool

    var isInstrument: Bool {
        audioComponentDescription.componentType == kAudioUnitType_MusicDevice
    }

    var isEffect: Bool {
        audioComponentDescription.componentType == kAudioUnitType_Effect ||
        audioComponentDescription.componentType == kAudioUnitType_MusicEffect
    }

    static func == (lhs: MacPluginInfo, rhs: MacPluginInfo) -> Bool {
        lhs.audioComponentDescription == rhs.audioComponentDescription
    }
}
