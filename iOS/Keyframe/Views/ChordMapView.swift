import SwiftUI

/// Simplified chord mapping view - just learn 7 buttons for 7 scale degrees
/// Now with secondary zone support for split controller mode
struct ChordMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var midiEngine = MIDIEngine.shared
    @State private var audioEngine = AudioEngine.shared

    @State private var mappings: [Int: Int] = [:]  // degree (1-7) -> MIDI note
    @State private var baseOctave: Int = 4
    @State private var learningDegree: Int? = nil

    // Secondary zone state
    @State private var secondaryEnabled: Bool = false
    @State private var secondaryMappings: [Int: Int] = [:]  // degree (1-7) -> MIDI note
    @State private var secondaryBaseOctave: Int = 4
    @State private var learningSecondaryDegree: Int? = nil

    init() {
        // Load existing mappings from MIDIEngine
        let mapping = MIDIEngine.shared.chordMapping
        var initial: [Int: Int] = [:]
        // Reverse the buttonMap (note -> degree) to (degree -> note)
        for (note, degree) in mapping.buttonMap {
            initial[degree] = note
        }
        _mappings = State(initialValue: initial)
        _baseOctave = State(initialValue: mapping.baseOctave)

        // Load secondary zone settings
        _secondaryEnabled = State(initialValue: mapping.secondaryZoneEnabled)
        // Load secondary mappings - reverse the map (note -> degree) to (degree -> note)
        var secondaryInitial: [Int: Int] = [:]
        for (note, degree) in mapping.secondaryButtonMap {
            secondaryInitial[degree] = note
        }
        _secondaryMappings = State(initialValue: secondaryInitial)
        _secondaryBaseOctave = State(initialValue: mapping.secondaryBaseOctave)
    }

    var body: some View {
        ZStack {
            TEColors.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(TEColors.black)
                    .frame(height: 2)

                ScrollView {
                    VStack(spacing: 24) {
                        instructionsSection
                        degreeButtonsSection
                        settingsSection
                        secondaryZoneSection
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            print("ChordMapView: Setting up onNoteLearn callback")
            midiEngine.onNoteLearn = { note, channel, source in
                print("ChordMapView: onNoteLearn called with note=\(note) ch=\(channel) source=\(source ?? "nil")")
                print("ChordMapView: learningDegree=\(String(describing: learningDegree)) learningSecondaryDegree=\(String(describing: learningSecondaryDegree))")
                // Learning for primary chord zone
                if let degree = learningDegree {
                    // Remove this note from any other primary degree first
                    for (d, n) in mappings where n == note && d != degree {
                        mappings.removeValue(forKey: d)
                    }
                    // Remove from secondary mappings if it conflicts
                    for (d, n) in secondaryMappings where n == note {
                        secondaryMappings.removeValue(forKey: d)
                    }
                    mappings[degree] = note
                    learningDegree = nil
                    midiEngine.isLearningMode = false
                }
                // Learning for secondary zone individual notes
                else if let degree = learningSecondaryDegree {
                    // Remove this note from any other secondary degree first
                    for (d, n) in secondaryMappings where n == note && d != degree {
                        secondaryMappings.removeValue(forKey: d)
                    }
                    // Remove from primary mappings if it conflicts
                    for (d, n) in mappings where n == note {
                        mappings.removeValue(forKey: d)
                    }
                    secondaryMappings[degree] = note
                    learningSecondaryDegree = nil
                    midiEngine.isLearningMode = false
                }
            }
        }
        .onDisappear {
            midiEngine.isLearningMode = false
            midiEngine.onNoteLearn = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                midiEngine.isLearningMode = false
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(TEColors.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .strokeBorder(TEColors.black, lineWidth: 2)
                    )
            }

            Spacer()

            Text("CHORD MAP")
                .font(TEFonts.display(16, weight: .black))
                .foregroundStyle(TEColors.black)
                .tracking(2)

            Spacer()

            Button {
                saveAndDismiss()
            } label: {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(TEColors.orange)
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TEColors.orange)

                Text("MAP YOUR CHORDPAD BUTTONS")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(TEColors.black)

                Spacer()

                // MIDI status
                HStack(spacing: 4) {
                    Circle()
                        .fill(!midiEngine.connectedSources.isEmpty ? TEColors.green : TEColors.red)
                        .frame(width: 8, height: 8)
                    Text(!midiEngine.connectedSources.isEmpty ? "MIDI OK" : "NO MIDI")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                }
            }

            Text("Tap a chord degree below, then press a button on your controller to assign it.")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundStyle(TEColors.midGray)
                .frame(maxWidth: .infinity, alignment: .leading)

            if learningDegree != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(TEColors.orange)

                    Text("LISTENING FOR MIDI INPUT...")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundStyle(TEColors.orange)

                    Spacer()

                    Button {
                        learningDegree = nil
                        midiEngine.isLearningMode = false
                    } label: {
                        Text("CANCEL")
                            .font(TEFonts.mono(9, weight: .bold))
                            .foregroundStyle(TEColors.red)
                    }
                }
                .padding(12)
                .background(
                    Rectangle()
                        .strokeBorder(TEColors.orange, lineWidth: 2)
                        .background(TEColors.warmWhite)
                )
            }
        }
    }

    // MARK: - Degree Buttons

    private var degreeButtonsSection: some View {
        VStack(spacing: 12) {
            // Row of 7 degree buttons
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { degree in
                    ChordDegreeLearnButton(
                        degree: degree,
                        mappedNote: mappings[degree],
                        isLearning: learningDegree == degree
                    ) {
                        if learningDegree == degree {
                            // Cancel learning
                            print("ChordMapView: Cancelling learning for degree \(degree)")
                            learningDegree = nil
                            midiEngine.isLearningMode = false
                        } else {
                            // Start learning for this degree
                            print("ChordMapView: Starting learning for degree \(degree)")
                            learningDegree = degree
                            midiEngine.isLearningMode = true
                            print("ChordMapView: midiEngine.isLearningMode is now \(midiEngine.isLearningMode)")
                        }
                    } onClear: {
                        mappings.removeValue(forKey: degree)
                    }
                }
            }

            // Summary
            let mappedCount = mappings.count
            HStack {
                Text("\(mappedCount)/7 MAPPED")
                    .font(TEFonts.mono(10, weight: .medium))
                    .foregroundStyle(mappedCount == 7 ? TEColors.green : TEColors.midGray)

                Spacer()

                if !mappings.isEmpty {
                    Button {
                        mappings.removeAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .bold))
                            Text("CLEAR ALL")
                                .font(TEFonts.mono(9, weight: .bold))
                        }
                        .foregroundStyle(TEColors.red)
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

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OUTPUT")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 16) {
                HStack {
                    Text("BASE OCTAVE")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundStyle(TEColors.midGray)

                    Spacer()

                    HStack(spacing: 0) {
                        ForEach(2...5, id: \.self) { octave in
                            Button {
                                baseOctave = octave
                            } label: {
                                Text("\(octave)")
                                    .font(TEFonts.mono(12, weight: .bold))
                                    .foregroundStyle(baseOctave == octave ? .white : TEColors.black)
                                    .frame(width: 44, height: 36)
                                    .background(baseOctave == octave ? TEColors.orange : TEColors.cream)
                            }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }

                Text("The octave where chord notes will be played (4 = middle C octave)")
                    .font(TEFonts.mono(9, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
            }
            .padding(16)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
        }
    }

    // MARK: - Secondary Zone Section

    private var secondaryZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPLIT CONTROLLER")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundStyle(TEColors.midGray)
                    .tracking(2)

                Spacer()

                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TEColors.midGray)
            }

            VStack(spacing: 16) {
                // Enable toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SECONDARY ZONE")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.darkGray)

                        Text("Route a second set of buttons to a different track")
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }

                    Spacer()

                    Toggle("", isOn: $secondaryEnabled)
                        .labelsHidden()
                        .tint(TEColors.orange)
                }

                if secondaryEnabled {
                    Rectangle()
                        .fill(TEColors.lightGray)
                        .frame(height: 1)

                    Text("Enable 'Single Note Target' on channels to receive these notes")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Row of 7 secondary degree buttons
                    HStack(spacing: 8) {
                        ForEach(1...7, id: \.self) { degree in
                            SecondaryDegreeLearnButton(
                                degree: degree,
                                mappedNote: secondaryMappings[degree],
                                isLearning: learningSecondaryDegree == degree
                            ) {
                                if learningSecondaryDegree == degree {
                                    learningSecondaryDegree = nil
                                    midiEngine.isLearningMode = false
                                } else {
                                    learningDegree = nil
                                    learningSecondaryDegree = degree
                                    midiEngine.isLearningMode = true
                                }
                            } onClear: {
                                secondaryMappings.removeValue(forKey: degree)
                            }
                        }
                    }

                    // Listening indicator
                    if learningSecondaryDegree != nil {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(TEColors.blue)

                            Text("LISTENING FOR MIDI INPUT...")
                                .font(TEFonts.mono(10, weight: .bold))
                                .foregroundStyle(TEColors.blue)

                            Spacer()

                            Button {
                                learningSecondaryDegree = nil
                                midiEngine.isLearningMode = false
                            } label: {
                                Text("CANCEL")
                                    .font(TEFonts.mono(9, weight: .bold))
                                    .foregroundStyle(TEColors.red)
                            }
                        }
                        .padding(12)
                        .background(
                            Rectangle()
                                .strokeBorder(TEColors.blue, lineWidth: 2)
                                .background(TEColors.warmWhite)
                        )
                    }

                    // Summary
                    let secondaryMappedCount = secondaryMappings.count
                    HStack {
                        Text("\(secondaryMappedCount)/7 MAPPED")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(secondaryMappedCount == 7 ? TEColors.green : TEColors.midGray)

                        Spacer()

                        if !secondaryMappings.isEmpty {
                            Button {
                                secondaryMappings.removeAll()
                            } label: {
                                Text("CLEAR ALL")
                                    .font(TEFonts.mono(9, weight: .bold))
                                    .foregroundStyle(TEColors.red)
                            }
                        }
                    }

                    Rectangle()
                        .fill(TEColors.lightGray)
                        .frame(height: 1)

                    // Secondary octave picker
                    HStack {
                        Text("OUTPUT OCTAVE")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)

                        Spacer()

                        HStack(spacing: 0) {
                            ForEach(2...5, id: \.self) { octave in
                                Button {
                                    secondaryBaseOctave = octave
                                } label: {
                                    Text("\(octave)")
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .foregroundStyle(secondaryBaseOctave == octave ? .white : TEColors.black)
                                        .frame(width: 44, height: 36)
                                        .background(secondaryBaseOctave == octave ? TEColors.blue : TEColors.cream)
                                }
                            }
                        }
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

    private func noteName(for note: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(noteNames[note % 12])\(octave)"
    }

    // MARK: - Save

    private func saveAndDismiss() {
        midiEngine.isLearningMode = false

        // Convert degree -> note mapping back to note -> degree for ChordMapping
        var buttonMap: [Int: Int] = [:]
        for (degree, note) in mappings {
            buttonMap[note] = degree
        }

        // Convert secondary degree -> note mapping to note -> degree
        var secondaryButtonMap: [Int: Int] = [:]
        for (degree, note) in secondaryMappings {
            secondaryButtonMap[note] = degree
        }

        midiEngine.chordMapping = ChordMapping(
            chordPadChannel: midiEngine.chordMapping.chordPadChannel,
            buttonMap: buttonMap,
            baseOctave: baseOctave,
            secondaryZoneEnabled: secondaryEnabled,
            secondaryStartNote: nil,
            secondaryTargetChannel: nil,
            secondaryBaseOctave: secondaryBaseOctave,
            secondaryButtonMap: secondaryButtonMap
        )

        dismiss()
    }
}

