import SwiftUI
import AVFoundation
import AudioToolbox

/// Detailed view for editing a channel's instrument, effects, and settings
struct ChannelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var showingInstrumentPicker = false
    @State private var showingEffectPicker = false
    @State private var showingInstrumentUI = false
    @State private var selectedEffectIndex: Int?
    @State private var pluginViewController: UIViewController?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Channel Header
                    ChannelHeaderSection(config: $config, channel: channel)
                    
                    // Instrument Section
                    InstrumentSection(
                        channel: channel,
                        config: $config,
                        onSelectInstrument: { showingInstrumentPicker = true },
                        onOpenUI: { openInstrumentUI() }
                    )
                    
                    // Effects Section
                    EffectsSection(
                        channel: channel,
                        config: $config,
                        onAddEffect: { showingEffectPicker = true },
                        onOpenEffectUI: { index in openEffectUI(at: index) }
                    )
                    
                    // MIDI Settings
                    MIDISettingsSection(config: $config)
                    
                    // Mixer Controls
                    MixerControlsSection(channel: channel, config: $config)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(config.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingInstrumentPicker) {
            PluginBrowserView(
                mode: .instrument,
                onSelect: { component in
                    loadInstrument(component)
                }
            )
        }
        .sheet(isPresented: $showingEffectPicker) {
            PluginBrowserView(
                mode: .effect,
                onSelect: { component in
                    loadEffect(component)
                }
            )
        }
        .sheet(isPresented: $showingInstrumentUI) {
            if let vc = pluginViewController {
                PluginUIHostView(viewController: vc)
            }
        }
    }
    
    // MARK: - Plugin Loading
    
    private func loadInstrument(_ component: AVAudioUnitComponent) {
        channel.loadInstrument(component.audioComponentDescription) { success, error in
            if success {
                channel.instrumentInfo = pluginManager.getInfo(for: component)
                config.instrument = PluginConfiguration(
                    name: component.name,
                    manufacturerName: component.manufacturerName,
                    componentType: component.audioComponentDescription.componentType,
                    componentSubType: component.audioComponentDescription.componentSubType,
                    componentManufacturer: component.audioComponentDescription.componentManufacturer
                )
            }
        }
    }
    
    private func loadEffect(_ component: AVAudioUnitComponent) {
        channel.addEffect(component.audioComponentDescription) { success, error in
            if success {
                channel.effectInfos.append(pluginManager.getInfo(for: component))
                config.effects.append(PluginConfiguration(
                    name: component.name,
                    manufacturerName: component.manufacturerName,
                    componentType: component.audioComponentDescription.componentType,
                    componentSubType: component.audioComponentDescription.componentSubType,
                    componentManufacturer: component.audioComponentDescription.componentManufacturer
                ))
            }
        }
    }
    
    private func openInstrumentUI() {
        channel.getInstrumentViewController { vc in
            if let vc = vc {
                pluginViewController = vc
                showingInstrumentUI = true
            }
        }
    }
    
    private func openEffectUI(at index: Int) {
        channel.getEffectViewController(at: index) { vc in
            if let vc = vc {
                pluginViewController = vc
                showingInstrumentUI = true
            }
        }
    }
}

// MARK: - Channel Header Section

struct ChannelHeaderSection: View {
    @Binding var config: ChannelConfiguration
    @ObservedObject var channel: ChannelStrip
    
