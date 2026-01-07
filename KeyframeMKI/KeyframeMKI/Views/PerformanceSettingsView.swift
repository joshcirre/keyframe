import SwiftUI

/// Settings view for the Performance Engine
struct PerformanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var showingSaveAs = false
    @State private var newSessionName = ""
    @State private var showingResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Audio Section
                Section("Audio") {
                    HStack {
                        Text("Engine Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(audioEngine.isRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(audioEngine.isRunning ? "Running" : "Stopped")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Channels")
                        Spacer()
                        Text("\(audioEngine.channelStrips.count) / \(audioEngine.maxChannels)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Master Volume")
                        Spacer()
                        Text("\(Int(audioEngine.masterVolume * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { audioEngine.masterVolume },
                        set: { audioEngine.masterVolume = $0 }
                    ), in: 0...1)
                    .tint(.cyan)
                }
                
                // MIDI Section
                Section("MIDI") {
                    HStack {
                        Text("Connected Sources")
                        Spacer()
                        Text("\(midiEngine.connectedSources.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(midiEngine.connectedSources) { source in
                        HStack {
                            Image(systemName: "pianokeys")
                                .foregroundColor(.cyan)
                            Text(source.name)
                                .font(.caption)
                        }
                    }
                    
                    if let lastMessage = midiEngine.lastReceivedMessage {
                        HStack {
                            Text("Last Message")
                            Spacer()
                            Text(lastMessage)
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                }
                
                // Scale Filter Section
                Section("Scale Filter") {
                    Toggle("Enabled", isOn: $midiEngine.isScaleFilterEnabled)
                    
                    HStack {
                        Text("Current Key")
                        Spacer()
                        Text("\(NoteName(rawValue: midiEngine.currentRootNote)?.displayName ?? "C") \(midiEngine.currentScaleType.rawValue)")
                            .foregroundColor(.cyan)
                    }
                    
                    Picker("NM2 Channel", selection: $midiEngine.nm2Channel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("Ch \(ch)").tag(ch)
                        }
                    }
                }
                
                // Plugins Section
                Section("Plugins") {
                    HStack {
                        Text("Instruments")
                        Spacer()
                        Text("\(pluginManager.availableInstruments.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Effects")
                        Spacer()
                        Text("\(pluginManager.availableEffects.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        pluginManager.scanForPlugins()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Rescan Plugins")
                        }
                    }
                }
                
                // Session Section
                Section("Session") {
                    HStack {
                        Text("Current Session")
                        Spacer()
                        Text(sessionStore.currentSession.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Songs")
                        Spacer()
                        Text("\(sessionStore.currentSession.songs.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        showingSaveAs = true
                    } label: {
                        Label("Save Session As...", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Keyframe Performance Engine")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Save Session", isPresented: $showingSaveAs) {
                TextField("Session Name", text: $newSessionName)
                Button("Save") {
                    sessionStore.saveSessionAs(newSessionName)
                    newSessionName = ""
                }
                Button("Cancel", role: .cancel) {
                    newSessionName = ""
                }
            } message: {
                Text("Enter a name for this session")
            }
            .confirmationDialog("Reset Session", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    sessionStore.loadSession(Session.defaultSession())
                }
            } message: {
                Text("This will reset to the default session. All changes will be lost.")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PerformanceSettingsView()
}
