import AVFoundation
import AudioToolbox
import CoreAudioKit
import UIKit

/// Manages discovery, instantiation, and lifecycle of AUv3 plugins
final class AUv3HostManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AUv3HostManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var availableInstruments: [AVAudioUnitComponent] = []
    @Published private(set) var availableEffects: [AVAudioUnitComponent] = []
    @Published private(set) var isScanning = false
    
    // MARK: - Component Manager
    
    private let componentManager = AVAudioUnitComponentManager.shared()
    private var notificationObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
        scanForPlugins()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Listen for new plugins being installed
        notificationObserver = NotificationCenter.default.addObserver(
            forName: AVAudioUnitComponentManager.registrationsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scanForPlugins()
        }
    }
    
    // MARK: - Plugin Discovery
    
    /// Scan for all available AUv3 plugins
    func scanForPlugins() {
        isScanning = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Find instruments (Music Devices)
            let instrumentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_MusicDevice,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
            let instruments = AVAudioUnitComponentManager.shared().components(matching: instrumentDescription)
            
            // Find effects
            let effectDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
            let effects = AVAudioUnitComponentManager.shared().components(matching: effectDescription)
            
            // Also find Music Effects (effects that can receive MIDI)
            let musicEffectDescription = AudioComponentDescription(
                componentType: kAudioUnitType_MusicEffect,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
            let musicEffects = AVAudioUnitComponentManager.shared().components(matching: musicEffectDescription)
            
            // Combine and sort
            let allEffects = (effects + musicEffects).sorted { $0.name < $1.name }
            let sortedInstruments = instruments.sorted { $0.name < $1.name }
            
            DispatchQueue.main.async {
                self?.availableInstruments = sortedInstruments
                self?.availableEffects = allEffects
                self?.isScanning = false
                
                print("AUv3HostManager: Found \(sortedInstruments.count) instruments, \(allEffects.count) effects")
            }
        }
    }
    
    // MARK: - Plugin Info
    
    /// Get info for a component
    func getInfo(for component: AVAudioUnitComponent) -> AUv3Info {
        return AUv3Info(
            name: component.name,
            manufacturerName: component.manufacturerName,
            componentType: component.audioComponentDescription.componentType,
            componentSubType: component.audioComponentDescription.componentSubType,
            componentManufacturer: component.audioComponentDescription.componentManufacturer
        )
    }
    
    /// Get the icon for a component (if available)
    func getIcon(for component: AVAudioUnitComponent, size: CGSize = CGSize(width: 44, height: 44)) -> UIImage? {
        // icon property is only available on macOS, not iOS
        return nil
    }
    
    // MARK: - Component Lookup
    
    /// Find a component by its audio component description
    func findComponent(matching description: AudioComponentDescription) -> AVAudioUnitComponent? {
        let components = componentManager.components(matching: description)
        return components.first
    }
    
    /// Find instrument by name
    func findInstrument(named name: String) -> AVAudioUnitComponent? {
        return availableInstruments.first { $0.name == name }
    }
    
    /// Find effect by name
    func findEffect(named name: String) -> AVAudioUnitComponent? {
        return availableEffects.first { $0.name == name }
    }
    
    // MARK: - Grouped Lists
    
    /// Get instruments grouped by manufacturer
    var instrumentsByManufacturer: [String: [AVAudioUnitComponent]] {
        Dictionary(grouping: availableInstruments) { $0.manufacturerName }
    }
    
    /// Get effects grouped by manufacturer
    var effectsByManufacturer: [String: [AVAudioUnitComponent]] {
        Dictionary(grouping: availableEffects) { $0.manufacturerName }
    }
    
    /// Get all manufacturers with instruments
    var instrumentManufacturers: [String] {
        Array(Set(availableInstruments.map { $0.manufacturerName })).sorted()
    }
    
    /// Get all manufacturers with effects
    var effectManufacturers: [String] {
        Array(Set(availableEffects.map { $0.manufacturerName })).sorted()
    }
}

// MARK: - AVAudioUnitComponent Extensions

extension AVAudioUnitComponent {
    /// Check if this is an Apple built-in component
    var isApple: Bool {
        manufacturerName == "Apple"
    }
    
    /// Get a four-character code string from the component type
    var typeString: String {
        fourCharCodeString(audioComponentDescription.componentType)
    }
    
    /// Get a four-character code string from the subtype
    var subtypeString: String {
        fourCharCodeString(audioComponentDescription.componentSubType)
    }
    
    /// Get a four-character code string from the manufacturer
    var manufacturerCode: String {
        fourCharCodeString(audioComponentDescription.componentManufacturer)
    }
    
    private func fourCharCodeString(_ code: UInt32) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!)
        ]
        return String(chars)
    }
}

// MARK: - Plugin Categories

enum PluginCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case synths = "Synths"
    case samplers = "Samplers"
    case drums = "Drums"
    case effects = "Effects"
    case dynamics = "Dynamics"
    case eq = "EQ"
    case reverb = "Reverb"
    case delay = "Delay"
    case modulation = "Modulation"
    case distortion = "Distortion"
    case utility = "Utility"
    
    var id: String { rawValue }
    
    /// Keywords that might indicate this category
    var keywords: [String] {
        switch self {
        case .all: return []
        case .synths: return ["synth", "synthesizer", "analog", "digital", "wavetable", "fm"]
        case .samplers: return ["sampler", "sample", "rompler"]
        case .drums: return ["drum", "beat", "percussion", "rhythm"]
        case .effects: return []
        case .dynamics: return ["compressor", "limiter", "gate", "expander", "dynamics"]
        case .eq: return ["eq", "equalizer", "filter", "parametric"]
        case .reverb: return ["reverb", "room", "hall", "plate", "spring"]
        case .delay: return ["delay", "echo", "tape"]
        case .modulation: return ["chorus", "flanger", "phaser", "tremolo", "vibrato", "modulation"]
        case .distortion: return ["distortion", "overdrive", "saturation", "fuzz", "amp"]
        case .utility: return ["gain", "utility", "meter", "analyzer", "tuner"]
        }
    }
    
    /// Check if a component likely belongs to this category
    func matches(_ component: AVAudioUnitComponent) -> Bool {
        if self == .all { return true }
        
        let name = component.name.lowercased()
        let manufacturer = component.manufacturerName.lowercased()
        
        for keyword in keywords {
            if name.contains(keyword) || manufacturer.contains(keyword) {
                return true
            }
        }
        
        return false
    }
}