    var body: some View {
        VStack(spacing: 12) {
            // Name editor
            TextField("Channel Name", text: $config.name)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Color picker
            HStack(spacing: 8) {
                ForEach(ChannelColor.allCases) { color in
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: config.color == color ? 2 : 0)
                        )
                        .onTapGesture {
                            config.color = color
                        }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Instrument Section

struct InstrumentSection: View {
    @ObservedObject var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    let onSelectInstrument: () -> Void
    let onOpenUI: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSTRUMENT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            if let instrument = config.instrument {
                // Instrument loaded
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instrument.name)
                            .font(.headline)
                        Text(instrument.manufacturerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("UI") {
                        onOpenUI()
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    
                    Button("Change") {
                        onSelectInstrument()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // No instrument
                Button {
                    onSelectInstrument()
                } label: {
                    HStack {
                        Image(systemName: "pianokeys")
                            .font(.title2)
                        Text("Select Instrument")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .foregroundColor(.cyan)
                }
            }
            
            if channel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Effects Section

struct EffectsSection: View {
    @ObservedObject var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    let onAddEffect: () -> Void
    let onOpenEffectUI: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSERT EFFECTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                Text("\(config.effects.count)/\(channel.maxEffects)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Effect slots
            ForEach(Array(config.effects.enumerated()), id: \.element.id) { index, effect in
                EffectSlotView(
                    effect: effect,
                    index: index,
                    isBypassed: channel.effects[safe: index]?.auAudioUnit.shouldBypassEffect ?? false,
                    onOpenUI: { onOpenEffectUI(index) },
                    onToggleBypass: {
                        channel.setEffectBypassed(!channel.effects[index].auAudioUnit.shouldBypassEffect, at: index)
                    },
                    onRemove: {
                        channel.removeEffect(at: index)
                        config.effects.remove(at: index)
                    }
                )
            }
            
            // Add effect button
            if config.effects.count < channel.maxEffects {
                Button {
                    onAddEffect()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Effect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.cyan)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Effect Slot View

struct EffectSlotView: View {
    let effect: PluginConfiguration
    let index: Int
    let isBypassed: Bool
    let onOpenUI: () -> Void
    let onToggleBypass: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            // Index
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.cyan))
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isBypassed ? .gray : .primary)
                Text(effect.manufacturerName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // UI button
            Button("UI") {
                onOpenUI()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.cyan)
            
            // Bypass button
            Button {
                onToggleBypass()
            } label: {
                Image(systemName: isBypassed ? "power.circle" : "power.circle.fill")
                    .foregroundColor(isBypassed ? .gray : .green)
            }
            .buttonStyle(.plain)
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
        )
    }
}

// MARK: - MIDI Settings Section

struct MIDISettingsSection: View {
    @Binding var config: ChannelConfiguration
    @StateObject private var midiEngine = MIDIEngine.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI SETTINGS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            // MIDI Source (Controller) Selection
            HStack {
                Text("MIDI Input")
                Spacer()
                Picker("", selection: Binding(
                    get: { config.midiSourceName ?? "" },
                    set: { config.midiSourceName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All Controllers").tag("")
                    ForEach(midiEngine.connectedSources, id: \.name) { source in
                        Text(source.name).tag(source.name)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // MIDI Channel
            HStack {
                Text("MIDI Channel")
                Spacer()
                Picker("", selection: $config.midiChannel) {
                    Text("All Channels").tag(0)
                    ForEach(1...16, id: \.self) { ch in
                        Text("Ch \(ch)").tag(ch)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Summary of MIDI routing
            let sourceText = config.midiSourceName ?? "Any controller"
            let channelText = config.midiChannel == 0 ? "all channels" : "channel \(config.midiChannel)"
            Text("Listens to: \(sourceText) on \(channelText)")
                .font(.caption)
                .foregroundColor(.cyan)
            
            Divider()
            
            // Scale Filter
            Toggle("Scale Filter", isOn: $config.scaleFilterEnabled)
            
            // NM2 Chord Channel
            Toggle("NM2 Chord Trigger", isOn: $config.isNM2ChordChannel)
            
            if config.isNM2ChordChannel {
                Text("This channel will receive chord triggers from the NM2 controller")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Mixer Controls Section

struct MixerControlsSection: View {
    @ObservedObject var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIXER")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            // Volume
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(channel.volume * 100))%")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $channel.volume, in: 0...1)
                    .tint(.cyan)
                    .onChange(of: channel.volume) { _, newValue in
                        config.volume = newValue
                    }
            }
            
            // Pan
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pan")
                    Spacer()
                    Text(panLabel)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $channel.pan, in: -1...1)
                    .tint(.cyan)
                    .onChange(of: channel.pan) { _, newValue in
                        config.pan = newValue
                    }
            }
            
            // Mute/Solo
            HStack(spacing: 16) {
                Button {
                    channel.isMuted.toggle()
                    config.isMuted = channel.isMuted
                } label: {
                    Text("MUTE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(channel.isMuted ? .black : .red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(channel.isMuted ? Color.red : Color.red.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                
                Button {
                    channel.isSoloed.toggle()
                } label: {
                    Text("SOLO")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(channel.isSoloed ? .black : .yellow)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(channel.isSoloed ? Color.yellow : Color.yellow.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var panLabel: String {
        if channel.pan < -0.01 {
            return "L \(Int(abs(channel.pan) * 100))"
        } else if channel.pan > 0.01 {
            return "R \(Int(channel.pan * 100))"
        } else {
            return "C"
        }
    }
}

// MARK: - Plugin UI Host View

struct PluginUIHostView: View {
    @Environment(\.dismiss) private var dismiss
    let viewController: UIViewController
    
    var body: some View {
        NavigationStack {
            PluginUIViewControllerWrapper(viewController: viewController)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct PluginUIViewControllerWrapper: UIViewControllerRepresentable {
    let viewController: UIViewController
    
    func makeUIViewController(context: Context) -> UIViewController {
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Array Extension

extension Array where Element == AVAudioUnit {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