// MARK: - Chord Degree Learn Button

struct ChordDegreeLearnButton: View {
    let degree: Int
    let mappedNote: Int?
    let isLearning: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    private var romanNumeral: String {
        ["I", "II", "III", "IV", "V", "VI", "VII"][degree - 1]
    }

    private var noteName: String {
        guard let note = mappedNote else { return "—" }
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(noteNames[note % 12])\(octave)"
    }

    var body: some View {
        VStack(spacing: 4) {
            // Main button
            Button(action: onTap) {
                VStack(spacing: 4) {
                    Text(romanNumeral)
                        .font(TEFonts.mono(16, weight: .black))

                    if let note = mappedNote {
                        Text(noteName)
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundStyle(isLearning ? .white.opacity(0.7) : .white.opacity(0.8))
                    } else {
                        Text("TAP")
                            .font(TEFonts.mono(8, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .foregroundStyle(mappedNote != nil || isLearning ? .white : TEColors.darkGray)
                .background(
                    isLearning ? TEColors.orange :
                    (mappedNote != nil ? TEColors.black : TEColors.lightGray)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(isLearning ? TEColors.orange : TEColors.black, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)

            // Clear button (only show if mapped)
            if mappedNote != nil && !isLearning {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(TEColors.red)
                }
                .frame(height: 16)
            } else {
                Spacer().frame(height: 16)
            }
        }
    }
}

// MARK: - Secondary Degree Learn Button

struct SecondaryDegreeLearnButton: View {
    let degree: Int
    let mappedNote: Int?
    let isLearning: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    private var degreeLabel: String {
        "\(degree)"
    }

    private var noteName: String {
        guard let note = mappedNote else { return "—" }
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(noteNames[note % 12])\(octave)"
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                VStack(spacing: 4) {
                    Text(degreeLabel)
                        .font(TEFonts.mono(16, weight: .black))

                    if let _ = mappedNote {
                        Text(noteName)
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundStyle(isLearning ? .white.opacity(0.7) : .white.opacity(0.8))
                    } else {
                        Text("TAP")
                            .font(TEFonts.mono(8, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .foregroundStyle(mappedNote != nil || isLearning ? .white : TEColors.darkGray)
                .background(
                    isLearning ? TEColors.blue :
                    (mappedNote != nil ? TEColors.darkGray : TEColors.lightGray)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(isLearning ? TEColors.blue : TEColors.black, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)

            if mappedNote != nil && !isLearning {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(TEColors.red)
                }
                .frame(height: 16)
            } else {
                Spacer().frame(height: 16)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChordMapView()
}
