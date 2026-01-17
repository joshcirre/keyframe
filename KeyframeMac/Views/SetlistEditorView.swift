import SwiftUI

/// Editor for creating and modifying setlists
struct SetlistEditorView: View {
    @EnvironmentObject var sessionStore: MacSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSetlistId: UUID?
    @State private var editingSetlist: Setlist?
    @State private var showingDeleteConfirmation = false
    @State private var setlistToDelete: Setlist?

    var body: some View {
        NavigationSplitView {
            // Setlist list sidebar
            setlistListView
        } detail: {
            // Setlist detail/editor
            if let editingSetlist = editingSetlist {
                SetlistDetailEditor(
                    setlist: Binding(
                        get: { editingSetlist },
                        set: { self.editingSetlist = $0 }
                    ),
                    presets: sessionStore.currentSession.presets,
                    onSave: saveSetlist,
                    onCancel: { self.editingSetlist = nil }
                )
            } else {
                Text("Select or create a setlist")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Delete Setlist?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let setlist = setlistToDelete {
                    sessionStore.deleteSetlist(setlist)
                    if editingSetlist?.id == setlist.id {
                        editingSetlist = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete '\(setlistToDelete?.name ?? "")'. This action cannot be undone.")
        }
    }

    // MARK: - Setlist List

    private var setlistListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Setlists")
                    .font(.headline)
                Spacer()
                Button(action: createNewSetlist) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // List
            List(selection: $selectedSetlistId) {
                ForEach(sessionStore.currentSession.setlists) { setlist in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(setlist.name)
                            Text("\(setlist.entries.count) songs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        // Active indicator
                        if sessionStore.currentSession.activeSetlistId == setlist.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .tag(setlist.id)
                    .contextMenu {
                        Button("Edit") {
                            editingSetlist = setlist
                        }
                        Button("Set as Active") {
                            sessionStore.setActiveSetlist(setlist)
                        }
                        Button("Duplicate") {
                            duplicateSetlist(setlist)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            setlistToDelete = setlist
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .onChange(of: selectedSetlistId) { oldValue, newValue in
                if let id = newValue,
                   let setlist = sessionStore.currentSession.setlists.first(where: { $0.id == id }) {
                    editingSetlist = setlist
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
    }

    // MARK: - Actions

    private func createNewSetlist() {
        let newSetlist = Setlist(name: "New Setlist")
        sessionStore.addSetlist(newSetlist)
        editingSetlist = newSetlist
        selectedSetlistId = newSetlist.id
    }

    private func duplicateSetlist(_ setlist: Setlist) {
        var duplicate = setlist
        duplicate.id = UUID()
        duplicate.name = "\(setlist.name) Copy"
        sessionStore.addSetlist(duplicate)
    }

    private func saveSetlist(_ setlist: Setlist) {
        sessionStore.updateSetlist(setlist)
        editingSetlist = nil
    }
}

// MARK: - Setlist Detail Editor

struct SetlistDetailEditor: View {
    @Binding var setlist: Setlist
    let presets: [MacPreset]
    let onSave: (Setlist) -> Void
    let onCancel: () -> Void

    @State private var showingPresetPicker = false
    @State private var editingEntry: SetlistEntry?
    @State private var draggedEntry: SetlistEntry?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                TextField("Setlist Name", text: $setlist.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .frame(maxWidth: 300)

                Spacer()

                Text("\(setlist.entries.count) songs")
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Song list
            if setlist.entries.isEmpty {
                emptyStateView
            } else {
                songListView
            }

            Divider()

            // Footer
            HStack {
                Button("Add Songs...") {
                    showingPresetPicker = true
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(setlist)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .sheet(isPresented: $showingPresetPicker) {
            PresetPickerView(
                presets: presets,
                existingEntries: setlist.entries,
                onAdd: addEntries
            )
        }
        .sheet(item: $editingEntry) { entry in
            EntryNotesEditor(
                entry: entry,
                preset: presets.first { $0.id == entry.presetId },
                onSave: { updatedEntry in
                    if let index = setlist.entries.firstIndex(where: { $0.id == entry.id }) {
                        setlist.entries[index] = updatedEntry
                    }
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
        }
    }

    // MARK: - Song List

    private var songListView: some View {
        List {
            ForEach(Array(setlist.entries.enumerated()), id: \.element.id) { index, entry in
                if let preset = presets.first(where: { $0.id == entry.presetId }) {
                    SetlistEntryRow(
                        index: index,
                        entry: entry,
                        preset: preset,
                        onEdit: { editingEntry = entry },
                        onTogglePause: { togglePause(at: index) }
                    )
                }
            }
            .onMove(perform: moveEntries)
            .onDelete(perform: deleteEntries)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Songs in Setlist")
                .font(.headline)
            Text("Add presets to build your setlist.")
                .font(.body)
                .foregroundColor(.secondary)
            Button("Add Songs...") {
                showingPresetPicker = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Actions

    private func addEntries(_ entries: [SetlistEntry]) {
        setlist.entries.append(contentsOf: entries)
        showingPresetPicker = false
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        setlist.entries.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteEntries(at offsets: IndexSet) {
        setlist.entries.remove(atOffsets: offsets)
    }

    private func togglePause(at index: Int) {
        setlist.entries[index].pauseAfter.toggle()
    }
}

// MARK: - Setlist Entry Row

struct SetlistEntryRow: View {
    let index: Int
    let entry: SetlistEntry
    let preset: MacPreset
    let onEdit: () -> Void
    let onTogglePause: () -> Void

    var body: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Index
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 24)

            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.songName ?? preset.name)
                    .font(.body)

                HStack(spacing: 8) {
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

                    if !entry.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Pause toggle
            Button(action: onTogglePause) {
                Image(systemName: entry.pauseAfter ? "pause.circle.fill" : "pause.circle")
                    .foregroundColor(entry.pauseAfter ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Pause after this song")

            // Edit notes button
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Edit notes")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preset Picker

struct PresetPickerView: View {
    let presets: [MacPreset]
    let existingEntries: [SetlistEntry]
    let onAdd: ([SetlistEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresetIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Songs to Setlist")
                    .font(.headline)
                Spacer()
                Text("\(selectedPresetIds.count) selected")
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Preset list
            List(presets, selection: $selectedPresetIds) { preset in
                HStack {
                    VStack(alignment: .leading) {
                        Text(preset.songName ?? preset.name)
                            .font(.body)

                        HStack(spacing: 8) {
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

                    // Already in setlist indicator
                    if existingEntries.contains(where: { $0.presetId == preset.id }) {
                        Text("In setlist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(preset.id)
            }

            Divider()

            // Footer
            HStack {
                Button("Select All") {
                    selectedPresetIds = Set(presets.map { $0.id })
                }

                Button("Select None") {
                    selectedPresetIds.removeAll()
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Add \(selectedPresetIds.count) Song(s)") {
                    let entries = selectedPresetIds.compactMap { id -> SetlistEntry? in
                        guard presets.contains(where: { $0.id == id }) else { return nil }
                        return SetlistEntry(presetId: id)
                    }
                    onAdd(entries)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPresetIds.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 500, idealHeight: 600)
    }
}

// MARK: - Entry Notes Editor

struct EntryNotesEditor: View {
    let entry: SetlistEntry
    let preset: MacPreset?
    let onSave: (SetlistEntry) -> Void
    let onCancel: () -> Void

    @State private var notes: String
    @State private var pauseAfter: Bool

    init(entry: SetlistEntry, preset: MacPreset?, onSave: @escaping (SetlistEntry) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.preset = preset
        self.onSave = onSave
        self.onCancel = onCancel
        _notes = State(initialValue: entry.notes)
        _pauseAfter = State(initialValue: entry.pauseAfter)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Edit Entry")
                    .font(.headline)
                Spacer()
                if let preset = preset {
                    Text(preset.songName ?? preset.name)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Text("Performance Notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $notes)
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.2))
            }

            // Pause option
            Toggle("Pause after this song", isOn: $pauseAfter)

            Spacer()

            // Footer
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var updated = entry
                    updated.notes = notes
                    updated.pauseAfter = pauseAfter
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 450, minHeight: 280, idealHeight: 350)
    }
}
