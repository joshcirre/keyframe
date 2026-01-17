import SwiftUI

// MARK: - Song Grid View (formerly PresetGridView)

/// Grid view for selecting and managing songs with their presets/sections
struct PresetGridView: View {
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @ObservedObject var themeProvider: ThemeProvider = .shared

    @State private var showingNewSongSheet = false
    @State private var editingSong: MacSong?
    @State private var songToDelete: MacSong?
    @State private var expandedSongIds: Set<UUID> = []

    private var colors: ThemeColors { themeProvider.colors }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Song List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessionStore.currentSession.songs) { song in
                        SongRow(
                            song: song,
                            isExpanded: expandedSongIds.contains(song.id),
                            isCurrentSong: sessionStore.currentSongId == song.id,
                            currentSectionIndex: sessionStore.currentSongId == song.id ? sessionStore.currentSectionIndex : nil,
                            colors: colors,
                            midiEngine: midiEngine,
                            sessionStore: sessionStore,
                            audioEngine: audioEngine,
                            existingMappings: midiEngine.songTriggerMappings,
                            onToggleExpand: { toggleExpand(song) },
                            onSelectSong: { selectSong(song) },
                            onSelectSection: { sectionIndex in selectSection(song: song, sectionIndex: sectionIndex) },
                            onEdit: { editingSong = song },
                            onDelete: { songToDelete = song },
                            onAddSection: { addSection(to: song) },
                            onMIDILearnSection: { sectionIndex in startMIDILearnForSection(song: song, sectionIndex: sectionIndex) },
                            onUpdateSection: { sectionIndex, updatedSection in updateSection(song: song, sectionIndex: sectionIndex, section: updatedSection) }
                        )
                    }

                    // Add new song button
                    addSongButton
                }
                .padding(16)
            }
            .background(colors.windowBackground)
        }
        .sheet(isPresented: $showingNewSongSheet) {
            SongEditorSheet(
                song: nil,
                onSave: { newSong in
                    var session = sessionStore.currentSession
                    session.songs.append(newSong)
                    sessionStore.currentSession = session
                    sessionStore.saveCurrentSession()
                    expandedSongIds.insert(newSong.id)
                }
            )
            .environmentObject(audioEngine)
            .environmentObject(sessionStore)
        }
        .sheet(item: $editingSong) { song in
            SongEditorSheet(
                song: song,
                onSave: { updatedSong in
                    if let index = sessionStore.currentSession.songs.firstIndex(where: { $0.id == song.id }) {
                        var session = sessionStore.currentSession
                        session.songs[index] = updatedSong
                        sessionStore.currentSession = session
                        sessionStore.saveCurrentSession()
                    }
                }
            )
            .environmentObject(audioEngine)
            .environmentObject(sessionStore)
        }
        .alert("Delete Song?", isPresented: Binding(
            get: { songToDelete != nil },
            set: { if !$0 { songToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { songToDelete = nil }
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    deleteSong(song)
                }
                songToDelete = nil
            }
        } message: {
            if let song = songToDelete {
                Text("Are you sure you want to delete \"\(song.name)\" and all its sections?")
            }
        }
        .onAppear {
            setupMIDITriggerCallbacks()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Current song/section info (takes full width)
            if let songId = sessionStore.currentSongId,
               let song = sessionStore.currentSession.songs.first(where: { $0.id == songId }) {
                HStack(spacing: 8) {
                    Text(song.name.uppercased())
                        .font(TEFonts.mono(12, weight: .bold))
                        .foregroundColor(colors.primaryText)

                    if let sectionIndex = sessionStore.currentSectionIndex,
                       sectionIndex < song.sections.count {
                        Text("›")
                            .foregroundColor(colors.secondaryText)
                        Text(song.sections[sectionIndex].name.uppercased())
                            .font(TEFonts.mono(11))
                            .foregroundColor(colors.secondaryText)
                    }

                    if let bpm = song.bpm {
                        Text("•")
                            .foregroundColor(colors.secondaryText)
                        Text("\(Int(bpm)) BPM")
                            .font(TEFonts.mono(11))
                            .foregroundColor(colors.secondaryText)
                    }

                    if let scale = song.scale, let root = song.rootNote {
                        Text("•")
                            .foregroundColor(colors.secondaryText)
                        Text("\(root.rawValue) \(scale.shortName)")
                            .font(TEFonts.mono(11))
                            .foregroundColor(colors.secondaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colors.accent.opacity(0.15))
                .overlay(Rectangle().strokeBorder(colors.accent, lineWidth: 1))
            }

            Spacer()

            Button(action: { showingNewSongSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("NEW SONG")
                }
                .font(TEFonts.mono(11, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(.white)
                .background(colors.accent)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)
    }

    // MARK: - Add Song Button

    private var addSongButton: some View {
        Button(action: { showingNewSongSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(TEFonts.mono(14, weight: .bold))
                Text("ADD SONG")
                    .font(TEFonts.mono(12, weight: .bold))
            }
            .foregroundColor(colors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(colors.controlBackground)
            .overlay(
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: colors.borderWidth, dash: [6, 3]))
                    .foregroundColor(colors.border.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func toggleExpand(_ song: MacSong) {
        if expandedSongIds.contains(song.id) {
            expandedSongIds.remove(song.id)
        } else {
            expandedSongIds.insert(song.id)
        }
    }

    private func selectSong(_ song: MacSong) {
        let previousSongId = sessionStore.currentSongId

        sessionStore.currentSongId = song.id
        sessionStore.currentSectionIndex = song.sections.isEmpty ? nil : 0

        // Only send song-level settings if we changed songs
        if previousSongId != song.id {
            applySongSettings(song)
        }

        // Apply first section's channel states
        if let firstSection = song.sections.first {
            applySectionSettings(firstSection)
        }

        // Auto-expand the selected song
        expandedSongIds.insert(song.id)
    }

    private func selectSection(song: MacSong, sectionIndex: Int) {
        let previousSongId = sessionStore.currentSongId

        sessionStore.currentSongId = song.id
        sessionStore.currentSectionIndex = sectionIndex

        // Only send song-level settings if we changed songs
        if previousSongId != song.id {
            applySongSettings(song)
        }

        // Apply section's channel states and MIDI
        if sectionIndex < song.sections.count {
            applySectionSettings(song.sections[sectionIndex])
        }
    }

    private func applySongSettings(_ song: MacSong) {
        // Set BPM (song level controls tempo for all sections)
        if let bpm = song.bpm {
            audioEngine.setTempo(bpm)
            midiEngine.currentBPM = Int(bpm)
            midiEngine.sendTapTempo(bpm: Int(bpm))
        }

        // Set scale/key (song level defines the key signature)
        if let scale = song.scale, let rootNote = song.rootNote {
            midiEngine.currentRootNote = rootNote.midiValue
            midiEngine.currentScaleType = scale
        }

        // NOTE: External MIDI messages are now handled at section/preset level only
        // Song level only controls BPM and key signature

        print("PresetGridView: Applied song settings for '\(song.name)' (BPM + key only)")
    }

    private func applySectionSettings(_ section: SongSection) {
        // Apply channel states
        for channelState in section.channelStates {
            if let channel = audioEngine.channelStrips.first(where: { $0.id == channelState.channelId }) {
                channel.volume = channelState.volume
                channel.pan = channelState.pan
                channel.isMuted = channelState.isMuted
                channel.isSoloed = channelState.isSoloed
            }
        }

        // Send section's external MIDI (e.g., Helix snapshot)
        midiEngine.sendExternalMIDIMessages(section.externalMIDIMessages)

        print("PresetGridView: Applied section '\(section.name)'")
    }

    private func addSection(to song: MacSong) {
        guard let index = sessionStore.currentSession.songs.firstIndex(where: { $0.id == song.id }) else { return }

        var updatedSong = song
        let newSection = SongSection(
            name: "Section \(song.sections.count + 1)",
            channelStates: captureCurrentChannelStates(),
            order: song.sections.count
        )
        updatedSong.sections.append(newSection)

        var session = sessionStore.currentSession
        session.songs[index] = updatedSong
        sessionStore.currentSession = session
        sessionStore.saveCurrentSession()
    }

    private func updateSection(song: MacSong, sectionIndex: Int, section: SongSection) {
        guard let songIndex = sessionStore.currentSession.songs.firstIndex(where: { $0.id == song.id }),
              sectionIndex < song.sections.count else { return }

        var updatedSong = song
        updatedSong.sections[sectionIndex] = section

        var session = sessionStore.currentSession
        session.songs[songIndex] = updatedSong
        sessionStore.currentSession = session
        sessionStore.saveCurrentSession()
    }

    private func captureCurrentChannelStates() -> [MacChannelState] {
        audioEngine.channelStrips.map { channel in
            MacChannelState(
                channelId: channel.id,
                volume: channel.volume,
                pan: channel.pan,
                isMuted: channel.isMuted,
                isSoloed: channel.isSoloed
            )
        }
    }

    private func deleteSong(_ song: MacSong) {
        sessionStore.currentSession.songs.removeAll { $0.id == song.id }

        if sessionStore.currentSongId == song.id {
            sessionStore.currentSongId = sessionStore.currentSession.songs.first?.id
            sessionStore.currentSectionIndex = nil
        }

        sessionStore.saveCurrentSession()
    }

    // MARK: - MIDI Learn (Section/Preset Level Only)

    private func startMIDILearnForSection(song: MacSong, sectionIndex: Int) {
        guard sectionIndex < song.sections.count else { return }
        let section = song.sections[sectionIndex]

        // Toggle: if already learning this section, cancel
        if midiEngine.songTriggerLearnTarget?.songId == song.id &&
           midiEngine.songTriggerLearnTarget?.sectionIndex == sectionIndex {
            midiEngine.cancelSongTriggerLearn()
        } else {
            // Set up the callback to save the mapping when learned
            midiEngine.onSongTriggerLearned = { [weak sessionStore] mapping in
                guard let store = sessionStore else { return }
                store.addSongTriggerMapping(mapping)
            }
            midiEngine.startSongTriggerLearn(
                songId: song.id,
                songName: song.name,
                sectionIndex: sectionIndex,
                sectionName: section.name
            )
        }
    }

    private func setupMIDITriggerCallbacks() {
        // When a MIDI trigger fires, select the corresponding song/section
        midiEngine.onSongTriggerFired = { [weak sessionStore, weak audioEngine, weak midiEngine] songId, sectionIndex in
            guard let store = sessionStore,
                  let audio = audioEngine,
                  let midi = midiEngine,
                  let song = store.currentSession.songs.first(where: { $0.id == songId }) else { return }

            DispatchQueue.main.async {
                let previousSongId = store.currentSongId
                store.currentSongId = songId
                store.currentSectionIndex = sectionIndex ?? (song.sections.isEmpty ? nil : 0)

                // Apply song-level settings if song changed (BPM and key only)
                if previousSongId != songId {
                    if let bpm = song.bpm {
                        audio.setTempo(bpm)
                        midi.currentBPM = Int(bpm)
                        midi.sendTapTempo(bpm: Int(bpm))
                    }
                    if let scale = song.scale, let rootNote = song.rootNote {
                        midi.currentRootNote = rootNote.midiValue
                        midi.currentScaleType = scale
                    }
                    // NOTE: External MIDI is now section-level only
                }

                // Apply section settings (includes external MIDI)
                let actualSectionIndex = sectionIndex ?? 0
                if actualSectionIndex < song.sections.count {
                    let section = song.sections[actualSectionIndex]
                    // Apply channel states
                    for channelState in section.channelStates {
                        if let channel = audio.channelStrips.first(where: { $0.id == channelState.channelId }) {
                            channel.volume = channelState.volume
                            channel.pan = channelState.pan
                            channel.isMuted = channelState.isMuted
                            channel.isSoloed = channelState.isSoloed
                        }
                    }
                    // Send section MIDI (external MIDI messages)
                    midi.sendExternalMIDIMessages(section.externalMIDIMessages)
                }

                print("PresetGridView: MIDI triggered song '\(song.name)'\(sectionIndex.map { " section \($0 + 1)" } ?? "")")
            }
        }

        // Load existing mappings
        midiEngine.loadSongTriggerMappings(from: sessionStore.currentSession)
    }
}

// MARK: - Song Row

struct SongRow: View {
    let song: MacSong
    let isExpanded: Bool
    let isCurrentSong: Bool
    let currentSectionIndex: Int?
    let colors: ThemeColors
    let midiEngine: MacMIDIEngine
    let sessionStore: MacSessionStore
    let audioEngine: MacAudioEngine
    let existingMappings: [SongTriggerMapping]
    let onToggleExpand: () -> Void
    let onSelectSong: () -> Void
    let onSelectSection: (Int) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAddSection: () -> Void
    let onMIDILearnSection: (Int) -> Void
    let onUpdateSection: (Int, SongSection) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Song header row
            HStack(spacing: 0) {
                // Expand/collapse button - larger click area
                Button(action: onToggleExpand) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.secondaryText)
                    }
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Song name and info - larger click area
                Button(action: onSelectSong) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name.uppercased())
                                .font(TEFonts.mono(13, weight: .bold))
                                .foregroundColor(isCurrentSong ? colors.accent : colors.primaryText)

                            HStack(spacing: 8) {
                                if let bpm = song.bpm {
                                    Text("\(Int(bpm)) BPM")
                                        .font(TEFonts.mono(10))
                                        .foregroundColor(colors.secondaryText)
                                }
                                if let scale = song.scale, let root = song.rootNote {
                                    Text("\(root.rawValue) \(scale.shortName)")
                                        .font(TEFonts.mono(10))
                                        .foregroundColor(colors.secondaryText)
                                }
                                Text("\(song.sections.count) sections")
                                    .font(TEFonts.mono(10))
                                    .foregroundColor(colors.secondaryText)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Action buttons (show on hover)
                if isHovering {
                    HStack(spacing: 8) {
                        Button(action: onAddSection) {
                            Image(systemName: "plus.circle")
                                .font(TEFonts.mono(12))
                                .foregroundColor(colors.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Add Section")

                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(TEFonts.mono(12))
                                .foregroundColor(colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Song")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(TEFonts.mono(12))
                                .foregroundColor(colors.error)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Song")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrentSong ? colors.accent.opacity(0.1) : colors.controlBackground)
            .overlay(Rectangle().strokeBorder(isCurrentSong ? colors.accent : colors.border, lineWidth: colors.borderWidth))
            .onHover { isHovering = $0 }
            .contextMenu {
                Button(action: onSelectSong) {
                    Label("Select Song", systemImage: "play.circle")
                }
                Divider()
                Button(action: onAddSection) {
                    Label("Add Section", systemImage: "plus.circle")
                }
                Button(action: onEdit) {
                    Label("Edit Song", systemImage: "pencil")
                }
                Divider()
                Button(action: onDelete) {
                    Label("Delete Song", systemImage: "trash")
                }
            }

            // Sections (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(song.sections.enumerated()), id: \.element.id) { index, section in
                        SectionRow(
                            section: section,
                            sectionIndex: index,
                            songId: song.id,
                            songName: song.name,
                            isCurrentSection: isCurrentSong && currentSectionIndex == index,
                            colors: colors,
                            midiEngine: midiEngine,
                            sessionStore: sessionStore,
                            audioEngine: audioEngine,
                            existingMappings: existingMappings,
                            onSelect: { onSelectSection(index) },
                            onMIDILearn: { onMIDILearnSection(index) },
                            onUpdate: { updatedSection in onUpdateSection(index, updatedSection) }
                        )
                    }

                    // Add section button
                    Button(action: onAddSection) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(TEFonts.mono(10))
                            Text("ADD SECTION")
                                .font(TEFonts.mono(10, weight: .medium))
                        }
                        .foregroundColor(colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(colors.windowBackground)
                        .overlay(
                            Rectangle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                                .foregroundColor(colors.border.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 32)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                }
                .background(colors.windowBackground.opacity(0.5))
            }
        }
    }
}

// MARK: - Section Row

struct SectionRow: View {
    let section: SongSection
    let sectionIndex: Int
    let songId: UUID
    let songName: String
    let isCurrentSection: Bool
    let colors: ThemeColors
    let midiEngine: MacMIDIEngine
    let sessionStore: MacSessionStore
    let audioEngine: MacAudioEngine
    let existingMappings: [SongTriggerMapping]
    let onSelect: () -> Void
    let onMIDILearn: () -> Void
    let onUpdate: (SongSection) -> Void

    @State private var isHovering = false
    @State private var showingEditor = false

    /// Check if we're currently learning MIDI for this section
    private var isLearning: Bool {
        midiEngine.songTriggerLearnTarget?.songId == songId &&
        midiEngine.songTriggerLearnTarget?.sectionIndex == sectionIndex
    }

    /// Get existing MIDI trigger mapping for this section
    private var sectionMapping: SongTriggerMapping? {
        existingMappings.first { $0.targetSongId == songId && $0.targetSectionIndex == sectionIndex }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Select button (main area)
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Section number indicator
                    Text("\(sectionIndex + 1)")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(isCurrentSection ? .white : colors.secondaryText)
                        .frame(width: 20, height: 20)
                        .background(isCurrentSection ? colors.accent : colors.controlBackground)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))

                    // Section name
                    Text(section.name.uppercased())
                        .font(TEFonts.mono(11, weight: isCurrentSection ? .bold : .medium))
                        .foregroundColor(isCurrentSection ? colors.accent : colors.primaryText)

                    Spacer()

                    // MIDI trigger mapping indicator
                    if let mapping = sectionMapping {
                        Text(mapping.triggerDescription)
                            .font(TEFonts.mono(8, weight: .bold))
                            .foregroundColor(colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.accent.opacity(0.1))
                            .overlay(Rectangle().strokeBorder(colors.accent.opacity(0.3), lineWidth: 1))
                    }

                    // External MIDI indicator (for messages sent when section selected)
                    if !section.externalMIDIMessages.isEmpty {
                        Text("MIDI OUT")
                            .font(TEFonts.mono(8, weight: .bold))
                            .foregroundColor(colors.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.controlBackground)
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                    }
                }
            }
            .buttonStyle(.plain)

            // Learning indicator
            if isLearning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("LEARNING...")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(.red)
                }
            }

            // Buttons (show on hover or when learning)
            if isHovering || isLearning {
                HStack(spacing: 6) {
                    // MIDI Learn button
                    Button(action: onMIDILearn) {
                        Image(systemName: isLearning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                            .font(TEFonts.mono(11))
                            .foregroundColor(isLearning ? .red : colors.accent)
                    }
                    .buttonStyle(.plain)
                    .help(isLearning ? "Cancel MIDI Learn" : "MIDI Learn Trigger")

                    // Edit button
                    Button(action: { showingEditor = true }) {
                        Image(systemName: "pencil")
                            .font(TEFonts.mono(11))
                            .foregroundColor(colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Section")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isCurrentSection ? colors.accent.opacity(0.05) : Color.clear)
        .padding(.leading, 32)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: onSelect) {
                Label("Select Section", systemImage: "play.circle")
            }
            Button(action: { showingEditor = true }) {
                Label("Edit Section", systemImage: "pencil")
            }
            Divider()
            Button(action: onMIDILearn) {
                Label(isLearning ? "Cancel MIDI Learn" : "MIDI Learn Trigger", systemImage: "antenna.radiowaves.left.and.right")
            }
            if sectionMapping != nil {
                Button(action: {
                    // Clear mapping - handled by parent via learn toggle
                }) {
                    Label("Clear MIDI Trigger", systemImage: "xmark.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SectionEditorSheet(
                section: section,
                sectionIndex: sectionIndex,
                songId: songId,
                songName: songName,
                colors: colors,
                audioEngine: audioEngine,
                midiEngine: midiEngine,
                sessionStore: sessionStore,
                existingMappings: existingMappings,
                onSave: onUpdate
            )
        }
    }
}

// MARK: - Song Editor Sheet

struct SongEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioEngine: MacAudioEngine
    @EnvironmentObject var sessionStore: MacSessionStore
    @EnvironmentObject var midiEngine: MacMIDIEngine
    @ObservedObject var themeProvider: ThemeProvider = .shared

    let song: MacSong?
    let onSave: (MacSong) -> Void

    @State private var name: String = ""
    @State private var bpm: Double = 120
    @State private var useBpm: Bool = true
    @State private var rootNote: NoteName = .c
    @State private var scale: ScaleType = .major
    @State private var useScale: Bool = false
    @State private var sections: [SongSection] = []
    @State private var editingSectionIndex: Int?
    @State private var editingSongId: UUID = UUID()  // Temp ID for new songs

    private var colors: ThemeColors { themeProvider.colors }

    /// The effective song ID (existing song or temp ID for new)
    private var effectiveSongId: UUID {
        song?.id ?? editingSongId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info Section
                    sectionContainer("SONG INFO") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Name
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SONG NAME")
                                    .font(TEFonts.mono(10, weight: .bold))
                                    .foregroundColor(colors.secondaryText)
                                TextField("", text: $name)
                                    .font(TEFonts.mono(14))
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(colors.controlBackground)
                                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                                    .onChange(of: name) { _, newValue in
                                        let uppercased = newValue.uppercased()
                                        if uppercased != newValue {
                                            name = uppercased
                                        }
                                    }
                            }

                            // BPM
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(isOn: $useBpm) {
                                    Text("SET BPM")
                                        .font(TEFonts.mono(10, weight: .bold))
                                        .foregroundColor(colors.secondaryText)
                                }
                                .toggleStyle(.checkbox)

                                if useBpm {
                                    HStack(spacing: 12) {
                                        TEHorizontalSlider(value: $bpm, range: 40...240, colors: colors)
                                            .frame(height: 24)

                                        TextField("", value: $bpm, format: .number)
                                            .font(TEFonts.mono(14, weight: .bold))
                                            .textFieldStyle(.plain)
                                            .frame(width: 50)
                                            .padding(8)
                                            .background(colors.controlBackground)
                                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))

                                        Text("BPM")
                                            .font(TEFonts.mono(11))
                                            .foregroundColor(colors.secondaryText)
                                    }
                                }
                            }

                            // Scale
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(isOn: $useScale) {
                                    Text("SET KEY / SCALE")
                                        .font(TEFonts.mono(10, weight: .bold))
                                        .foregroundColor(colors.secondaryText)
                                }
                                .toggleStyle(.checkbox)

                                if useScale {
                                    HStack(spacing: 12) {
                                        // Root note picker
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("ROOT")
                                                .font(TEFonts.mono(9))
                                                .foregroundColor(colors.secondaryText)
                                            Picker("", selection: $rootNote) {
                                                ForEach(NoteName.allCases, id: \.self) { note in
                                                    Text(note.rawValue).tag(note)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(width: 60)
                                        }

                                        // Scale picker
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("SCALE")
                                                .font(TEFonts.mono(9))
                                                .foregroundColor(colors.secondaryText)
                                            Picker("", selection: $scale) {
                                                ForEach(ScaleType.allCases, id: \.self) { scaleType in
                                                    Text(scaleType.displayName).tag(scaleType)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(width: 140)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Sections (external MIDI is configured at the section level)
                    sectionContainer("SECTIONS") {
                        VStack(alignment: .leading, spacing: 8) {
                            if sections.isEmpty {
                                Text("No sections yet - add intro, verse, chorus, etc.")
                                    .font(TEFonts.mono(11))
                                    .foregroundColor(colors.secondaryText)
                            } else {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                    SectionEditorRow(
                                        section: sections[index],
                                        sectionIndex: index,
                                        songId: effectiveSongId,
                                        songName: name,
                                        colors: colors,
                                        onUpdate: { updated in sections[index] = updated },
                                        onDelete: { sections.remove(at: index) },
                                        audioEngine: audioEngine,
                                        midiEngine: midiEngine,
                                        sessionStore: sessionStore,
                                        existingMappings: midiEngine.songTriggerMappings
                                    )
                                }
                            }

                            Button(action: addNewSection) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("ADD SECTION")
                                }
                                .font(TEFonts.mono(10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundColor(colors.accent)
                                .background(colors.controlBackground)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(style: StrokeStyle(lineWidth: colors.borderWidth, dash: [6, 3]))
                                        .foregroundColor(colors.accent)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(colors.windowBackground)
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 700, idealHeight: 900)
        .background(colors.windowBackground)
        .onAppear {
            if let song = song {
                name = song.name
                sections = song.sections
                if let songBpm = song.bpm {
                    bpm = songBpm
                    useBpm = true
                } else {
                    useBpm = false
                }
                if let songScale = song.scale, let songRoot = song.rootNote {
                    scale = songScale
                    rootNote = songRoot
                    useScale = true
                } else {
                    useScale = false
                }
            } else {
                // New song - create default section
                sections = [SongSection(name: "Intro", channelStates: captureCurrentChannelStates(), order: 0)]
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(colors.primaryText)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text(song == nil ? "NEW SONG" : "EDIT SONG")
                .font(TEFonts.display(14, weight: .bold))
                .foregroundColor(colors.primaryText)

            Spacer()

            Button(action: saveSong) {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(name.isEmpty ? colors.secondaryText : colors.accent)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(name.isEmpty)
        }
        .padding(16)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)
    }

    // MARK: - Helpers

    private func sectionContainer<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)

            content()
                .padding(12)
                .background(colors.sectionBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
        }
    }

    private func captureCurrentChannelStates() -> [MacChannelState] {
        audioEngine.channelStrips.map { channel in
            MacChannelState(
                channelId: channel.id,
                volume: channel.volume,
                pan: channel.pan,
                isMuted: channel.isMuted,
                isSoloed: channel.isSoloed
            )
        }
    }

    private func addNewSection() {
        let newSection = SongSection(
            name: "Section \(sections.count + 1)",
            channelStates: captureCurrentChannelStates(),
            order: sections.count
        )
        sections.append(newSection)
    }

    private func saveSong() {
        // NOTE: External MIDI messages are now configured at the section level only
        // Songs only define BPM and key/scale for all their sections
        let newSong = MacSong(
            id: song?.id ?? UUID(),
            name: name,
            bpm: useBpm ? bpm : nil,
            rootNote: useScale ? rootNote : nil,
            scale: useScale ? scale : nil,
            externalMIDIMessages: [],  // Empty - external MIDI is section-level only
            sections: sections,
            order: song?.order ?? 0
        )

        onSave(newSong)
        dismiss()
    }
}

// MARK: - Section Editor Row

struct SectionEditorRow: View {
    let section: SongSection
    let sectionIndex: Int
    let songId: UUID
    let songName: String
    let colors: ThemeColors
    let onUpdate: (SongSection) -> Void
    let onDelete: () -> Void
    let audioEngine: MacAudioEngine
    let midiEngine: MacMIDIEngine
    let sessionStore: MacSessionStore
    let existingMappings: [SongTriggerMapping]

    @State private var showingEditor = false

    /// Check if we're currently learning MIDI for this section
    private var isLearning: Bool {
        midiEngine.songTriggerLearnTarget?.songId == songId &&
        midiEngine.songTriggerLearnTarget?.sectionIndex == sectionIndex
    }

    /// Get existing MIDI trigger mapping for this section
    private var sectionMapping: SongTriggerMapping? {
        existingMappings.first { $0.targetSongId == songId && $0.targetSectionIndex == sectionIndex }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Section number
            Text("\(sectionIndex + 1)")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.secondaryText)
                .frame(width: 20, height: 20)
                .background(colors.controlBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))

            // Section name and info
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name.uppercased())
                    .font(TEFonts.mono(12, weight: .medium))
                    .foregroundColor(colors.primaryText)

                HStack(spacing: 8) {
                    if !section.channelStates.isEmpty {
                        Text("\(section.channelStates.count) ch")
                            .font(TEFonts.mono(9))
                            .foregroundColor(colors.secondaryText)
                    }
                    if !section.externalMIDIMessages.isEmpty {
                        Text("\(section.externalMIDIMessages.count) MIDI OUT")
                            .font(TEFonts.mono(9))
                            .foregroundColor(colors.accent)
                    }
                }
            }

            Spacer()

            // MIDI trigger mapping
            if let mapping = sectionMapping {
                Text(mapping.triggerDescription)
                    .font(TEFonts.mono(9, weight: .bold))
                    .foregroundColor(colors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(colors.accent.opacity(0.1))
                    .overlay(Rectangle().strokeBorder(colors.accent.opacity(0.3), lineWidth: 1))
            }

            // Learning indicator
            if isLearning {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                    Text("LEARNING")
                        .font(TEFonts.mono(8, weight: .bold))
                        .foregroundColor(.red)
                }
            }

            // MIDI Learn button
            Button(action: toggleMIDILearn) {
                Image(systemName: isLearning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(TEFonts.mono(10))
                    .foregroundColor(isLearning ? .red : colors.accent)
            }
            .buttonStyle(.plain)
            .help(isLearning ? "Cancel MIDI Learn" : "MIDI Learn Trigger")

            // Edit button
            Button(action: { showingEditor = true }) {
                Text("EDIT")
                    .font(TEFonts.mono(10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(TEFonts.mono(10))
                    .foregroundColor(colors.error)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(colors.controlBackground)
        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
        .sheet(isPresented: $showingEditor) {
            SectionEditorSheet(
                section: section,
                sectionIndex: sectionIndex,
                songId: songId,
                songName: songName,
                colors: colors,
                audioEngine: audioEngine,
                midiEngine: midiEngine,
                sessionStore: sessionStore,
                existingMappings: existingMappings,
                onSave: onUpdate
            )
        }
    }

    private func toggleMIDILearn() {
        if isLearning {
            midiEngine.cancelSongTriggerLearn()
        } else {
            midiEngine.onSongTriggerLearned = { [sessionStore] mapping in
                sessionStore.addSongTriggerMapping(mapping)
            }
            midiEngine.startSongTriggerLearn(
                songId: songId,
                songName: songName,
                sectionIndex: sectionIndex,
                sectionName: section.name
            )
        }
    }
}

// MARK: - Section Editor Sheet (Full Editor)

struct SectionEditorSheet: View {
    @Environment(\.dismiss) var dismiss

    let section: SongSection
    let sectionIndex: Int
    let songId: UUID
    let songName: String
    let colors: ThemeColors
    let audioEngine: MacAudioEngine
    let midiEngine: MacMIDIEngine
    let sessionStore: MacSessionStore
    let existingMappings: [SongTriggerMapping]
    let onSave: (SongSection) -> Void

    @State private var name: String = ""
    @State private var channelStates: [MacChannelState] = []
    @State private var externalMIDIMessages: [ExternalMIDIMessage] = []
    @State private var showingMIDIEditor = false
    @State private var showingHelixPicker = false

    /// Check if we're currently learning MIDI for this section
    private var isLearning: Bool {
        midiEngine.songTriggerLearnTarget?.songId == songId &&
        midiEngine.songTriggerLearnTarget?.sectionIndex == sectionIndex
    }

    /// Get existing MIDI trigger mapping for this section
    private var sectionMapping: SongTriggerMapping? {
        existingMappings.first { $0.targetSongId == songId && $0.targetSectionIndex == sectionIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            // Content - two columns
            HStack(spacing: 0) {
                // Left column: Channel States
                channelStatesColumn

                // Divider
                Rectangle()
                    .fill(colors.border)
                    .frame(width: colors.borderWidth)

                // Right column: MIDI & Settings
                midiColumn
            }
        }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 600, idealHeight: 700)
        .background(colors.windowBackground)
        .onAppear {
            name = section.name
            externalMIDIMessages = section.externalMIDIMessages

            // Initialize channel states from section or from current mixer
            if section.channelStates.isEmpty {
                channelStates = audioEngine.channelStrips.map { channel in
                    MacChannelState(
                        channelId: channel.id,
                        volume: channel.volume,
                        pan: channel.pan,
                        isMuted: channel.isMuted,
                        isSoloed: channel.isSoloed
                    )
                }
            } else {
                channelStates = section.channelStates
            }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(colors.primaryText)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer()

            // Section name field
            HStack(spacing: 8) {
                Text("SECTION:")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(colors.secondaryText)
                TextField("", text: $name)
                    .font(TEFonts.mono(14, weight: .bold))
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                    .onChange(of: name) { _, newValue in
                        let uppercased = newValue.uppercased()
                        if uppercased != newValue {
                            name = uppercased
                        }
                    }
            }

            // MIDI Learn section
            HStack(spacing: 8) {
                // Current mapping indicator
                if let mapping = sectionMapping {
                    Text(mapping.triggerDescription)
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(colors.accent.opacity(0.1))
                        .overlay(Rectangle().strokeBorder(colors.accent.opacity(0.5), lineWidth: 1))
                }

                // Learning indicator
                if isLearning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("LEARNING...")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(.red)
                    }
                }

                // MIDI Learn button
                Button(action: toggleMIDILearn) {
                    HStack(spacing: 4) {
                        Image(systemName: isLearning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                        Text(isLearning ? "CANCEL" : "MIDI LEARN")
                    }
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(isLearning ? .red : colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isLearning ? Color.red.opacity(0.1) : colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(isLearning ? Color.red : colors.accent, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: saveSection) {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(name.isEmpty ? colors.secondaryText : colors.accent)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(name.isEmpty)
        }
        .padding(16)
        .background(colors.sectionBackground)
        .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)
    }

    private func toggleMIDILearn() {
        if isLearning {
            midiEngine.cancelSongTriggerLearn()
        } else {
            midiEngine.onSongTriggerLearned = { [sessionStore] mapping in
                sessionStore.addSongTriggerMapping(mapping)
            }
            midiEngine.startSongTriggerLearn(
                songId: songId,
                songName: songName,
                sectionIndex: sectionIndex,
                sectionName: name
            )
        }
    }

    // MARK: - Channel States Column

    private var channelStatesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Text("CHANNEL STATES")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(colors.primaryText)

                Spacer()

                Button(action: captureCurrentMixer) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("CAPTURE MIXER")
                    }
                    .font(TEFonts.mono(9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colors.accent)
                    .foregroundColor(.white)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(colors.sectionBackground)
            .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)

            // Channel list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(channelStates.enumerated()), id: \.element.id) { index, state in
                        ChannelStateEditorRow(
                            channelState: $channelStates[index],
                            channelName: channelName(for: state.channelId),
                            colors: colors
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 500)
    }

    // MARK: - MIDI Column

    private var midiColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            Text("SECTION MIDI")
                .font(TEFonts.mono(11, weight: .bold))
                .foregroundColor(colors.primaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.sectionBackground)
                .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Helix quick-add section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HELIX / SNAPSHOTS")
                            .font(TEFonts.mono(9, weight: .bold))
                            .foregroundColor(colors.secondaryText)

                        Button(action: { showingHelixPicker = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "guitars")
                                Text("ADD HELIX SNAPSHOT")
                            }
                            .font(TEFonts.mono(10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(colors.accent)
                            .background(colors.controlBackground)
                            .overlay(Rectangle().strokeBorder(colors.accent, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .background(colors.border)

                    // Current MIDI messages
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MIDI MESSAGES")
                            .font(TEFonts.mono(9, weight: .bold))
                            .foregroundColor(colors.secondaryText)

                        if externalMIDIMessages.isEmpty {
                            Text("No MIDI messages configured")
                                .font(TEFonts.mono(10))
                                .foregroundColor(colors.secondaryText)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(externalMIDIMessages) { message in
                                HStack {
                                    Text(message.displayDescription)
                                        .font(TEFonts.mono(11))
                                        .foregroundColor(colors.primaryText)
                                    Spacer()
                                    Button(action: { externalMIDIMessages.removeAll { $0.id == message.id } }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(colors.error)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(colors.controlBackground)
                                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                            }
                        }

                        Button(action: { showingMIDIEditor = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("ADD CUSTOM MIDI")
                            }
                            .font(TEFonts.mono(10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundColor(colors.secondaryText)
                            .background(colors.controlBackground)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                                    .foregroundColor(colors.border)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 350)
        .sheet(isPresented: $showingMIDIEditor) {
            TEMIDIMessageEditorSheet(colors: colors) { newMessage in
                externalMIDIMessages.append(newMessage)
            }
        }
        .sheet(isPresented: $showingHelixPicker) {
            TEHelixSnapshotPickerSheet(colors: colors) { helixMessages in
                externalMIDIMessages.append(contentsOf: helixMessages)
            }
        }
    }

    // MARK: - Helpers

    private func channelName(for channelId: UUID) -> String {
        audioEngine.channelStrips.first { $0.id == channelId }?.name ?? "Unknown"
    }

    private func captureCurrentMixer() {
        channelStates = audioEngine.channelStrips.map { channel in
            MacChannelState(
                channelId: channel.id,
                volume: channel.volume,
                pan: channel.pan,
                isMuted: channel.isMuted,
                isSoloed: channel.isSoloed
            )
        }
    }

    private func saveSection() {
        var updatedSection = section
        updatedSection.name = name
        updatedSection.channelStates = channelStates
        updatedSection.externalMIDIMessages = externalMIDIMessages
        onSave(updatedSection)
        dismiss()
    }
}

// MARK: - Channel State Editor Row

struct ChannelStateEditorRow: View {
    @Binding var channelState: MacChannelState
    let channelName: String
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            // Channel name
            Text(channelName.uppercased())
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundColor(colors.primaryText)
                .frame(width: 100, alignment: .leading)

            // Mute toggle
            Button(action: { channelState.isMuted.toggle() }) {
                Text("M")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(channelState.isMuted ? .white : colors.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(channelState.isMuted ? colors.error : colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Solo toggle
            Button(action: { channelState.isSoloed.toggle() }) {
                Text("S")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(channelState.isSoloed ? .black : colors.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(channelState.isSoloed ? colors.accent : colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Volume slider
            VStack(alignment: .leading, spacing: 2) {
                Text("VOL")
                    .font(TEFonts.mono(8))
                    .foregroundColor(colors.secondaryText)
                HStack(spacing: 8) {
                    TEHorizontalSlider(
                        value: Binding(
                            get: { Double(channelState.volume) },
                            set: { channelState.volume = Float($0) }
                        ),
                        range: 0...1,
                        colors: colors
                    )
                    .frame(height: 16)

                    Text("\(Int(channelState.volume * 100))%")
                        .font(TEFonts.mono(9))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: 35, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity)

            // Pan slider
            VStack(alignment: .leading, spacing: 2) {
                Text("PAN")
                    .font(TEFonts.mono(8))
                    .foregroundColor(colors.secondaryText)
                HStack(spacing: 8) {
                    TEHorizontalSlider(
                        value: Binding(
                            get: { Double(channelState.pan) },
                            set: { channelState.pan = Float($0) }
                        ),
                        range: -1...1,
                        colors: colors
                    )
                    .frame(width: 80, height: 16)

                    Text(panLabel)
                        .font(TEFonts.mono(9))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.controlBackground)
        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
    }

    private var panLabel: String {
        if abs(channelState.pan) < 0.05 {
            return "C"
        } else if channelState.pan < 0 {
            return "L\(Int(abs(channelState.pan) * 100))"
        } else {
            return "R\(Int(channelState.pan * 100))"
        }
    }
}

// MARK: - TE Horizontal Slider

struct TEHorizontalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: ThemeColors

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(colors.controlBackground)

                // Fill
                Rectangle()
                    .fill(colors.accent)
                    .frame(width: geometry.size.width * normalizedValue)
            }
            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = Double(gesture.location.x / geometry.size.width)
                        value = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, newValue))
                    }
            )
        }
    }

    private var normalizedValue: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
}

// MARK: - TE MIDI Message Editor Sheet

struct TEMIDIMessageEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    let colors: ThemeColors
    let onSave: (ExternalMIDIMessage) -> Void

    @State private var messageType: MIDIMessageType = .programChange
    @State private var data1: Int = 0
    @State private var data2: Int = 127

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("CANCEL") { dismiss() }
                    .font(TEFonts.mono(11, weight: .bold))
                    .buttonStyle(.plain)

                Spacer()

                Text("ADD MIDI MESSAGE")
                    .font(TEFonts.display(14, weight: .bold))

                Spacer()

                Button("ADD") { addMessage() }
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(colors.accent)
                    .buttonStyle(.plain)
            }
            .padding(16)
            .background(colors.sectionBackground)

            VStack(alignment: .leading, spacing: 16) {
                // Type picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("MESSAGE TYPE")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.secondaryText)
                    Picker("", selection: $messageType) {
                        Text("Program Change").tag(MIDIMessageType.programChange)
                        Text("Control Change").tag(MIDIMessageType.controlChange)
                        Text("Note On").tag(MIDIMessageType.noteOn)
                        Text("Note Off").tag(MIDIMessageType.noteOff)
                    }
                    .labelsHidden()
                }

                // Data 1
                VStack(alignment: .leading, spacing: 4) {
                    Text(messageType.data1Label.uppercased())
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.secondaryText)
                    HStack {
                        Stepper("\(data1)", value: $data1, in: 0...127)
                            .font(TEFonts.mono(12))
                        Spacer()
                    }
                }

                // Data 2
                if !messageType.data2Label.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(messageType.data2Label.uppercased())
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.secondaryText)
                        HStack {
                            Stepper("\(data2)", value: $data2, in: 0...127)
                                .font(TEFonts.mono(12))
                            Spacer()
                        }
                    }
                }

                // Preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(colors.secondaryText)
                    Text(ExternalMIDIMessage(type: messageType, data1: data1, data2: data2).displayDescription)
                        .font(TEFonts.mono(12))
                        .padding(8)
                        .background(colors.controlBackground)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                }
            }
            .padding(16)

            Spacer()
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 350, idealHeight: 400)
        .background(colors.windowBackground)
    }

    private func addMessage() {
        let message = ExternalMIDIMessage(type: messageType, data1: data1, data2: data2)
        onSave(message)
        dismiss()
    }
}

// MARK: - TE Helix Preset Picker Sheet (for Songs - full preset selection)

struct TEHelixPresetPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let colors: ThemeColors
    let onSave: ([ExternalMIDIMessage]) -> Void

    @State private var setlist: Int = 0
    @State private var preset: Int = 0
    @State private var snapshot: Int = 0
    @State private var includeSetlist: Bool = true
    @State private var includeSnapshot: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Text("CANCEL")
                        .font(TEFonts.mono(11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(colors.primaryText)
                        .background(colors.controlBackground)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("HELIX PRESET")
                    .font(TEFonts.display(14, weight: .bold))
                    .foregroundColor(colors.primaryText)

                Spacer()

                Button(action: { addHelixPreset() }) {
                    Text("ADD")
                        .font(TEFonts.mono(11, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(colors.accent)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(colors.sectionBackground)
            .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Setlist section
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $includeSetlist) {
                            Text("CHANGE SETLIST")
                                .font(TEFonts.mono(10, weight: .bold))
                                .foregroundColor(colors.primaryText)
                        }
                        .toggleStyle(.checkbox)

                        if includeSetlist {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SELECT SETLIST")
                                    .font(TEFonts.mono(9))
                                    .foregroundColor(colors.secondaryText)

                                // Grid of setlist buttons instead of picker
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 8) {
                                    ForEach(HelixSetlist.allCases, id: \.rawValue) { s in
                                        Button(action: { setlist = s.rawValue }) {
                                            Text(s.shortName)
                                                .font(TEFonts.mono(10, weight: .bold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .foregroundColor(setlist == s.rawValue ? .white : colors.primaryText)
                                                .background(setlist == s.rawValue ? colors.accent : colors.controlBackground)
                                                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(12)
                            .background(colors.controlBackground.opacity(0.5))
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                        }
                    }

                    // Preset section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRESET NUMBER")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.primaryText)

                        HStack(spacing: 12) {
                            // Preset number input
                            HStack(spacing: 8) {
                                Button(action: { if preset > 0 { preset -= 1 } }) {
                                    Image(systemName: "minus")
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .frame(width: 30, height: 30)
                                        .background(colors.controlBackground)
                                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)

                                Text("\(preset + 1)")
                                    .font(TEFonts.mono(20, weight: .bold))
                                    .foregroundColor(colors.accent)
                                    .frame(width: 60)

                                Button(action: { if preset < 127 { preset += 1 } }) {
                                    Image(systemName: "plus")
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .frame(width: 30, height: 30)
                                        .background(colors.controlBackground)
                                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }

                            Text("(PC \(preset))")
                                .font(TEFonts.mono(11))
                                .foregroundColor(colors.secondaryText)

                            Spacer()

                            // Slider for quick selection
                            TEHorizontalSlider(
                                value: Binding(
                                    get: { Double(preset) },
                                    set: { preset = Int($0) }
                                ),
                                range: 0...127,
                                colors: colors
                            )
                            .frame(width: 200, height: 20)
                        }
                    }

                    // Snapshot section
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $includeSnapshot) {
                            Text("INCLUDE SNAPSHOT")
                                .font(TEFonts.mono(10, weight: .bold))
                                .foregroundColor(colors.primaryText)
                        }
                        .toggleStyle(.checkbox)

                        if includeSnapshot {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SELECT SNAPSHOT")
                                    .font(TEFonts.mono(9))
                                    .foregroundColor(colors.secondaryText)

                                // Grid of snapshot buttons
                                HStack(spacing: 6) {
                                    ForEach(0..<8, id: \.self) { s in
                                        Button(action: { snapshot = s }) {
                                            Text("\(s + 1)")
                                                .font(TEFonts.mono(12, weight: .bold))
                                                .frame(width: 40, height: 36)
                                                .foregroundColor(snapshot == s ? .white : colors.primaryText)
                                                .background(snapshot == s ? colors.accent : colors.controlBackground)
                                                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(12)
                            .background(colors.controlBackground.opacity(0.5))
                            .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                        }
                    }

                    // Preview section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MIDI MESSAGES TO SEND")
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundColor(colors.primaryText)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(previewMessages, id: \.displayDescription) { msg in
                                HStack {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(colors.accent)
                                    Text(msg.displayDescription)
                                        .font(TEFonts.mono(11))
                                        .foregroundColor(colors.primaryText)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.controlBackground)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 500, idealHeight: 550)
        .background(colors.windowBackground)
    }

    private var previewMessages: [ExternalMIDIMessage] {
        var messages: [ExternalMIDIMessage] = []
        if includeSetlist {
            messages.append(.helixSetlist(setlist))
        }
        messages.append(.helixPreset(preset))
        if includeSnapshot {
            messages.append(.helixSnapshot(snapshot))
        }
        return messages
    }

    private func addHelixPreset() {
        onSave(previewMessages)
        dismiss()
    }
}

// MARK: - TE Helix Snapshot Picker Sheet (for Sections - snapshot only)

struct TEHelixSnapshotPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let colors: ThemeColors
    let onSave: ([ExternalMIDIMessage]) -> Void

    @State private var snapshot: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Text("CANCEL")
                        .font(TEFonts.mono(11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(colors.primaryText)
                        .background(colors.controlBackground)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("HELIX SNAPSHOT")
                    .font(TEFonts.display(14, weight: .bold))
                    .foregroundColor(colors.primaryText)

                Spacer()

                Button(action: { addSnapshot() }) {
                    Text("ADD")
                        .font(TEFonts.mono(11, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(colors.accent)
                        .overlay(Rectangle().strokeBorder(colors.border, lineWidth: colors.borderWidth))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(colors.sectionBackground)
            .overlay(Rectangle().frame(height: colors.borderWidth).foregroundColor(colors.border), alignment: .bottom)

            VStack(alignment: .leading, spacing: 20) {
                Text("Select a Helix snapshot to recall when this section is selected.")
                    .font(TEFonts.mono(11))
                    .foregroundColor(colors.secondaryText)

                // Snapshot grid - 2 rows of 4
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { s in
                            snapshotButton(s)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(4..<8, id: \.self) { s in
                            snapshotButton(s)
                        }
                    }
                }

                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("MIDI MESSAGE")
                        .font(TEFonts.mono(9, weight: .bold))
                        .foregroundColor(colors.secondaryText)

                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(colors.accent)
                        Text(ExternalMIDIMessage.helixSnapshot(snapshot).displayDescription)
                            .font(TEFonts.mono(11))
                            .foregroundColor(colors.primaryText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.controlBackground)
                    .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
                }
            }
            .padding(20)

            Spacer()
        }
        .frame(minWidth: 400, idealWidth: 420, minHeight: 320, idealHeight: 350)
        .background(colors.windowBackground)
    }

    private func snapshotButton(_ index: Int) -> some View {
        Button(action: { snapshot = index }) {
            VStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(TEFonts.mono(18, weight: .bold))
                Text("SNAPSHOT")
                    .font(TEFonts.mono(8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .foregroundColor(snapshot == index ? .white : colors.primaryText)
            .background(snapshot == index ? colors.accent : colors.controlBackground)
            .overlay(Rectangle().strokeBorder(snapshot == index ? colors.accent : colors.border, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func addSnapshot() {
        onSave([.helixSnapshot(snapshot)])
        dismiss()
    }
}

// MARK: - ScaleType Extension

extension ScaleType {
    var shortName: String {
        switch self {
        case .major: return "Maj"
        case .minor: return "Min"
        case .harmonicMinor: return "HMin"
        case .melodicMinor: return "Mel"
        case .dorian: return "Dor"
        case .phrygian: return "Phr"
        case .lydian: return "Lyd"
        case .mixolydian: return "Mix"
        case .locrian: return "Loc"
        case .pentatonicMajor: return "PntM"
        case .pentatonicMinor: return "Pntm"
        case .blues: return "Blu"
        case .chromatic: return "Chr"
        }
    }
}
