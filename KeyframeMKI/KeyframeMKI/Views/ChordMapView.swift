import SwiftUI

struct ChordMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var songStore: SharedSongStore
    @EnvironmentObject var midiService: MIDIService
    
    @StateObject private var viewModel: ChordMapViewModel
    @State private var selectedButton: Int?
    @State private var previewRootNote: Int = 0
    @State private var previewScaleType: ScaleType = .major
    
    init() {
        _viewModel = StateObject(wrappedValue: ChordMapViewModel(mapping: SharedSongStore.shared.chordMapping))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MIDI Learn Section
                    MIDILearnSection(viewModel: viewModel, midiService: midiService)
                    
                    // Preview key selector
                    PreviewKeySection(
                        rootNote: $previewRootNote,
                        scaleType: $previewScaleType
                    )
                    
                    // NM2 Grid
                    NM2GridSection(
                        viewModel: viewModel,
                        selectedButton: $selectedButton,
                        rootNote: previewRootNote,
                        scaleType: previewScaleType
                    )
                    
                    // Degree selector (when button selected)
                    if selectedButton != nil {
                        DegreeSelector(
                            viewModel: viewModel,
                            selectedButton: $selectedButton,
                            rootNote: previewRootNote,
                            scaleType: previewScaleType
                        )
                    }
                    
                    // Settings section
                    SettingsSection(viewModel: viewModel)
                    
                    // Quick presets
                    QuickPresetsSection(viewModel: viewModel)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("NM2 Chord Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        midiService.isLearningMode = false
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        midiService.isLearningMode = false
                        songStore.updateChordMapping(viewModel.mapping)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Use active song's key for preview if available
                if let song = songStore.activeSong {
                    previewRootNote = song.rootNote
                    previewScaleType = song.scaleType
                }
                
                // Setup MIDI learn callback
                midiService.onNoteLearn = { note, channel, velocity in
                    if viewModel.isLearning {
                        viewModel.noteWasLearned(note: note, channel: channel)
                        midiService.isLearningMode = false
                    }
                }
            }
            .onDisappear {
                midiService.isLearningMode = false
                midiService.onNoteLearn = nil
            }
        }
    }
}

// MARK: - MIDI Learn Section

