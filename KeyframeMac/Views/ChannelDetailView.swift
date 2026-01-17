import SwiftUI
import CoreMIDI

/// Detailed view for editing a channel's settings
struct ChannelDetailView: View {
    @ObservedObject var channel: MacChannelStrip
    @Binding var config: MacChannelConfiguration
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @EnvironmentObject var pluginManager: MacPluginManager

    let colors: ThemeColors

    @State private var showingInstrumentBrowser = false
    @State private var showingEffectBrowser = false

    private let midiChannelOptions = [0] + Array(1...16)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Channel name
                channelNameSection

                sectionDivider

                // Instrument section
                instrumentSection

                sectionDivider

                // Effects section
                effectsSection

                sectionDivider

                // MIDI settings
                midiSettingsSection

                sectionDivider

                // Mixer settings
                mixerSettingsSection
            }
        }
        .frame(minWidth: 320, idealWidth: 380)
        .background(colors.windowBackground)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(colors.border)
            .frame(height: colors.borderWidth)
    }

    // MARK: - Channel Name

    private var channelNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHANNEL NAME")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)

            TextField("", text: $config.name)
                .font(TEFonts.mono(14, weight: .bold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                .onChange(of: config.name) { _, newValue in
                    let uppercased = newValue.uppercased()
                    if uppercased != newValue {
                        config.name = uppercased
                    }
                }
        }
        .padding(16)
    }

    // MARK: - Instrument Section

    private var instrumentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INSTRUMENT")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(colors.secondaryText)

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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(colors.primaryText)
                        Text(info.manufacturerName)
                            .font(TEFonts.mono(10))
                            .foregroundColor(colors.secondaryText)
                    }

                    Spacer()

                    Button(action: { channel.unloadInstrument() }) {
                        Image(systemName: "xmark")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.error)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Remove Instrument")
                }
                .padding(10)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            } else {
                Button(action: { showingInstrumentBrowser = true }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(TEFonts.mono(10, weight: .bold))
                        Text("ADD INSTRUMENT")
                            .font(TEFonts.mono(10, weight: .bold))
                    }
                    .foregroundColor(colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(colors.controlBackground)
                    .overlay(
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: colors.borderWidth, dash: [4, 2]))
                            .foregroundColor(colors.border)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingInstrumentBrowser) {
            PluginBrowserSheet(
                channel: channel,
                config: $config,
                category: .instrument,
                colors: colors
            )
            .environmentObject(pluginManager)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS (\(channel.effects.count)/\(channel.maxEffects))")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)

            ForEach(Array(channel.effectInfos.enumerated()), id: \.offset) { index, info in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(colors.primaryText)
                        Text(info.manufacturerName)
                            .font(TEFonts.mono(10))
                            .foregroundColor(colors.secondaryText)
                    }

                    Spacer()

                    // Bypass toggle
                    Button(action: {
                        let isBypassed = channel.effects[index].auAudioUnit.shouldBypassEffect
                        channel.setEffectBypassed(!isBypassed, at: index)
                    }) {
                        Text("BYP")
                            .font(TEFonts.mono(9, weight: .bold))
                            .foregroundColor(channel.effects[index].auAudioUnit.shouldBypassEffect ? colors.warning : colors.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(channel.effects[index].auAudioUnit.shouldBypassEffect ? colors.warning.opacity(0.2) : Color.clear)
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
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
                        Image(systemName: "xmark")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.error)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Remove Effect")
                }
                .padding(10)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }

            if channel.effects.count < channel.maxEffects {
                Button(action: { showingEffectBrowser = true }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(TEFonts.mono(10, weight: .bold))
                        Text("ADD EFFECT")
                            .font(TEFonts.mono(10, weight: .bold))
                    }
                    .foregroundColor(colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(colors.controlBackground)
                    .overlay(
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: colors.borderWidth, dash: [4, 2]))
                            .foregroundColor(colors.border)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingEffectBrowser) {
            PluginBrowserSheet(
                channel: channel,
                config: $config,
                category: .effect,
                colors: colors
            )
            .environmentObject(pluginManager)
        }
    }

    // MARK: - MIDI Settings

    private var midiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI INPUT")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)

            // MIDI Channel
            HStack {
                Text("CHANNEL")
                    .font(TEFonts.mono(10))
                    .foregroundColor(colors.primaryText)
                Spacer()
                Menu {
                    ForEach(midiChannelOptions, id: \.self) { ch in
                        Button(action: { config.midiChannel = ch }) {
                            Text(ch == 0 ? "Omni" : "Ch \(ch)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(config.midiChannel == 0 ? "OMNI" : "CH \(config.midiChannel)")
                            .font(TEFonts.mono(10, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(colors.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .menuStyle(.borderlessButton)
            }

            // MIDI Source
            HStack {
                Text("SOURCE")
                    .font(TEFonts.mono(10))
                    .foregroundColor(colors.primaryText)
                Spacer()
                Menu {
                    Button(action: { config.midiSourceName = nil }) {
                        Text("Any")
                    }
                    ForEach(midiEngine.connectedSources) { source in
                        Button(action: { config.midiSourceName = source.name }) {
                            Text(source.name)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(config.midiSourceName?.uppercased() ?? "ANY")
                            .font(TEFonts.mono(10, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(colors.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 180)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .menuStyle(.borderlessButton)
            }

            // Scale filter toggle
            teToggle("SCALE FILTER", isOn: $config.scaleFilterEnabled)

            // ChordPad target toggle
            teToggle("CHORDPAD TARGET", isOn: $config.isChordPadTarget)
        }
        .padding(16)
    }

    // MARK: - Mixer Settings

    private var mixerSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIXER")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)

            // Volume
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("VOLUME")
                        .font(TEFonts.mono(10))
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    Text("\(Int(channel.volume * 100))%")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.primaryText)
                }
                TESlider(value: Binding(
                    get: { Double(channel.volume) },
                    set: { channel.volume = Float($0) }
                ), colors: colors)
                    .frame(height: 24)
            }

            // Pan
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("PAN")
                        .font(TEFonts.mono(10))
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    Text(panLabel)
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.primaryText)
                }
                TESlider(value: Binding(
                    get: { Double((channel.pan + 1) / 2) },  // Convert -1...1 to 0...1
                    set: { channel.pan = Float($0 * 2 - 1) }  // Convert 0...1 back to -1...1
                ), colors: colors)
                    .frame(height: 24)
            }

            // Mute/Solo
            HStack(spacing: 12) {
                teToggle("MUTE", isOn: $channel.isMuted)
                teToggle("SOLO", isOn: $channel.isSoloed)
            }
        }
        .padding(16)
    }

    // MARK: - Helper Views

    private func teToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(isOn.wrappedValue ? colors.accent : colors.controlBackground)
                    .frame(width: 12, height: 12)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                Text(label)
                    .font(TEFonts.mono(10))
                    .foregroundColor(colors.primaryText)
            }
        }
        .buttonStyle(.plain)
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

