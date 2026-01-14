import SwiftUI

/// Large performance-oriented setlist view with current/next song display
struct SetlistView: View {
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var midiEngine: MacMIDIEngine

    @State private var showingSetlistPicker = false
    @State private var showingSetlistEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with setlist selector
            headerSection

            Divider()

            if let setlist = activeSetlist {
                // Current song display
                currentSongSection(setlist: setlist)

                Divider()

                // Navigation controls
                navigationSection(setlist: setlist)

                Divider()

                // Song list
                songListSection(setlist: setlist)
            } else {
                // No setlist selected
                emptyStateView
            }
        }
        .sheet(isPresented: $showingSetlistPicker) {
            SetlistPickerView(
                setlists: sessionStore.currentSession.setlists,
                onSelect: { setlist in
                    sessionStore.setActiveSetlist(setlist)
                    showingSetlistPicker = false
                },
                onEdit: {
                    showingSetlistPicker = false
                    showingSetlistEditor = true
                }
            )
        }
        .sheet(isPresented: $showingSetlistEditor) {
            SetlistEditorView()
                .environmentObject(sessionStore)
        }
    }

    // MARK: - Computed Properties

    private var activeSetlist: Setlist? {
        sessionStore.currentSession.activeSetlist
    }

    private func presetFor(entry: SetlistEntry) -> MacPreset? {
        sessionStore.currentSession.presets.first { $0.id == entry.presetId }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            // Setlist name/selector
            Button(action: { showingSetlistPicker = true }) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text(activeSetlist?.name ?? "Select Setlist")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Edit button
            Button(action: { showingSetlistEditor = true }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit Setlists")

            // Create new setlist
            Button(action: createNewSetlist) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Create New Setlist")
        }
        .padding()
    }

    // MARK: - Current Song

    private func currentSongSection(setlist: Setlist) -> some View {
        VStack(spacing: 16) {
            if let entry = setlist.currentEntry,
               let preset = presetFor(entry: entry) {

                // Large song name
                Text(preset.songName ?? preset.name)
                    .font(.system(size: 48, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // Preset name (if different from song)
                if preset.songName != nil {
                    Text(preset.name)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }

                // Song info row
                HStack(spacing: 24) {
                    // Key
                    if let rootNote = preset.rootNote, let scale = preset.scale {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                            Text("\(rootNote.displayName) \(scale.shortName)")
                        }
                        .font(.title3)
                    }

                    // BPM
                    if let bpm = preset.bpm {
                        HStack(spacing: 4) {
                            Image(systemName: "metronome")
                            Text("\(Int(bpm)) BPM")
                        }
                        .font(.title3)
                    }

                    // Position
                    Text("\(setlist.currentIndex + 1) / \(setlist.entries.count)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                // Performance notes
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                Text("No Song Selected")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Navigation

    private func navigationSection(setlist: Setlist) -> some View {
        HStack(spacing: 32) {
            // Previous
            Button(action: previousSong) {
                VStack {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 48))
                    Text("Previous")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(!setlist.hasPrevious)
            .opacity(setlist.hasPrevious ? 1 : 0.3)
            .keyboardShortcut(.leftArrow, modifiers: [])

            // Next song preview
            if setlist.hasNext,
               let nextIndex = setlist.currentIndex + 1 < setlist.entries.count ? setlist.currentIndex + 1 : nil,
               let nextEntry = setlist.entries[safe: nextIndex],
               let nextPreset = presetFor(entry: nextEntry) {
                VStack(spacing: 4) {
                    Text("NEXT")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(nextPreset.songName ?? nextPreset.name)
                        .font(.title3)
                        .lineLimit(1)
                }
                .frame(minWidth: 200)
            } else {
                VStack(spacing: 4) {
                    Text("NEXT")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("End of Setlist")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 200)
            }

            // Next
            Button(action: nextSong) {
                VStack {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 48))
                    Text("Next")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(!setlist.hasNext)
            .opacity(setlist.hasNext ? 1 : 0.3)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.vertical, 24)
    }

    // MARK: - Song List

    private func songListSection(setlist: Setlist) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(setlist.entries.enumerated()), id: \.element.id) { index, entry in
                    if let preset = presetFor(entry: entry) {
                        SetlistRowView(
                            index: index,
                            entry: entry,
                            preset: preset,
                            isCurrent: index == setlist.currentIndex,
                            onSelect: { goToSong(at: index) }
                        )
                        .id(entry.id)
                    }
                }
            }
            .onChange(of: setlist.currentIndex) { oldValue, newValue in
                if let entry = setlist.entries[safe: newValue] {
                    withAnimation {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Setlist Selected")
                .font(.title2)

            Text("Create or select a setlist to use performance mode.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Create Setlist") {
                    createNewSetlist()
                }
                .buttonStyle(.borderedProminent)

                if !sessionStore.currentSession.setlists.isEmpty {
                    Button("Select Setlist") {
                        showingSetlistPicker = true
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func createNewSetlist() {
        let newSetlist = Setlist(name: "New Setlist")
        sessionStore.addSetlist(newSetlist)
        sessionStore.setActiveSetlist(newSetlist)
        showingSetlistEditor = true
    }

    private func nextSong() {
        if let preset = sessionStore.nextSetlistEntry() {
            activatePreset(preset)
        }
    }

    private func previousSong() {
        if let preset = sessionStore.previousSetlistEntry() {
            activatePreset(preset)
        }
    }

    private func goToSong(at index: Int) {
        if let preset = sessionStore.goToSetlistEntry(at: index) {
            activatePreset(preset)
        }
    }

    private func activatePreset(_ preset: MacPreset) {
        // Apply scale settings
        if let scale = preset.scale, let rootNote = preset.rootNote {
            midiEngine.currentRootNote = rootNote.midiValue
            midiEngine.currentScaleType = scale
        }

        // Apply BPM
        if let bpm = preset.bpm {
            audioEngine.setTempo(bpm)
            midiEngine.currentBPM = Int(bpm)
            midiEngine.sendTapTempo(bpm: Int(bpm))
        }

        // Apply channel states with spillover support
        let spilloverEnabled = sessionStore.currentSession.spilloverEnabled
        for channelState in preset.channelStates {
            if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                channel.applyStateWithSpillover(
                    volume: channelState.volume,
                    pan: channelState.pan,
                    mute: channelState.isMuted,
                    spilloverEnabled: spilloverEnabled
                )
                channel.isSoloed = channelState.isSoloed
            }
        }

        // Send external MIDI messages
        midiEngine.sendExternalMIDIMessages(preset.externalMIDIMessages)

        // Handle backing track
        if let backingTrack = preset.backingTrack, backingTrack.autoStart {
            audioEngine.loadAndPlayBackingTrack(backingTrack)
        } else {
            audioEngine.stopBackingTrack()
        }

        print("SetlistView: Activated preset '\(preset.name)'")
    }
}

// MARK: - Setlist Row View

struct SetlistRowView: View {
    let index: Int
    let entry: SetlistEntry
    let preset: MacPreset
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            // Index
            Text("\(index + 1)")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(width: 30)

            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.songName ?? preset.name)
                    .font(.headline)
                    .foregroundColor(isCurrent ? .accentColor : .primary)

                HStack(spacing: 12) {
                    if let rootNote = preset.rootNote, let scale = preset.scale {
                        Text("\(rootNote.displayName) \(scale.shortName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let bpm = preset.bpm {
                        Text("\(Int(bpm)) BPM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Current indicator
            if isCurrent {
                Image(systemName: "play.fill")
                    .foregroundColor(.accentColor)
            }

            // Pause indicator
            if entry.pauseAfter {
                Image(systemName: "pause.circle")
                    .foregroundColor(.orange)
                    .help("Pause after this song")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

// MARK: - Setlist Picker View

struct SetlistPickerView: View {
    let setlists: [Setlist]
    let onSelect: (Setlist) -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Setlist")
                    .font(.headline)
                Spacer()
                Button("Edit All") { onEdit() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if setlists.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Setlists")
                        .font(.headline)
                    Text("Create a setlist to organize your songs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(setlists) { setlist in
                    Button(action: { onSelect(setlist) }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(setlist.name)
                                    .font(.headline)
                                Text("\(setlist.entries.count) songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
