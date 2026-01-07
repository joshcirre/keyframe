import SwiftUI
import AVFoundation
import AudioToolbox

/// Browser for selecting AUv3 instruments and effects
struct PluginBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    enum Mode {
        case instrument
        case effect
    }
    
    let mode: Mode
    let onSelect: (AVAudioUnitComponent) -> Void
    
    @State private var searchText = ""
    @State private var selectedManufacturer: String?
    
    private var components: [AVAudioUnitComponent] {
        switch mode {
        case .instrument:
            return pluginManager.availableInstruments
        case .effect:
            return pluginManager.availableEffects
        }
    }
    
    private var filteredComponents: [AVAudioUnitComponent] {
        var result = components
        
        // Filter by manufacturer
        if let manufacturer = selectedManufacturer {
            result = result.filter { $0.manufacturerName == manufacturer }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.manufacturerName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    private var manufacturers: [String] {
        switch mode {
        case .instrument:
            return pluginManager.instrumentManufacturers
        case .effect:
            return pluginManager.effectManufacturers
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Manufacturer filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedManufacturer == nil) {
                            selectedManufacturer = nil
                        }
                        
                        ForEach(manufacturers, id: \.self) { manufacturer in
                            FilterChip(title: manufacturer, isSelected: selectedManufacturer == manufacturer) {
                                selectedManufacturer = manufacturer
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                
                // Plugin list
                List {
                    if pluginManager.isScanning {
                        HStack {
                            ProgressView()
                            Text("Scanning for plugins...")
                                .foregroundColor(.secondary)
                        }
                    } else if filteredComponents.isEmpty {
                        Text("No plugins found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredComponents, id: \.name) { component in
                            PluginRowView(component: component) {
                                onSelect(component)
                                dismiss()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(mode == .instrument ? "Instruments" : "Effects")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search plugins")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pluginManager.scanForPlugins()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.cyan : Color(UIColor.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plugin Row View

struct PluginRowView: View {
    let component: AVAudioUnitComponent
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon (placeholder since iOS doesn't support AU icons)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyan.opacity(0.2))
                Image(systemName: component.audioComponentDescription.componentType == kAudioUnitType_MusicDevice ? "pianokeys" : "waveform")
                    .foregroundColor(.cyan)
            }
            .frame(width: 44, height: 44)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(component.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(component.manufacturerName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Preview

#Preview {
    PluginBrowserView(mode: .instrument) { _ in }
}
