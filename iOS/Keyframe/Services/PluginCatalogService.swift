import AVFoundation
import AudioToolbox

/// Represents a factory preset available within an instrument
struct FactoryPreset: Identifiable, Codable, Sendable {
    let id: Int  // The preset number
    let name: String
}

/// Codable wrapper for AudioComponentDescription
struct CodableComponentDescription: Codable, Sendable {
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32
    
    var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
    
    init(from description: AudioComponentDescription) {
        self.componentType = description.componentType
        self.componentSubType = description.componentSubType
        self.componentManufacturer = description.componentManufacturer
    }
}

/// Complete catalog entry for a plugin including its factory presets
struct PluginCatalogEntry: Identifiable, Codable, Sendable {
    let id: String  // Unique identifier (manufacturer + name)
    let name: String
    let manufacturerName: String
    let codableComponentDescription: CodableComponentDescription
    let categoryRawValue: String
    let factoryPresets: [FactoryPreset]
    var soundTags: [String]  // AI-generated sound characteristics
    
    var componentDescription: AudioComponentDescription {
        codableComponentDescription.audioComponentDescription
    }
    
    var category: PluginCategory {
        PluginCategory(rawValue: categoryRawValue) ?? .all
    }
    
    var isInstrument: Bool {
        codableComponentDescription.componentType == kAudioUnitType_MusicDevice
    }
    
    var isEffect: Bool {
        codableComponentDescription.componentType == kAudioUnitType_Effect ||
        codableComponentDescription.componentType == kAudioUnitType_MusicEffect
    }
    
    init(id: String, name: String, manufacturerName: String, componentDescription: AudioComponentDescription, category: PluginCategory, factoryPresets: [FactoryPreset], soundTags: [String] = []) {
        self.id = id
        self.name = name
        self.manufacturerName = manufacturerName
        self.codableComponentDescription = CodableComponentDescription(from: componentDescription)
        self.categoryRawValue = category.rawValue
        self.factoryPresets = factoryPresets
        self.soundTags = soundTags
    }
}

/// Persisted catalog data
private struct PersistedCatalog: Codable {
    let instruments: [PluginCatalogEntry]
    let effects: [PluginCatalogEntry]
    let savedAt: Date
    let pluginCount: Int  // To detect if plugins were added/removed
}

/// Service that catalogs available plugins and their factory presets
@Observable
@MainActor
final class PluginCatalogService {
    
    static let shared = PluginCatalogService()
    
    private(set) var instrumentCatalog: [PluginCatalogEntry] = []
    private(set) var effectCatalog: [PluginCatalogEntry] = []
    private(set) var isScanning = false
    private(set) var scanProgress: Double = 0
    
    private let catalogKey = "plugin_catalog_v1"
    
    private init() {
        loadPersistedCatalog()
    }
    
    /// Check if catalog needs refresh (plugin count changed)
    var needsRefresh: Bool {
        let hostManager = AUv3HostManager.shared
        let currentCount = hostManager.availableInstruments.count + hostManager.availableEffects.count
        let catalogCount = instrumentCatalog.count + effectCatalog.count
        return catalogCount == 0 || currentCount != catalogCount
    }
    
    /// Scan all available plugins and enumerate their factory presets
    /// This is an expensive operation - call once at app launch or on demand
    func buildCatalog() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        
        let hostManager = AUv3HostManager.shared
        let allInstruments = hostManager.availableInstruments
        let allEffects = hostManager.availableEffects
        let totalCount = allInstruments.count + allEffects.count
        var processed = 0
        
        var instruments: [PluginCatalogEntry] = []
        var effects: [PluginCatalogEntry] = []
        
        // Process instruments
        for component in allInstruments {
            if let entry = await buildCatalogEntry(for: component) {
                instruments.append(entry)
            }
            processed += 1
            scanProgress = Double(processed) / Double(totalCount)
        }
        
        // Process effects
        for component in allEffects {
            if let entry = await buildCatalogEntry(for: component) {
                effects.append(entry)
            }
            processed += 1
            scanProgress = Double(processed) / Double(totalCount)
        }
        
        instrumentCatalog = instruments.sorted { $0.name < $1.name }
        effectCatalog = effects.sorted { $0.name < $1.name }
        
        // TODO: Generate AI sound tags for better matching (not implemented yet)
        // print("PluginCatalogService: Generating sound tags...")
        // await generateSoundTags()
        
        isScanning = false
        scanProgress = 1.0
        
        // Persist the catalog
        saveCatalog()
        
