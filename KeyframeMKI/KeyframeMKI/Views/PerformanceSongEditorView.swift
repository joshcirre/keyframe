import SwiftUI

/// Editor for creating and editing performance songs - TE Style
struct PerformanceSongEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var midiEngine = MIDIEngine.shared

    @State var song: PerformanceSong
    let isNew: Bool
    let channels: [ChannelConfiguration]

    @State private var showingDeleteConfirmation = false
    @State private var isLearningTrigger = false
    
    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Song name
                        nameSection
                        
                        // Key settings
                        keySection
                        
                        // BPM
                        bpmSection

                        // MIDI Trigger
                        midiTriggerSection

                        // Channel presets
                        channelPresetsSection
                        
                        // Delete button
                        if !isNew {
                            deleteSection
                        }
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
        .confirmationDialog("DELETE SONG", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("DELETE", role: .destructive) {
                sessionStore.deleteSong(song)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(song.name)'?")
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
                    .foregroundColor(TEColors.darkGray)
            }
            
            Spacer()
            
            Text(isNew ? "NEW SONG" : "EDIT SONG")
                .font(TEFonts.display(16, weight: .black))
                .foregroundColor(TEColors.black)
                .tracking(2)
            
            Spacer()
            
            Button {
                saveSong()
            } label: {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(song.name.isEmpty ? TEColors.midGray : TEColors.orange)
            }
            .disabled(song.name.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }
    
    // MARK: - Name Section
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NAME")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            TextField("SONG NAME", text: $song.name)
                .font(TEFonts.display(24, weight: .black))
                .foregroundColor(TEColors.black)
                .textInputAutocapitalization(.characters)
                .padding(16)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.black, lineWidth: 2)
                        .background(TEColors.warmWhite)
                )
        }
    }
    
    // MARK: - Key Section
    
    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KEY")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 16) {
                // Root note picker
                HStack {
                    Text("ROOT")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                    
                    Spacer()
                    
                    // Note buttons
                    HStack(spacing: 4) {
                        ForEach(NoteName.allCases) { note in
                            Button {
                                song.rootNote = note.rawValue
                            } label: {
                                Text(note.displayName)
                                    .font(TEFonts.mono(12, weight: .bold))
                                    .foregroundColor(song.rootNote == note.rawValue ? .white : TEColors.black)
                                    .frame(width: 28, height: 32)
                                    .background(
                                        Rectangle()
                                            .fill(song.rootNote == note.rawValue ? TEColors.orange : TEColors.cream)
                                    )
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(TEColors.black, lineWidth: song.rootNote == note.rawValue ? 0 : 1)
                                    )
                            }
                        }
                    }
                }
                
                // Scale type
                HStack {
                    Text("SCALE")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        ForEach(ScaleType.allCases) { scale in
                            Button {
                                song.scaleType = scale
                            } label: {
                                Text(scale.rawValue.uppercased())
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundColor(song.scaleType == scale ? .white : TEColors.black)
                                    .frame(width: 70, height: 36)
                                    .background(
                                        Rectangle()
                                            .fill(song.scaleType == scale ? TEColors.black : TEColors.cream)
                                    )
                            }
                        }
                    }
                    .overlay(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
                }
                
                // Filter mode
                HStack {
                    Text("MODE")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        ForEach(FilterMode.allCases) { mode in
                            Button {
                                song.filterMode = mode
                            } label: {
                                Text(mode.rawValue.uppercased())
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundColor(song.filterMode == mode ? .white : TEColors.black)
                                    .frame(width: 70, height: 36)
                                    .background(
                                        Rectangle()
                                            .fill(song.filterMode == mode ? TEColors.orange : TEColors.cream)
                                    )
                            }
                        }
                    }
                    .overlay(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
                }
                
                // Mode description
                Text(song.filterMode.description.uppercased())
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundColor(TEColors.midGray)
            }
            .padding(16)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
        }
    }
    
    // MARK: - BPM Section
    
    private var bpmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEMPO")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 16) {
                HStack {
                    Text("BPM")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                    
                    Spacer()
                    
                    if let bpm = song.bpm {
                        Text("\(bpm)")
                            .font(TEFonts.mono(24, weight: .bold))
                            .foregroundColor(TEColors.black)
                    } else {
                        Text("OFF")
                            .font(TEFonts.mono(14, weight: .bold))
                            .foregroundColor(TEColors.midGray)
                    }
                }
                
                // Enable toggle
                Button {
                    song.bpm = song.bpm == nil ? 120 : nil
                } label: {
                    HStack {
                        Text("ENABLE BPM")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(song.bpm != nil ? TEColors.orange : TEColors.lightGray)
                            .frame(width: 48, height: 24)
                            .overlay(
                                Rectangle()
                                    .fill(TEColors.warmWhite)
                                    .frame(width: 20, height: 20)
                                    .offset(x: song.bpm != nil ? 12 : -12)
                            )
                            .overlay(
                                Rectangle()
                                    .strokeBorder(TEColors.black, lineWidth: 2)
                            )
                    }
                }
                .buttonStyle(.plain)
                
                if song.bpm != nil {
                    // Preset buttons
                    HStack(spacing: 8) {
                        ForEach([80, 100, 120, 140, 160], id: \.self) { tempo in
                            Button {
                                song.bpm = tempo
                            } label: {
                                Text("\(tempo)")
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundColor(song.bpm == tempo ? .white : TEColors.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        Rectangle()
                                            .fill(song.bpm == tempo ? TEColors.orange : TEColors.cream)
                                    )
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(TEColors.black, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    
                    // Stepper
                    HStack {
                        Button {
                            song.bpm = max((song.bpm ?? 120) - 1, 40)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(TEColors.black)
                                .frame(width: 44, height: 44)
                                .background(
                                    Rectangle()
                                        .strokeBorder(TEColors.black, lineWidth: 2)
                                )
                        }
                        
                        Spacer()
                        
                        Button {
                            song.bpm = min((song.bpm ?? 120) + 1, 240)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(TEColors.black)
                                .frame(width: 44, height: 44)
                                .background(
                                    Rectangle()
                                        .strokeBorder(TEColors.black, lineWidth: 2)
                                )
                        }
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

    // MARK: - MIDI Trigger Section

    private var midiTriggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI TRIGGER")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 16) {
                // Source picker
                HStack {
                    Text("CONTROLLER")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    let connectedNames = Set(midiEngine.connectedSources.map { $0.name })
                    let isOffline = song.triggerSourceName != nil && !connectedNames.contains(song.triggerSourceName!)

                    Menu {
                        Button("ANY") {
                            song.triggerSourceName = nil
                        }
                        ForEach(midiEngine.connectedSources) { source in
                            Button(source.name.uppercased()) {
                                song.triggerSourceName = source.name
                            }
                        }
                        // Show saved offline source
                        if let savedSource = song.triggerSourceName, isOffline {
                            Button("\(savedSource.uppercased()) (OFFLINE)") {
                                // Keep same selection
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(triggerSourceLabel(isOffline: isOffline))
                                .font(TEFonts.mono(12, weight: .bold))
                                .foregroundColor(isOffline ? TEColors.orange : TEColors.black)
                                .lineLimit(1)

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

                // Channel picker
                HStack {
                    Text("CHANNEL")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    Menu {
                        Button("ANY") {
                            song.triggerChannel = nil
                        }
                        ForEach(1...16, id: \.self) { ch in
                            Button("CH \(ch)") {
                                song.triggerChannel = ch
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(song.triggerChannel.map { "CH \($0)" } ?? "ANY")
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

                // Note Learn button
                HStack {
                    Text("NOTE")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    if let note = song.triggerNote {
                        Text("NOTE \(note)")
                            .font(TEFonts.mono(12, weight: .bold))
                            .foregroundColor(TEColors.black)

                        Button {
                            song.triggerNote = nil
                            song.triggerChannel = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TEColors.red)
                        }
                    }

                    Button {
                        isLearningTrigger.toggle()
                        midiEngine.isLearningMode = isLearningTrigger
                        if isLearningTrigger {
                            // Capture current filter settings
                            let filterSource = song.triggerSourceName
                            let filterChannel = song.triggerChannel

                            midiEngine.onNoteLearn = { note, channel, source in
                                // Only accept if it matches pre-selected filters
                                let sourceMatches = filterSource == nil || filterSource == source
                                let channelMatches = filterChannel == nil || filterChannel == channel

                                guard sourceMatches && channelMatches else { return }

                                song.triggerNote = note
                                song.triggerChannel = channel
                                if song.triggerSourceName == nil {
                                    song.triggerSourceName = source
                                }
                                isLearningTrigger = false
                                midiEngine.isLearningMode = false
                            }
                        }
                    } label: {
                        Text(isLearningTrigger ? "LISTENING..." : "LEARN")
                            .font(TEFonts.mono(11, weight: .bold))
                            .foregroundColor(isLearningTrigger ? .white : TEColors.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isLearningTrigger ? TEColors.orange : TEColors.lightGray)
                            .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
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

    // MARK: - Channel Presets Section
    
    private var channelPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHANNEL PRESETS")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(TEColors.midGray)
                .tracking(2)
            
            VStack(spacing: 8) {
                ForEach(channels) { channel in
                    ChannelStateEditor(
                        channel: channel,
                        state: binding(for: channel)
                    )
                }
            }
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
                Text("DELETE SONG")
                    .font(TEFonts.mono(12, weight: .bold))
            }
            .foregroundColor(TEColors.red)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.red, lineWidth: 2)
            )
        }
    }
    
    // MARK: - Helpers
    
    private func saveSong() {
        if isNew {
            sessionStore.addSong(song)
        } else {
            sessionStore.updateSong(song)
        }
        dismiss()
    }
    
    private func binding(for channel: ChannelConfiguration) -> Binding<ChannelPresetState?> {
        Binding(
            get: {
                song.channelStates.first { $0.channelId == channel.id }
            },
            set: { newState in
                if let newState = newState {
                    if let index = song.channelStates.firstIndex(where: { $0.channelId == channel.id }) {
                        song.channelStates[index] = newState
                    } else {
                        song.channelStates.append(newState)
                    }
                } else {
                    song.channelStates.removeAll { $0.channelId == channel.id }
                }
            }
        )
    }

    private func triggerSourceLabel(isOffline: Bool) -> String {
        guard let sourceName = song.triggerSourceName else {
            return "ANY"
        }
        if isOffline {
            return "\(sourceName.uppercased()) (OFFLINE)"
        }
        return sourceName.uppercased()
    }
}

// MARK: - Channel State Editor

struct ChannelStateEditor: View {
    let channel: ChannelConfiguration
    @Binding var state: ChannelPresetState?
    
    @State private var isExpanded = false
    
    private var isEnabled: Bool { state != nil }
    private var currentVolume: Float { state?.volume ?? channel.volume }
    private var currentMuted: Bool { state?.muted ?? channel.isMuted }
    private var currentEffectBypasses: [Bool] { state?.effectBypasses ?? channel.effects.map { $0.isBypassed } }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row - separate expand and toggle tap areas
            HStack(spacing: 0) {
                // Left side: tappable for expand
                HStack(spacing: 12) {
                    // Channel name
                    Text(channel.name.uppercased())
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(TEColors.black)

                    // Status
                    if isEnabled {
                        Text("\(Int(currentVolume * 100))%")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.orange)

                        if currentMuted {
                            Text("M")
                                .font(TEFonts.mono(10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(TEColors.red)
                        }
                    }

                    Spacer()

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TEColors.darkGray)
                        .frame(width: 24, height: 24)
                }
                .padding(.leading, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Only expand if enabled
                    if isEnabled {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    }
                }

                // Right side: enable toggle (separate tap target)
                Button {
                    if isEnabled {
                        state = nil
                        isExpanded = false
                    } else {
                        state = ChannelPresetState(
                            channelId: channel.id,
                            volume: channel.volume,
                            pan: nil,
                            muted: channel.isMuted,
                            effectBypasses: channel.effects.map { $0.isBypassed }
                        )
                    }
                } label: {
                    Rectangle()
                        .fill(isEnabled ? TEColors.orange : TEColors.lightGray)
                        .frame(width: 48, height: 24)
                        .overlay(
                            Rectangle()
                                .fill(TEColors.warmWhite)
                                .frame(width: 20, height: 20)
                                .offset(x: isEnabled ? 12 : -12)
                        )
                        .overlay(
                            Rectangle()
                                .strokeBorder(TEColors.black, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
            
            // Expanded content
            if isExpanded && isEnabled {
                VStack(spacing: 16) {
                    Rectangle()
                        .fill(TEColors.black)
                        .frame(height: 1)
                    
                    // Volume slider
                    VStack(spacing: 8) {
                        HStack {
                            Text("VOLUME")
                                .font(TEFonts.mono(9, weight: .medium))
                                .foregroundColor(TEColors.midGray)
                            Spacer()
                            Text("\(Int(currentVolume * 100))")
                                .font(TEFonts.mono(14, weight: .bold))
                                .foregroundColor(TEColors.black)
                        }
                        
                        TESlider(value: Binding(
                            get: { currentVolume },
                            set: { newVolume in
                                updateState(volume: newVolume, muted: currentMuted, effectBypasses: currentEffectBypasses)
                            }
                        ))
                    }
                    
                    // Mute toggle
                    Button {
                        updateState(volume: currentVolume, muted: !currentMuted, effectBypasses: currentEffectBypasses)
                    } label: {
                        HStack {
                            Text("MUTE")
                                .font(TEFonts.mono(9, weight: .medium))
                                .foregroundColor(TEColors.midGray)
                            Spacer()
                            Rectangle()
                                .fill(currentMuted ? TEColors.red : TEColors.lightGray)
                                .frame(width: 48, height: 24)
                                .overlay(
                                    Rectangle()
                                        .fill(TEColors.warmWhite)
                                        .frame(width: 20, height: 20)
                                        .offset(x: currentMuted ? 12 : -12)
                                )
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(TEColors.black, lineWidth: 2)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Effect bypasses
                    if !channel.effects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EFFECTS")
                                .font(TEFonts.mono(9, weight: .bold))
                                .foregroundColor(TEColors.midGray)
                            
                            ForEach(Array(channel.effects.enumerated()), id: \.element.id) { index, effect in
                                let isBypassed = index < currentEffectBypasses.count ? currentEffectBypasses[index] : false
                                
                                Button {
                                    var newBypasses = currentEffectBypasses
                                    while newBypasses.count <= index {
                                        newBypasses.append(false)
                                    }
                                    newBypasses[index] = !isBypassed
                                    updateState(volume: currentVolume, muted: currentMuted, effectBypasses: newBypasses)
                                } label: {
                                    HStack(spacing: 8) {
                                        Rectangle()
                                            .fill(!isBypassed ? TEColors.green : TEColors.lightGray)
                                            .frame(width: 8, height: 8)
                                        
                                        Text(effect.name.uppercased())
                                            .font(TEFonts.mono(10, weight: .medium))
                                            .foregroundColor(isBypassed ? TEColors.midGray : TEColors.black)
                                        
                                        Spacer()
                                        
                                        Text(isBypassed ? "OFF" : "ON")
                                            .font(TEFonts.mono(9, weight: .bold))
                                            .foregroundColor(isBypassed ? TEColors.midGray : TEColors.green)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(
            Rectangle()
                .strokeBorder(TEColors.black, lineWidth: 2)
                .background(TEColors.warmWhite)
        )
    }
    
    private func updateState(volume: Float, muted: Bool, effectBypasses: [Bool]) {
        state = ChannelPresetState(
            channelId: channel.id,
            volume: volume,
            pan: nil,
            muted: muted,
            effectBypasses: effectBypasses.isEmpty ? nil : effectBypasses
        )
    }
}

// MARK: - Preview

#Preview {
    PerformanceSongEditorView(
        song: PerformanceSong(name: "Test"),
        isNew: true,
        channels: []
    )
}