struct MIDILearnSection: View {
    @ObservedObject var viewModel: ChordMapViewModel
    @ObservedObject var midiService: MIDIService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MIDI LEARN")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(midiService.isListeningForInput ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(midiService.isListeningForInput ? "Ready" : "No Input")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Press a degree button below, then press a button on your NM2 to assign it.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Learning indicator
            if viewModel.isLearning, let degree = viewModel.learningForDegree {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Waiting for MIDI... Press button for Degree \(degree)")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        viewModel.stopLearning()
                        midiService.isLearningMode = false
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                )
            }
            
            // Last learned note display
            if let lastNote = viewModel.lastLearnedNote, let lastChannel = viewModel.lastLearnedChannel {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Text("Last: Note \(lastNote) (\(viewModel.noteNameFor(lastNote))) on Ch \(lastChannel + 1)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // Learn buttons for each degree
            VStack(spacing: 8) {
                Text("Tap to learn button for each chord degree:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { degree in
                        LearnDegreeButton(
                            degree: degree,
                            learnedNote: viewModel.learnedNotes[degree],
                            isLearning: viewModel.isLearning && viewModel.learningForDegree == degree,
                            viewModel: viewModel,
                            midiService: midiService
                        )
                    }
                }
            }
            
            // Clear learned notes
            if !viewModel.learnedNotes.isEmpty {
                Button {
                    viewModel.clearLearnedNotes()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Clear Learned Notes")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Learn Degree Button

struct LearnDegreeButton: View {
    let degree: Int
    let learnedNote: Int?
    let isLearning: Bool
    @ObservedObject var viewModel: ChordMapViewModel
    @ObservedObject var midiService: MIDIService
    
    private var buttonColor: Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        return colors[(degree - 1) % colors.count]
    }
    
    var body: some View {
        Button {
            if isLearning {
                viewModel.stopLearning()
                midiService.isLearningMode = false
            } else {
                viewModel.startLearning(forDegree: degree)
                midiService.isLearningMode = true
            }
        } label: {
            VStack(spacing: 2) {
                Text(romanNumeral)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                
                if let note = learnedNote {
                    Text("\(note)")
                        .font(.system(size: 9))
                } else {
                    Text("—")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(learnedNote != nil ? .white : .white.opacity(0.7))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(learnedNote != nil ? buttonColor : buttonColor.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isLearning ? Color.white : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isLearning ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isLearning)
        }
        .buttonStyle(.plain)
    }
    
    private var romanNumeral: String {
        let numerals = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
        return numerals[degree - 1]
    }
}

// MARK: - Preview Key Section

struct PreviewKeySection: View {
    @Binding var rootNote: Int
    @Binding var scaleType: ScaleType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW KEY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack(spacing: 12) {
                Picker("Root", selection: $rootNote) {
                    ForEach(NoteName.allCases) { note in
                        Text(note.displayName).tag(note.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(8)
                
                Picker("Scale", selection: $scaleType) {
                    ForEach(ScaleType.allCases) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - NM2 Grid Section

struct NM2GridSection: View {
    @ObservedObject var viewModel: ChordMapViewModel
    @Binding var selectedButton: Int?
    let rootNote: Int
    let scaleType: ScaleType
    
    @State private var showNoteNumbers = true
    
    let gridStates: [[NM2ButtonState]]
    
    init(viewModel: ChordMapViewModel, selectedButton: Binding<Int?>, rootNote: Int, scaleType: ScaleType) {
        self.viewModel = viewModel
        self._selectedButton = selectedButton
        self.rootNote = rootNote
        self.scaleType = scaleType
        self.gridStates = viewModel.generateGridStates()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NM2 BUTTON GRID")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                // Toggle note numbers
                Button {
                    showNoteNumbers.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showNoteNumbers ? "number.circle.fill" : "number.circle")
                            .font(.caption)
                        Text("Notes")
                            .font(.caption2)
                    }
                    .foregroundColor(showNoteNumbers ? .cyan : .gray)
                }
            }
            
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { col in
                            let note = ChordMapping.NM2Grid.noteAt(row: row, col: col)
                            let degree = viewModel.mapping.buttonMap[note]
                            
                            NM2GridButton(
                                note: note,
                                degree: degree,
                                isSelected: selectedButton == note,
                                rootNote: rootNote,
                                scaleType: scaleType,
                                showNoteNumber: showNoteNumbers
                            ) {
                                if selectedButton == note {
                                    selectedButton = nil
                                } else {
                                    selectedButton = note
                                }
                            }
                        }
                    }
                }
            }
            
            HStack {
                Text("Tap a button to assign a chord degree")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if showNoteNumbers {
                    Text("Expected: 36-53")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - NM2 Grid Button

struct NM2GridButton: View {
    let note: Int
    let degree: Int?
    let isSelected: Bool
    let rootNote: Int
    let scaleType: ScaleType
    let action: () -> Void
    var showNoteNumber: Bool = true
    
    private var buttonColor: Color {
        guard let degree = degree else { return .gray.opacity(0.3) }
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        return colors[(degree - 1) % colors.count]
    }
    
    private var noteNameDisplay: String {
        let noteNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let octave = (note / 12) - 1
        let noteName = noteNames[note % 12]
        return "\(noteName)\(octave)"
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let degree = degree {
                    Text(ChordEngine.romanNumeral(degree: degree, scaleType: scaleType))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text(ChordEngine.chordName(degree: degree, rootNote: rootNote, scaleType: scaleType))
                        .font(.system(size: 8))
                    if showNoteNumber {
                        Text("\(note)")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .medium))
                    if showNoteNumber {
                        Text("\(note)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundColor(degree != nil ? .white : .gray)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Degree Selector

struct DegreeSelector: View {
    @ObservedObject var viewModel: ChordMapViewModel
    @Binding var selectedButton: Int?
    let rootNote: Int
    let scaleType: ScaleType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ASSIGN CHORD")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                Button("Clear") {
                    if let button = selectedButton {
                        viewModel.mapping.setMapping(note: button, degree: nil)
                    }
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { degree in
                    DegreeButton(
                        degree: degree,
                        rootNote: rootNote,
                        scaleType: scaleType,
                        isCurrentlyAssigned: selectedButton.flatMap { viewModel.mapping.buttonMap[$0] } == degree
                    ) {
                        if let button = selectedButton {
                            viewModel.mapping.setMapping(note: button, degree: degree)
                            selectedButton = nil
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Degree Button

struct DegreeButton: View {
    let degree: Int
    let rootNote: Int
    let scaleType: ScaleType
    let isCurrentlyAssigned: Bool
    let action: () -> Void
    
    private var buttonColor: Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        return colors[(degree - 1) % colors.count]
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(ChordEngine.romanNumeral(degree: degree, scaleType: scaleType))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(ChordEngine.chordName(degree: degree, rootNote: rootNote, scaleType: scaleType))
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(buttonColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isCurrentlyAssigned ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Section

struct SettingsSection: View {
    @ObservedObject var viewModel: ChordMapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack {
                Text("NM2 MIDI Channel")
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.mapping.nm2Channel },
                    set: { viewModel.mapping.nm2Channel = $0 }
                )) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("Ch \(channel)").tag(channel)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Base Octave")
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.mapping.baseOctave },
                    set: { viewModel.mapping.baseOctave = $0 }
                )) {
                    ForEach(1...6, id: \.self) { octave in
                        Text("\(octave)").tag(octave)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Quick Presets Section

struct QuickPresetsSection: View {
    @ObservedObject var viewModel: ChordMapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK PRESETS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack(spacing: 12) {
                QuickPresetButton(title: "Default", icon: "arrow.counterclockwise") {
                    viewModel.resetToDefault()
                }
                
                QuickPresetButton(title: "Simple", icon: "1.circle") {
                    viewModel.setupSimpleLayout()
                }
                
                QuickPresetButton(title: "Pop", icon: "music.note.list") {
                    viewModel.setupPopLayout()
                }
                
                QuickPresetButton(title: "Clear", icon: "trash") {
                    viewModel.clearAllMappings()
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Quick Preset Button

struct QuickPresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(.cyan)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cyan.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ChordMapView()
        .environmentObject(SharedSongStore.shared)
}
