import SwiftUI
import AVFoundation
import AudioToolbox

/// Detailed view for editing a channel - Teenage Engineering style
struct ChannelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var channel: ChannelStrip
    @Binding var config: ChannelConfiguration
    
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var showingInstrumentPicker = false
    @State private var showingEffectPicker = false
    @State private var showingPluginUI = false
    @State private var pluginViewController: UIViewController?
    
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
        .sheet(isPresented: $showingPluginUI) {
            if let vc = pluginViewController {
                PluginUIHostView(viewController: vc)
            }
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
                .foregroundColor(TEColors.darkGray)
                
                Spacer()
                
                Text("CHANNEL")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.midGray)
            }
            
            // Editable name
            TextField("NAME", text: $config.name)
                .font(TEFonts.display(28, weight: .black))
                .foregroundColor(TEColors.black)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
            
            // Color picker
            HStack(spacing: 8) {
                ForEach(ChannelColor.allCases) { color in
                    Button {
                        config.color = color
                    } label: {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color(color.uiColor))
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 0)
                                    .strokeBorder(TEColors.black, lineWidth: config.color == color ? 3 : 0)
                            )
                    }
                }
            }
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
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            if let instrument = config.instrument {
                HStack(spacing: 12) {
                    // Instrument info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instrument.name.uppercased())
                            .font(TEFonts.mono(14, weight: .bold))
                            .foregroundColor(TEColors.black)
                        
                        Text(instrument.manufacturerName.uppercased())
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
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
                    .foregroundColor(TEColors.darkGray)
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
                        .foregroundColor(TEColors.midGray)
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
                    .foregroundColor(TEColors.midGray)
                    .tracking(2)
                
                Spacer()
                
                Text("\(config.effects.count)/\(channel.maxEffects)")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundColor(TEColors.midGray)
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
                        .foregroundColor(TEColors.darkGray)
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
        let isBypassed = channel.effects[safe: index]?.auAudioUnit.shouldBypassEffect ?? false
        
        return HStack(spacing: 12) {
            // Index
            Text("\(index + 1)")
                .font(TEFonts.mono(12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(TEColors.black)
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name.uppercased())
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(isBypassed ? TEColors.midGray : TEColors.black)
                    .lineLimit(1)
                
                Text(effect.manufacturerName.uppercased())
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.midGray)
            }
            
            Spacer()
            
            // UI button
            Button {
                openEffectUI(at: index)
            } label: {
                Text("UI")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
            }
            
            // Bypass toggle
            Button {
                channel.setEffectBypassed(!isBypassed, at: index)
            } label: {
                Rectangle()
                    .fill(isBypassed ? TEColors.lightGray : TEColors.green)
                    .frame(width: 32, height: 24)
                    .overlay(
                        Text(isBypassed ? "OFF" : "ON")
                            .font(TEFonts.mono(8, weight: .bold))
                            .foregroundColor(isBypassed ? TEColors.darkGray : .white)
                    )
            }
            
            // Remove
            Button {
                channel.removeEffect(at: index)
                config.effects.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TEColors.red)
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
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 20) {
                // Volume
                VStack(spacing: 8) {
                    HStack {
                        Text("VOLUME")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                        Spacer()
                        Text("\(Int(channel.volume * 100))")
                            .font(TEFonts.mono(16, weight: .bold))
                            .foregroundColor(TEColors.black)
                    }
                    
                    TESlider(value: $channel.volume)
                        .onChange(of: channel.volume) { _, newValue in
                            config.volume = newValue
                        }
                }
                
                // Pan
                VStack(spacing: 8) {
                    HStack {
                        Text("PAN")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                        Spacer()
                        Text(panLabel)
                            .font(TEFonts.mono(16, weight: .bold))
                            .foregroundColor(TEColors.black)
                    }
                    
                    TESlider(value: $channel.pan, range: -1...1, centered: true)
                        .onChange(of: channel.pan) { _, newValue in
                            config.pan = newValue
                        }
                }
                
                // Mute/Solo buttons
                HStack(spacing: 12) {
                    Button {
                        channel.isMuted.toggle()
                        config.isMuted = channel.isMuted
                    } label: {
                        Text("MUTE")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(channel.isMuted ? .white : TEColors.red)
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
                    
                    Button {
                        channel.isSoloed.toggle()
                    } label: {
                        Text("SOLO")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(channel.isSoloed ? TEColors.black : TEColors.yellow)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Rectangle()
                                    .fill(channel.isSoloed ? TEColors.yellow : TEColors.cream)
                            )
                            .overlay(
                                Rectangle()
                                    .strokeBorder(TEColors.yellow, lineWidth: 2)
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
    
    private var panLabel: String {
        if channel.pan < -0.01 {
            return "L\(Int(abs(channel.pan) * 100))"
        } else if channel.pan > 0.01 {
            return "R\(Int(channel.pan * 100))"
        } else {
            return "C"
        }
    }
    
    // MARK: - MIDI Section
    
    private var midiSourceOptions: [String: String] {
        var options: [String: String] = ["": "ALL"]
        for source in MIDIEngine.shared.connectedSources {
            options[source.name] = source.name.uppercased()
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
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 16) {
                // Source picker
                TEPicker(
                    label: "INPUT",
                    selection: Binding(
                        get: { config.midiSourceName ?? "" },
                        set: { config.midiSourceName = $0.isEmpty ? nil : $0 }
                    ),
                    options: midiSourceOptions
                )
                
                // Channel picker
                TEPicker(
                    label: "CHANNEL",
                    selection: $config.midiChannel,
                    options: midiChannelOptions
                )
                
                // Scale filter toggle
                TEToggle(label: "SCALE FILTER", isOn: $config.scaleFilterEnabled)
                
                // NM2 toggle
                TEToggle(label: "NM2 CHORDS", isOn: $config.isNM2ChordChannel)
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
                .foregroundColor(style == .primary ? .white : TEColors.black)
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
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(TEColors.lightGray)
                    .frame(height: 8)
                
                // Fill
                if centered {
                    let center = geometry.size.width / 2
                    let fillWidth = abs(CGFloat(value) / CGFloat(range.upperBound)) * center
                    let fillX = value >= 0 ? center : center - fillWidth
                    
                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: fillWidth, height: 8)
                        .offset(x: fillX)
                } else {
                    Rectangle()
                        .fill(TEColors.orange)
                        .frame(width: geometry.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)), height: 8)
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
                        let percent = Float(gesture.location.x / geometry.size.width)
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
    
    init(label: String, selection: Binding<T>, options: [T: String]) {
        self.label = label
        self._selection = selection
        // Convert to sorted array for stable ordering
        self.options = options.map { (key: $0.key, value: $0.value) }
            .sorted { $0.value < $1.value }
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(TEColors.midGray)
            
            Spacer()
            
            Menu {
                ForEach(options, id: \.key) { option in
                    Button {
                        selection = option.key
                    } label: {
                        if selection == option.key {
                            Label(option.value, systemImage: "checkmark")
                        } else {
                            Text(option.value)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(options.first { $0.key == selection }?.value ?? "")
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TEColors.darkGray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                )
            }
        }
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
                    .foregroundColor(TEColors.midGray)
                
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
                            .foregroundColor(.white)
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
