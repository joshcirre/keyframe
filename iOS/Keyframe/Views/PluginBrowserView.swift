import SwiftUI
import AVFoundation
import AudioToolbox

/// Browser for selecting AUv3 instruments and effects - TE Style
struct PluginBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pluginManager = AUv3HostManager.shared

    enum Mode {
        case instrument
        case effect
    }

    let mode: Mode
    let onSelect: (AVAudioUnitComponent) -> Void

    @State private var searchText = ""
    @State private var selectedManufacturer: String?
    @State private var filteredComponents: [AVAudioUnitComponent] = []

    private var components: [AVAudioUnitComponent] {
        switch mode {
        case .instrument:
            return pluginManager.availableInstruments
        case .effect:
            return pluginManager.availableEffects
        }
    }

    private var manufacturers: [String] {
        switch mode {
        case .instrument:
            return pluginManager.instrumentManufacturers
        case .effect:
            return pluginManager.effectManufacturers
        }
    }

    private func updateFilteredComponents() {
        var result = components

        if let manufacturer = selectedManufacturer {
            result = result.filter { $0.manufacturerName == manufacturer }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.manufacturerName.localizedCaseInsensitiveContains(searchText)
            }
        }

        filteredComponents = result
    }
    
    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                
                // Search bar
                searchBar
                
                // Manufacturer filter
                manufacturerFilter
                
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                
                // Plugin list
                pluginList
            }
        }
        .preferredColorScheme(.light)
        .task {
            updateFilteredComponents()
        }
        .onChange(of: searchText) {
            updateFilteredComponents()
        }
        .onChange(of: selectedManufacturer) {
            updateFilteredComponents()
        }
        .onChange(of: pluginManager.availableInstruments) {
            updateFilteredComponents()
        }
        .onChange(of: pluginManager.availableEffects) {
            updateFilteredComponents()
        }
    }

    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(TEColors.darkGray)
            }
            
            Spacer()
            
            Text(mode == .instrument ? "INSTRUMENTS" : "EFFECTS")
                .font(TEFonts.display(16, weight: .black))
                .foregroundStyle(TEColors.black)
                .tracking(2)
            
            Spacer()
            
            Button {
                pluginManager.scanForPlugins()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TEColors.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TEColors.midGray)
            
            TextField("SEARCH", text: $searchText)
                .font(TEFonts.mono(12, weight: .medium))
                .foregroundStyle(TEColors.black)
                .textInputAutocapitalization(.characters)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)
                }
            }
        }
        .padding(16)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Manufacturer Filter
    
    private var manufacturerFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "ALL", isSelected: selectedManufacturer == nil) {
                    selectedManufacturer = nil
                }
                
                ForEach(manufacturers, id: \.self) { manufacturer in
                    FilterChip(
                        title: manufacturer.uppercased(),
                        isSelected: selectedManufacturer == manufacturer
                    ) {
                        selectedManufacturer = manufacturer
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(TEColors.lightGray.opacity(0.5))
    }
    
    // MARK: - Plugin List
    
    private var pluginList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if pluginManager.isScanning {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(TEColors.orange)
                        Text("SCANNING...")
                            .font(TEFonts.mono(12, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if filteredComponents.isEmpty {
                    Text("NO PLUGINS FOUND")
                        .font(TEFonts.mono(12, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    ForEach(Array(filteredComponents.enumerated()), id: \.element.name) { index, component in
                        PluginRowView(
                            component: component,
                            index: index,
                            isInstrument: mode == .instrument
                        ) {
                            onSelect(component)
                            dismiss()
                        }
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
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(isSelected ? .white : TEColors.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(isSelected ? TEColors.black : TEColors.warmWhite)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plugin Row View

struct PluginRowView: View {
    let component: AVAudioUnitComponent
    let index: Int
    let isInstrument: Bool
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Index number
                Text(String(format: "%02d", index + 1))
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
                    .frame(width: 24)
                
                // Icon
                ZStack {
                    Rectangle()
                        .fill(TEColors.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isInstrument ? "pianokeys" : "waveform")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TEColors.orange)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.name.uppercased())
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                        .lineLimit(1)
                    
                    Text(component.manufacturerName.uppercased())
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TEColors.darkGray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(isPressed ? TEColors.lightGray : (index % 2 == 0 ? TEColors.cream : TEColors.warmWhite))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PluginBrowserView(mode: .instrument) { _ in }
}