        print("PluginCatalogService: Cataloged \(instruments.count) instruments, \(effects.count) effects")
    }
    
    /// Build a catalog entry for a single component by instantiating it temporarily
    private func buildCatalogEntry(for component: AVAudioUnitComponent) async -> PluginCatalogEntry? {
        let description = component.audioComponentDescription
        
        // Instantiate the plugin to read its factory presets
        let presets = await withCheckedContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: .loadOutOfProcess) { audioUnit, error in
                guard let audioUnit = audioUnit, error == nil else {
                    continuation.resume(returning: [FactoryPreset]())
                    return
                }
                
                // Read factory presets
                let factoryPresets = audioUnit.auAudioUnit.factoryPresets ?? []
                let presets = factoryPresets.map { preset in
                    FactoryPreset(id: preset.number, name: preset.name)
                }
                
                continuation.resume(returning: presets)
            }
        }
        
        // Determine category
        let category = PluginCategory.allCases.first { cat in
            cat != .all && cat.matches(component)
        } ?? .all
        
        return PluginCatalogEntry(
            id: "\(component.manufacturerName).\(component.name)",
            name: component.name,
            manufacturerName: component.manufacturerName,
            componentDescription: description,
            category: category,
            factoryPresets: presets
        )
    }
    
    /// Get a summary suitable for sending to an LLM
    func getCatalogSummary() -> String {
        var summary = "# Available Instruments\n\n"
        
        for instrument in instrumentCatalog {
            summary += "## \(instrument.name) (\(instrument.manufacturerName))\n"
            if instrument.factoryPresets.isEmpty {
                summary += "- No factory presets (uses default sound)\n"
            } else {
                summary += "Factory presets:\n"
                for preset in instrument.factoryPresets.prefix(20) {  // Limit to keep context reasonable
                    summary += "- \(preset.name)\n"
                }
                if instrument.factoryPresets.count > 20 {
                    summary += "- ... and \(instrument.factoryPresets.count - 20) more\n"
                }
            }
            summary += "\n"
        }
        
        summary += "# Available Effects\n\n"
        
        for effect in effectCatalog {
            summary += "## \(effect.name) (\(effect.manufacturerName)) - Category: \(effect.category.rawValue)\n"
            if !effect.factoryPresets.isEmpty {
                summary += "Factory presets: "
                summary += effect.factoryPresets.prefix(10).map { $0.name }.joined(separator: ", ")
                if effect.factoryPresets.count > 10 {
                    summary += ", ... and \(effect.factoryPresets.count - 10) more"
                }
                summary += "\n"
            }
            summary += "\n"
        }
        
        return summary
    }
    
    /// Find an instrument by name (with fuzzy matching fallback)
    func findInstrument(named name: String) -> PluginCatalogEntry? {
        let searchName = name.lowercased()
        
        // Exact match first
        if let exact = instrumentCatalog.first(where: { $0.name.lowercased() == searchName }) {
            return exact
        }
        
        // Try removing manufacturer suffix like "(AudioKit)" or "(Waldorf)"
        let cleanedName = searchName.replacingOccurrences(of: #"\s*\([^)]+\)\s*$"#, with: "", options: .regularExpression)
        if let cleaned = instrumentCatalog.first(where: { $0.name.lowercased() == cleanedName }) {
            return cleaned
        }
        
        // Try contains match (instrument name contains search or vice versa)
        if let contains = instrumentCatalog.first(where: { 
            $0.name.lowercased().contains(cleanedName) || cleanedName.contains($0.name.lowercased())
        }) {
            return contains
        }
        
        return nil
    }
    
    /// Find an effect by name (with fuzzy matching fallback)
    func findEffect(named name: String) -> PluginCatalogEntry? {
        let searchName = name.lowercased()
        
        // Exact match first
        if let exact = effectCatalog.first(where: { $0.name.lowercased() == searchName }) {
            return exact
        }
        
        // Try removing manufacturer suffix like "(Apple)" or "(Eventide)"
        let cleanedName = searchName.replacingOccurrences(of: #"\s*\([^)]+\)\s*$"#, with: "", options: .regularExpression)
        if let cleaned = effectCatalog.first(where: { $0.name.lowercased() == cleanedName }) {
            return cleaned
        }
        
        // Try contains match
        if let contains = effectCatalog.first(where: { 
            $0.name.lowercased().contains(cleanedName) || cleanedName.contains($0.name.lowercased())
        }) {
            return contains
        }
        
        return nil
    }
    
    /// Find a factory preset within an instrument
    func findPreset(named presetName: String, in instrument: PluginCatalogEntry) -> FactoryPreset? {
        instrument.factoryPresets.first { $0.name.lowercased() == presetName.lowercased() }
    }
    
    // MARK: - Persistence
    
    private func saveCatalog() {
        let catalog = PersistedCatalog(
            instruments: instrumentCatalog,
            effects: effectCatalog,
            savedAt: Date(),
            pluginCount: instrumentCatalog.count + effectCatalog.count
        )
        
        do {
            let data = try JSONEncoder().encode(catalog)
            UserDefaults.standard.set(data, forKey: catalogKey)
            print("PluginCatalogService: Saved catalog to disk")
        } catch {
            print("PluginCatalogService: Failed to save catalog: \(error)")
        }
    }
    
    private func loadPersistedCatalog() {
        guard let data = UserDefaults.standard.data(forKey: catalogKey) else {
            print("PluginCatalogService: No persisted catalog found")
            return
        }
        
        do {
            let catalog = try JSONDecoder().decode(PersistedCatalog.self, from: data)
            instrumentCatalog = catalog.instruments
            effectCatalog = catalog.effects
            print("PluginCatalogService: Loaded \(catalog.instruments.count) instruments, \(catalog.effects.count) effects from disk (saved \(catalog.savedAt))")
        } catch {
            print("PluginCatalogService: Failed to load catalog: \(error)")
        }
    }
}
