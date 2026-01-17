import SwiftUI
import CoreMIDI

/// Detailed view for editing a channel's settings
struct ChannelDetailView: View {
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var pluginManager: MacPluginManager

    @State private var showingInstrumentBrowser = false
    @State private var showingEffectBrowser = false

    private let midiChannelOptions = [0] + Array(1...16)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Channel name
                channelNameSection

                Divider()

                // Instrument section
                instrumentSection

                Divider()

                // Effects section
                effectsSection

                Divider()

                // MIDI settings
                midiSettingsSection

                Divider()

                // Mixer settings
                mixerSettingsSection
            }
            .padding()
        }
        .frame(minWidth: 300, idealWidth: 350)
    }

    // MARK: - Channel Name

    private var channelNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHANNEL NAME")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Name", text: $config.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Instrument Section

    private var instrumentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INSTRUMENT")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if channel.isInstrumentLoaded {
                    PluginEditorButton(
                        channel: channel,
                        channelName: config.name,
                        isInstrument: true,
                        effectIndex: nil
                    )
                }
            }

            if let info = channel.instrumentInfo {
                HStack {
                    VStack(alignment: .leading) {
                        Text(info.name)
                            .font(.body)
                        Text(info.manufacturerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { channel.unloadInstrument() }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove Instrument")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            } else {
                Button(action: { showingInstrumentBrowser = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Instrument")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showingInstrumentBrowser) {
            PluginBrowserSheet(
                channel: channel,
                config: $config,
                category: .instrument
            )
            .environmentObject(pluginManager)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS (\(channel.effects.count)/\(channel.maxEffects))")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(Array(channel.effectInfos.enumerated()), id: \.offset) { index, info in
                HStack {
                    VStack(alignment: .leading) {
                        Text(info.name)
                            .font(.body)
                        Text(info.manufacturerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Bypass toggle
                    Button(action: {
                        let isBypassed = channel.effects[index].auAudioUnit.shouldBypassEffect
                        channel.setEffectBypassed(!isBypassed, at: index)
                    }) {
                        Text("BYP")
                            .font(.caption2.bold())
                            .foregroundColor(channel.effects[index].auAudioUnit.shouldBypassEffect ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Bypass")

                    // Editor button
                    PluginEditorButton(
                        channel: channel,
                        channelName: config.name,
                        isInstrument: false,
                        effectIndex: index
                    )

                    // Remove button
                    Button(action: { channel.removeEffect(at: index) }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove Effect")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }

            if channel.effects.count < channel.maxEffects {
                Button(action: { showingEffectBrowser = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Effect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showingEffectBrowser) {
            PluginBrowserSheet(
                channel: channel,
                config: $config,
                category: .effect
            )
            .environmentObject(pluginManager)
        }
    }

    // MARK: - MIDI Settings

    private var midiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MIDI INPUT")
                .font(.caption)
                .foregroundColor(.secondary)

            // MIDI Channel
            HStack {
                Text("Channel")
                Spacer()
                Picker("", selection: $config.midiChannel) {
                    ForEach(midiChannelOptions, id: \.self) { ch in
                        if ch == 0 {
                            Text("Omni").tag(ch)
                        } else {
                            Text("Ch \(ch)").tag(ch)
                        }
                    }
                }
                .frame(width: 100)
            }

            // MIDI Source
            HStack {
                Text("Source")
                Spacer()
                Picker("", selection: $config.midiSourceName) {
                    Text("Any").tag(nil as String?)
                    ForEach(midiEngine.connectedSources) { source in
                        Text(source.name).tag(source.name as String?)
                    }
                }
                .frame(minWidth: 150, maxWidth: 200)
                .truncationMode(.middle)
            }

            // Scale filter
            Toggle("Scale Filter", isOn: $config.scaleFilterEnabled)

            // ChordPad target
            Toggle("ChordPad Target", isOn: $config.isChordPadTarget)
        }
    }

    // MARK: - Mixer Settings

    private var mixerSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MIXER")
                .font(.caption)
                .foregroundColor(.secondary)

            // Volume
            HStack {
                Text("Volume")
                Slider(value: $channel.volume, in: 0...1)
                Text("\(Int(channel.volume * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            // Pan
            HStack {
                Text("Pan")
                Slider(value: $channel.pan, in: -1...1)
                Text(panLabel)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            // Mute/Solo
            HStack {
                Toggle("Mute", isOn: $channel.isMuted)
                Toggle("Solo", isOn: $channel.isSoloed)
            }
        }
    }

    private var panLabel: String {
        if channel.pan < -0.01 {
            return "L\(Int(abs(channel.pan) * 100))"
        } else if channel.pan > 0.01 {
            return "R\(Int(channel.pan * 100))"
        } else {
            return "C"
        }
    }
}

// MARK: - Plugin Browser Sheet

enum PluginCategory {
    case instrument
    case effect
}

struct PluginBrowserSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @EnvironmentObject var pluginManager: MacPluginManager

    let category: PluginCategory

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(category == .instrument ? "Select Instrument" : "Select Effect")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            // Search
            TextField("Search plugins...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // Plugin list
            List {
                ForEach(filteredPlugins) { plugin in
                    Button(action: { loadPlugin(plugin) }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plugin.name)
                                    .font(.body)
                                Text(plugin.manufacturerName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if !plugin.isSandboxSafe {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                    .help("Not sandbox-safe")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 500, idealHeight: 600)
    }

    private var filteredPlugins: [MacPluginInfo] {
        let plugins = category == .instrument
            ? pluginManager.availableInstruments
            : pluginManager.availableEffects

        if searchText.isEmpty {
            return plugins
        }

        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manufacturerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadPlugin(_ plugin: MacPluginInfo) {
        if category == .instrument {
            channel.loadInstrument(plugin.audioComponentDescription) { success, error in
                if success {
                    channel.instrumentInfo = MacAUInfo(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        componentType: plugin.audioComponentDescription.componentType,
                        componentSubType: plugin.audioComponentDescription.componentSubType,
                        componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                    )

                    config.instrument = MacPluginConfiguration(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        audioComponentDescription: plugin.audioComponentDescription
                    )
                }
            }
        } else {
            channel.addEffect(plugin.audioComponentDescription) { success, error in
                if success {
                    channel.effectInfos.append(MacAUInfo(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        componentType: plugin.audioComponentDescription.componentType,
                        componentSubType: plugin.audioComponentDescription.componentSubType,
                        componentManufacturer: plugin.audioComponentDescription.componentManufacturer
                    ))

                    config.effects.append(MacPluginConfiguration(
                        name: plugin.name,
                        manufacturerName: plugin.manufacturerName,
                        audioComponentDescription: plugin.audioComponentDescription
                    ))
                }
            }
        }

        dismiss()
    }
}
