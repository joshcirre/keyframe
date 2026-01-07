import SwiftUI

/// Editor for creating and editing performance songs
struct PerformanceSongEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore = SessionStore.shared
    
    @State var song: PerformanceSong
    let isNew: Bool
    let channels: [ChannelConfiguration]
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section("Song Info") {
                    TextField("Song Name", text: $song.name)
                }
                
                // Key Settings
                Section("Key") {
                    Picker("Root Note", selection: $song.rootNote) {
                        ForEach(NoteName.allCases) { note in
                            Text(note.displayName).tag(note.rawValue)
                        }
                    }
                    
                    Picker("Scale", selection: $song.scaleType) {
                        ForEach(ScaleType.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Filter Mode", selection: $song.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(song.filterMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // BPM
                Section {
                    Toggle("Set BPM", isOn: Binding(
                        get: { song.bpm != nil },
                        set: { song.bpm = $0 ? 120 : nil }
                    ))
                    
                    if song.bpm != nil {
                        Stepper("BPM: \(song.bpm ?? 120)", value: Binding(
                            get: { song.bpm ?? 120 },
                            set: { song.bpm = $0 }
                        ), in: 40...240)
                        
                        HStack(spacing: 8) {
                            ForEach([80, 100, 120, 140], id: \.self) { tempo in
                                Button("\(tempo)") {
                                    song.bpm = tempo
                                }
                                .buttonStyle(.bordered)
                                .tint(song.bpm == tempo ? .purple : .gray)
                            }
                        }
                    }
                } header: {
                    Text("Tempo")
                }
                
                // Channel States
                Section {
                    ForEach(channels) { channel in
                        ChannelStateEditor(
                            channel: channel,
                            state: binding(for: channel)
                        )
                    }
                } header: {
                    Text("Channel Presets")
                } footer: {
                    Text("Configure what happens to each channel when this song is selected")
                }
                
                // Delete
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Song")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Song" : "Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSong()
                    }
                    .fontWeight(.semibold)
                    .disabled(song.name.isEmpty)
                }
            }
            .confirmationDialog("Delete Song", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    sessionStore.deleteSong(song)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete '\(song.name)'?")
            }
        }
    }
    
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
}

// MARK: - Channel State Editor

struct ChannelStateEditor: View {
    let channel: ChannelConfiguration
    @Binding var state: ChannelPresetState?
    
    // Computed property to check if this channel has a preset
    private var isEnabled: Bool {
        state != nil
    }
    
    // Current values (from state or channel defaults)
    private var currentVolume: Float {
        state?.volume ?? channel.volume
    }
    
    private var currentMuted: Bool {
        state?.muted ?? channel.isMuted
    }
    
    private var currentEffectBypasses: [Bool] {
        state?.effectBypasses ?? channel.effects.map { $0.isBypassed }
    }
    
    var body: some View {
        DisclosureGroup {
            if isEnabled {
                // Volume
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(currentVolume * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { currentVolume },
                        set: { newVolume in
                            updateState(volume: newVolume, muted: currentMuted, effectBypasses: currentEffectBypasses)
                        }
                    ), in: 0...1)
                    .tint(.cyan)
                }
                
                // Mute
                Toggle("Mute Channel", isOn: Binding(
                    get: { currentMuted },
                    set: { newMuted in
                        updateState(volume: currentVolume, muted: newMuted, effectBypasses: currentEffectBypasses)
                    }
                ))
                
                // Effect Bypasses
                if !channel.effects.isEmpty {
                    Divider()
                    
                    Text("EFFECTS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    ForEach(Array(channel.effects.enumerated()), id: \.element.id) { index, effect in
                        HStack {
                            let isBypassed = index < currentEffectBypasses.count ? currentEffectBypasses[index] : false
                            
                            Circle()
                                .fill(!isBypassed ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            
                            Text(effect.name)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: {
                                    // true = effect ON (not bypassed)
                                    index < currentEffectBypasses.count ? !currentEffectBypasses[index] : true
                                },
                                set: { isOn in
                                    var newBypasses = currentEffectBypasses
                                    // Ensure array is large enough
                                    while newBypasses.count <= index {
                                        newBypasses.append(false)
                                    }
                                    newBypasses[index] = !isOn  // Store as bypassed (inverted)
                                    updateState(volume: currentVolume, muted: currentMuted, effectBypasses: newBypasses)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        } label: {
            HStack {
                Circle()
                    .fill(Color(channel.color.uiColor))
                    .frame(width: 12, height: 12)
                
                Text(channel.name)
                    .fontWeight(.medium)
                
                if isEnabled {
                    Text("• \(Int(currentVolume * 100))%\(currentMuted ? " M" : "")")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                
                if !channel.effects.isEmpty {
                    Text("(\(channel.effects.count) FX)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newEnabled in
                        if newEnabled {
                            // Create new state with channel defaults
                            state = ChannelPresetState(
                                channelId: channel.id,
                                volume: channel.volume,
                                pan: nil,
                                muted: channel.isMuted,
                                effectBypasses: channel.effects.map { $0.isBypassed }
                            )
                        } else {
                            state = nil
                        }
                    }
                ))
                .labelsHidden()
            }
        }
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
