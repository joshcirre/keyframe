import SwiftUI
import AVFoundation
import AudioToolbox

/// Detailed view for editing a channel - Teenage Engineering style
struct ChannelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    var onDelete: (() -> Void)?

    @State private var pluginManager = AUv3HostManager.shared
    @State private var midiEngine = MIDIEngine.shared

    @State private var showingInstrumentPicker = false
    @State private var showingEffectPicker = false
    @State private var showingPluginUI = false
    @State private var pluginViewController: UIViewController?
    @State private var isLearningFaderCC = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header with name
                    channelHeader

                    // Instrument section
                    instrumentSection

                    // Effects chain
                    effectsSection

                    // Mixer controls
                    mixerSection

                    // MIDI routing
                    midiSection

                    // Delete channel button
                    if onDelete != nil {
                        deleteSection
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingInstrumentPicker) {
            PluginBrowserView(mode: .instrument) { component in
                loadInstrument(component)
            }
        }
        .sheet(isPresented: $showingEffectPicker) {
            PluginBrowserView(mode: .effect) { component in
                loadEffect(component)
            }
        }
        .sheet(isPresented: $showingPluginUI, onDismiss: {
            // Sync plugin preset state back to session when UI is dismissed
            SessionStore.shared.syncPluginStateFromAudioEngine()
            SessionStore.shared.saveCurrentSession()
        }) {
            if let vc = pluginViewController {
                PluginUIHostView(viewController: vc)
            }
        }
        .confirmationDialog("Delete Channel", isPresented: $showingDeleteConfirmation) {
            Button("Delete Channel", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the channel and all its settings. This cannot be undone.")
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                Text("DELETE CHANNEL")
                    .font(TEFonts.mono(12, weight: .bold))
            }
            .foregroundStyle(TEColors.red)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.red, lineWidth: 2)
                    .background(TEColors.cream)
            )
        }
    }
    
    // MARK: - Channel Header
    
    private var channelHeader: some View {
        VStack(spacing: 16) {
            HStack {
                Button("CLOSE") {
                    dismiss()
                }
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(TEColors.darkGray)
                
                Spacer()
                
                Text("CHANNEL")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
            }
            
            // Editable name
            TextField("NAME", text: $config.name)
                .font(TEFonts.display(28, weight: .black))
                .foregroundStyle(TEColors.black)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
        }
        .padding(20)
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
    
    // MARK: - Instrument Section
    
    private var instrumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSTRUMENT")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)
            
            if let instrument = config.instrument {
                HStack(spacing: 12) {
                    // Instrument info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instrument.name.uppercased())
                            .font(TEFonts.mono(14, weight: .bold))
                            .foregroundStyle(TEColors.black)
                        
                        Text(instrument.manufacturerName.uppercased())
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }
                    
                    Spacer()
                    
                    // UI button
                    TEButton(label: "UI", style: .secondary) {
                        openInstrumentUI()
                    }
                    
                    // Change button
                    TEButton(label: "CHANGE", style: .secondary) {
                        showingInstrumentPicker = true
                    }
                }
                .padding(16)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                        .background(TEColors.warmWhite)
                )
            } else {
                Button {
                    showingInstrumentPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("SELECT INSTRUMENT")
                            .font(TEFonts.mono(12, weight: .bold))
                    }
                    .foregroundStyle(TEColors.darkGray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.darkGray, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                }
            }
            
            if channel.isLoading {
                HStack {
                    ProgressView()
                        .tint(TEColors.orange)
                    Text("LOADING...")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                }
            }
        }
    }
    
    // MARK: - Effects Section
    
    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EFFECTS")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.midGray)
                    .tracking(2)
                
                Spacer()
                
                Text("\(config.effects.count)/\(channel.maxEffects)")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(config.effects.enumerated()), id: \.element.id) { index, effect in
                    effectSlot(effect: effect, index: index)
                }
                
                if config.effects.count < channel.maxEffects {
                    Button {
                        showingEffectPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("ADD EFFECT")
                                .font(TEFonts.mono(11, weight: .bold))
                        }
                        .foregroundStyle(TEColors.darkGray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.darkGray, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        )
                    }
                }
            }
        }
    }
    
    private func effectSlot(effect: PluginConfiguration, index: Int) -> some View {
        // Use observable effectBypasses array for SwiftUI reactivity
        let isBypassed = channel.effectBypasses[safe: index] ?? false
        
        return HStack(spacing: 12) {
            // Index
            Text("\(index + 1)")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(TEColors.black)
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name.uppercased())
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(isBypassed ? TEColors.midGray : TEColors.black)
                    .lineLimit(1)
                
                Text(effect.manufacturerName.uppercased())
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
            }
            
            Spacer()
            
            // UI button
            Button {
                openEffectUI(at: index)
            } label: {
                Text("UI")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
            }
            
            // Bypass toggle
            Button {
                // Toggle using observable state
                let currentBypass = channel.effectBypasses[safe: index] ?? false
                channel.setEffectBypassed(!currentBypass, at: index)
            } label: {
                Rectangle()
                    .fill(isBypassed ? TEColors.lightGray : TEColors.green)
                    .frame(width: 32, height: 24)
                    .overlay(
                        Text(isBypassed ? "OFF" : "ON")
                            .font(TEFonts.mono(8, weight: .bold))
                            .foregroundStyle(isBypassed ? TEColors.darkGray : .white)
                    )
            }
            
            // Remove
            Button {
                channel.removeEffect(at: index)
                if index < config.effects.count {
                    config.effects.remove(at: index)
                }
                // Ensure channel connections to master are maintained
                AudioEngine.shared.ensureChannelConnections()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TEColors.red)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(12)
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
    
    // MARK: - Mixer Section

    private var mixerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MIXER")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 20) {
                // Volume
                VStack(spacing: 8) {
                    HStack {
                        Text("VOLUME")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                        Spacer()
                        Text("\(Int(channel.volume * 100))")
                            .font(TEFonts.mono(16, weight: .bold))
                            .foregroundStyle(TEColors.black)
                    }

                    TESlider(value: $channel.volume)
                        .onChange(of: channel.volume) { _, newValue in
                            config.volume = newValue
                        }
                }

                // Mute button
                Button {
                    channel.isMuted.toggle()
                    config.isMuted = channel.isMuted
                } label: {
                    Text("MUTE")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(channel.isMuted ? .white : TEColors.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Rectangle()
                                .fill(channel.isMuted ? TEColors.red : TEColors.cream)
                        )
                        .overlay(
                            Rectangle()
                                .strokeBorder(TEColors.red, lineWidth: 2)
                        )
                }
            }
            .padding(16)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
        }
    }
    
    // MARK: - MIDI Section
    
    /// Options for MIDI input source - pre-ordered with NONE first
    private var midiSourceOptions: [(key: String, value: String)] {
        var options: [(key: String, value: String)] = [
            ("__none__", "NONE"),
            ("", "ALL")
        ]
        let connectedNames = Set(MIDIEngine.shared.connectedSources.map { $0.name })

        // Add connected sources (sorted)
        let sortedSources = MIDIEngine.shared.connectedSources.sorted { $0.name < $1.name }
        for source in sortedSources {
            options.append((source.name, source.name.uppercased()))
        }

        // Include saved source name even if disconnected (for MIDI input)
        if let savedSource = config.midiSourceName,
           savedSource != "__none__",
           !connectedNames.contains(savedSource) {
            options.append((savedSource, "\(savedSource.uppercased()) (OFFLINE)"))
        }

        return options
    }

    /// Options for fader control source - uses "NONE" instead of "ALL" as default
    private var faderControlSourceOptions: [(key: String, value: String)] {
        var options: [(key: String, value: String)] = [
            ("__none__", "NONE"),
            ("", "ALL")
        ]
        let connectedNames = Set(MIDIEngine.shared.connectedSources.map { $0.name })

        // Add connected sources (sorted)
        let sortedSources = MIDIEngine.shared.connectedSources.sorted { $0.name < $1.name }
        for source in sortedSources {
            options.append((source.name, source.name.uppercased()))
        }

        // Include saved control source name even if disconnected
        if let savedControl = config.controlSourceName, !connectedNames.contains(savedControl) {
            options.append((savedControl, "\(savedControl.uppercased()) (OFFLINE)"))
        }

        return options
    }
    
    private var midiChannelOptions: [Int: String] {
        var options: [Int: String] = [0: "ALL"]
        for ch in 1...16 {
            options[ch] = "CH \(ch)"
        }
        return options
    }
    
    private var midiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 16) {
                // Source picker - NONE means no MIDI input, ALL means any source
                TEPicker(
                    label: "INPUT",
                    selection: Binding(
                        get: {
                            // Show NONE if midiSourceName is the special none value
                            if config.midiSourceName == "__none__" {
                                return "__none__"
                            }
                            return config.midiSourceName ?? ""
                        },
                        set: { newValue in
                            if newValue == "__none__" {
                                config.midiSourceName = "__none__"
                                channel.midiSourceName = "__none__"
                            } else {
                                let value = newValue.isEmpty ? nil : newValue
                                config.midiSourceName = value
                                channel.midiSourceName = value
                            }
                        }
                    ),
                    orderedOptions: midiSourceOptions
                )
                
                // Channel picker
                TEPicker(
                    label: "CHANNEL",
                    selection: Binding(
                        get: { config.midiChannel },
                        set: { newValue in
                            config.midiChannel = newValue
                            channel.midiChannel = newValue
                        }
                    ),
                    options: midiChannelOptions
                )
                
                // Scale filter toggle
                TEToggle(label: "SCALE FILTER", isOn: Binding(
                    get: { config.scaleFilterEnabled },
                    set: { newValue in
                        config.scaleFilterEnabled = newValue
                        channel.scaleFilterEnabled = newValue
                    }
                ))

                // ChordPad toggle - auto-selects ChordPad controller when enabled
                TEToggle(label: "CHORDPAD TARGET", isOn: Binding(
                    get: { config.isChordPadTarget },
                    set: { newValue in
                        config.isChordPadTarget = newValue
                        channel.isChordPadTarget = newValue
                        // Auto-select ChordPad controller when enabling
                        if newValue && config.midiSourceName == "__none__" {
                            if let chordPadSource = midiEngine.chordPadSourceName {
                                config.midiSourceName = chordPadSource
                                channel.midiSourceName = chordPadSource
                            }
                            config.midiChannel = midiEngine.chordPadChannel
                            channel.midiChannel = midiEngine.chordPadChannel
                        }
                    }
                ))

                // Single Note toggle - auto-selects ChordPad controller when enabled
                TEToggle(label: "SINGLE NOTE TARGET", isOn: Binding(
                    get: { config.isSingleNoteTarget },
                    set: { newValue in
                        config.isSingleNoteTarget = newValue
                        channel.isSingleNoteTarget = newValue
                        // Auto-select ChordPad controller when enabling
                        if newValue && config.midiSourceName == "__none__" {
                            if let chordPadSource = midiEngine.chordPadSourceName {
                                config.midiSourceName = chordPadSource
                                channel.midiSourceName = chordPadSource
                            }
                            config.midiChannel = midiEngine.chordPadChannel
                            channel.midiChannel = midiEngine.chordPadChannel
                        }
                    }
                ))

                // Octave transpose picker
                TEPicker(
                    label: "TRANSPOSE",
                    selection: Binding(
                        get: { config.octaveTranspose },
                        set: { newValue in
                            config.octaveTranspose = newValue
                            channel.octaveTranspose = newValue
                        }
                    ),
                    options: [-3: "-3 OCT", -2: "-2 OCT", -1: "-1 OCT", 0: "0", 1: "+1 OCT", 2: "+2 OCT", 3: "+3 OCT"]
                )

                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 1)

                // Fader Control section
                VStack(spacing: 12) {
                    Text("FADER CONTROL")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundStyle(TEColors.midGray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Control source picker - allows selecting controller before learning CC
                    TEPicker(
                        label: "CONTROLLER",
                        selection: Binding(
                            get: {
                                // Show the actual source name, or NONE if explicitly cleared
                                if config.controlSourceName == nil && config.controlCC == nil {
                                    return "__none__"
                                }
                                return config.controlSourceName ?? ""
                            },
                            set: { newValue in
                                if newValue == "__none__" {
                                    // Clear fader control entirely
                                    config.controlSourceName = nil
                                    config.controlCC = nil
                                    config.controlChannel = nil
                                } else {
                                    // Set the source - user can now learn CC from this source
                                    config.controlSourceName = newValue.isEmpty ? nil : newValue
                                }
                            }
                        ),
                        orderedOptions: faderControlSourceOptions
                    )

                    // CC Learn button and display
                    HStack {
                        Text("CC")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)

                        Spacer()

                        if let cc = config.controlCC {
                            Text("CC \(cc)")
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundStyle(TEColors.black)

                            Button {
                                config.controlCC = nil
                                config.controlChannel = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(TEColors.red)
                            }
                        }

                        Button {
                            isLearningFaderCC.toggle()
                            midiEngine.isCCLearningMode = isLearningFaderCC
                            if isLearningFaderCC {
                                // Capture current filter settings
                                let filterSource = config.controlSourceName
                                let filterChannel = config.controlChannel

                                midiEngine.onCCLearn = { cc, channel, source in
                                    // Only accept if it matches pre-selected filters
                                    let sourceMatches = filterSource == nil || filterSource == source
                                    let channelMatches = filterChannel == nil || filterChannel == channel

                                    guard sourceMatches && channelMatches else { return }

                                    config.controlCC = cc
                                    config.controlChannel = channel
                                    if config.controlSourceName == nil {
                                        config.controlSourceName = source
                                    }
                                    isLearningFaderCC = false
                                    midiEngine.isCCLearningMode = false
                                }
                            }
                        } label: {
                            Text(isLearningFaderCC ? "LISTENING..." : "LEARN")
                                .font(TEFonts.mono(11, weight: .bold))
                                .foregroundStyle(isLearningFaderCC ? .white : TEColors.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isLearningFaderCC ? TEColors.orange : TEColors.lightGray)
                                .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                        }
                    }

                    // Only show channel picker when a CC is mapped
                    if config.controlCC != nil {
                        TEPicker(
                            label: "CHANNEL",
                            selection: Binding(
                                get: { config.controlChannel ?? 0 },
                                set: { config.controlChannel = $0 == 0 ? nil : $0 }
                            ),
                            options: midiChannelOptions
                        )
                    }
                }
            }
            .padding(16)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
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
                // Ensure channel connections to master are maintained after chain rebuild
                AudioEngine.shared.ensureChannelConnections()
            }
        }
    }
    
    private func openInstrumentUI() {
        channel.getInstrumentViewController { vc in
            if let vc = vc {
                pluginViewController = vc
                showingPluginUI = true
            }
        }
    }
    
    private func openEffectUI(at index: Int) {
        channel.getEffectViewController(at: index) { vc in
            if let vc = vc {
                pluginViewController = vc
                showingPluginUI = true
            }
        }
    }
}