// MARK: - TE Slider

struct TESlider: View {
    @Binding var value: Double
    let colors: ThemeColors

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)  // Avoid division by zero
            let fillWidth = max(0, width * CGFloat(value.isFinite ? value : 0))

            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))

                // Fill
                Rectangle()
                    .fill(colors.accent)
                    .frame(width: fillWidth)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard width > 0 else { return }
                        let newValue = gesture.location.x / width
                        value = max(0, min(1, Double(newValue)))
                    }
            )
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
    let colors: ThemeColors

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            // Divider
            Rectangle()
                .fill(colors.border)
                .frame(height: colors.borderWidth)

            // Search
            TextField("", text: $searchText, prompt: Text("SEARCH PLUGINS...").foregroundColor(colors.secondaryText))
                .font(TEFonts.mono(12))
                .textFieldStyle(.plain)
                .padding(12)
                .background(colors.controlBackground)

            Rectangle()
                .fill(colors.border)
                .frame(height: colors.borderWidth)

            // Plugin list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPlugins) { plugin in
                        pluginRow(plugin)
                    }
                }
            }
        }
        .frame(minWidth: 450, idealWidth: 500, minHeight: 550, idealHeight: 650)
        .background(colors.windowBackground)
    }

    private var sheetHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(colors.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text(category == .instrument ? "SELECT INSTRUMENT" : "SELECT EFFECT")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundColor(colors.primaryText)

            Spacer()

            // Invisible spacer to balance layout
            Color.clear.frame(width: 80)
        }
        .padding(16)
        .background(colors.sectionBackground)
    }

    private func pluginRow(_ plugin: MacPluginInfo) -> some View {
        Button(action: { loadPlugin(plugin) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(colors.primaryText)
                    Text(plugin.manufacturerName)
                        .font(TEFonts.mono(10))
                        .foregroundColor(colors.secondaryText)
                }

                Spacer()

                if !plugin.isSandboxSafe {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(colors.warning)
                        .help("Not sandbox-safe")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(colors.secondaryText)
            }
            .padding(12)
            .background(colors.controlBackground)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(colors.border.opacity(0.5)),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
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