// MARK: - TE Custom Controls

struct TEButton: View {
    let label: String
    var style: ButtonStyle = .primary
    let action: () -> Void
    
    enum ButtonStyle {
        case primary, secondary
    }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TEFonts.mono(11, weight: .bold))
                .foregroundStyle(style == .primary ? .white : TEColors.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(style == .primary ? TEColors.orange : TEColors.cream)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                )
        }
    }
}

struct TESlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var centered: Bool = false

    var body: some View {
        GeometryReader { geometry in
            // Guard against zero width during initial layout
            let safeWidth = max(1, geometry.size.width)

            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 8)

                // Fill
                if centered {
                    let center = safeWidth / 2
                    let fillWidth = abs(CGFloat(value) / CGFloat(range.upperBound)) * center
                    let fillX = value >= 0 ? center : center - fillWidth

                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: max(0, fillWidth), height: 8)
                        .offset(x: fillX)
                } else {
                    let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: max(0, safeWidth * CGFloat(normalizedValue)), height: 8)
                }

                // Border
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .frame(height: 8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percent = Float(gesture.location.x / safeWidth)
                        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * min(max(percent, 0), 1)
                        value = newValue
                    }
            )
        }
        .frame(height: 8)
    }
}

struct TEPicker<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(key: T, value: String)]
    @State private var showingPicker = false

    init(label: String, selection: Binding<T>, options: [T: String]) {
        self.label = label
        self._selection = selection
        // Convert to sorted array for stable ordering
        // Sort numerically for Int keys, alphabetically otherwise
        self.options = options.map { (key: $0.key, value: $0.value) }
            .sorted { a, b in
                if let aInt = a.key as? Int, let bInt = b.key as? Int {
                    return aInt < bInt
                }
                return a.value < b.value
            }
    }

    /// Init with pre-ordered options array (preserves order)
    init(label: String, selection: Binding<T>, orderedOptions: [(key: T, value: String)]) {
        self.label = label
        self._selection = selection
        self.options = orderedOptions
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(TEColors.midGray)
            
            Spacer()
            
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(options.first { $0.key == selection }?.value ?? "")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundStyle(TEColors.black)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TEColors.darkGray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingPicker) {
            TEPickerSheet(
                title: label,
                selection: $selection,
                options: options,
                isPresented: $showingPicker
            )
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - TEPicker Sheet (faster than Menu on iOS 18)

struct TEPickerSheet<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(key: T, value: String)]
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.key) { index, option in
                        Button {
                            selection = option.key
                            isPresented = false
                        } label: {
                            HStack {
                                Text(option.value)
                                    .font(TEFonts.mono(14, weight: selection == option.key ? .bold : .medium))
                                    .foregroundStyle(TEColors.black)

                                Spacer()

                                if selection == option.key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(TEColors.orange)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(selection == option.key ? TEColors.orange.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())  // Full-width tap target
                        }
                        .buttonStyle(.plain)

                        // Divider between items
                        if index < options.count - 1 {
                            Rectangle()
                                .fill(TEColors.lightGray.opacity(0.6))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(TEColors.cream)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") {
                        isPresented = false
                    }
                    .font(TEFonts.mono(12, weight: .bold))
                    .foregroundStyle(TEColors.orange)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

struct TEToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                Text(label)
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
                
                Spacer()
                
                Rectangle()
                    .fill(isOn ? TEColors.orange : TEColors.lightGray)
                    .frame(width: 48, height: 24)
                    .overlay(
                        Rectangle()
                            .fill(TEColors.warmWhite)
                            .frame(width: 20, height: 20)
                            .offset(x: isOn ? 12 : -12)
                    )
                    .overlay(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plugin UI Host View

struct PluginUIHostView: View {
    @Environment(\.dismiss) private var dismiss
    let viewController: UIViewController
    
    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(TEColors.black)
                    }
                }
                .padding(16)
                .background(TEColors.warmWhite)
                
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                
                PluginUIViewControllerWrapper(viewController: viewController)
            }
        }
        .preferredColorScheme(.light)
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
