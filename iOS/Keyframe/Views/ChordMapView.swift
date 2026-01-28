import SwiftUI

/// Simplified chord mapping view - just learn 7 buttons for 7 scale degrees
/// Now with secondary zone support for split controller mode
struct ChordMapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var audioEngine = AudioEngine.shared

    @State private var mappings: [Int: Int] = [:]  // degree (1-7) -> MIDI note
    @State private var baseOctave: Int = 4
    @State private var learningDegree: Int? = nil

    // Secondary zone state
    @State private var secondaryEnabled: Bool = false
    @State private var secondaryStartNote: Int? = nil  // First note of secondary zone
    @State private var secondaryTargetChannel: Int? = nil
    @State private var secondaryBaseOctave: Int = 4
    @State private var isLearningSecondaryStart: Bool = false

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
        _secondaryStartNote = State(initialValue: mapping.secondaryStartNote)
        _secondaryTargetChannel = State(initialValue: mapping.secondaryTargetChannel)
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
            midiEngine.onNoteLearn = { note, channel, source in
                // Learning for primary chord zone
                if let degree = learningDegree {
                    // Remove this note from any other degree first
                    for (d, n) in mappings where n == note && d != degree {
                        mappings.removeValue(forKey: d)
                    }
                    // Check if note conflicts with secondary zone
                    if let start = secondaryStartNote, note >= start && note < start + 7 {
                        secondaryStartNote = nil  // Clear secondary if there's a conflict
                    }
                    mappings[degree] = note
                    learningDegree = nil
                    midiEngine.isLearningMode = false
                }
                // Learning for secondary zone start note
                else if isLearningSecondaryStart {
                    // Remove any primary mappings that would conflict with secondary zone (7 notes)
                    for offset in 0..<7 {
                        let conflictNote = note + offset
                        for (d, n) in mappings where n == conflictNote {
                            mappings.removeValue(forKey: d)
                        }
                    }
                    secondaryStartNote = note
                    isLearningSecondaryStart = false
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
                    .foregroundColor(TEColors.black)
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
                .foregroundColor(TEColors.black)
                .tracking(2)

            Spacer()

            Button {
                saveAndDismiss()
            } label: {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(.white)
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
                    .foregroundColor(TEColors.orange)

                Text("MAP YOUR CHORDPAD BUTTONS")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundColor(TEColors.black)

                Spacer()

                // MIDI status
                HStack(spacing: 4) {
                    Circle()
                        .fill(!midiEngine.connectedSources.isEmpty ? TEColors.green : TEColors.red)
                        .frame(width: 8, height: 8)
                    Text(!midiEngine.connectedSources.isEmpty ? "MIDI OK" : "NO MIDI")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundColor(TEColors.midGray)
                }
            }

            Text("Tap a chord degree below, then press a button on your controller to assign it.")
                .font(TEFonts.mono(10, weight: .medium))
                .foregroundColor(TEColors.midGray)
                .frame(maxWidth: .infinity, alignment: .leading)

            if learningDegree != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(TEColors.orange)

                    Text("LISTENING FOR MIDI INPUT...")
                        .font(TEFonts.mono(10, weight: .bold))
                        .foregroundColor(TEColors.orange)

                    Spacer()

                    Button {
                        learningDegree = nil
                        midiEngine.isLearningMode = false
                    } label: {
                        Text("CANCEL")
                            .font(TEFonts.mono(9, weight: .bold))
                            .foregroundColor(TEColors.red)
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
                            learningDegree = nil
                            midiEngine.isLearningMode = false
                        } else {
                            // Start learning for this degree
                            learningDegree = degree
                            midiEngine.isLearningMode = true
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
                    .foregroundColor(mappedCount == 7 ? TEColors.green : TEColors.midGray)

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
                        .foregroundColor(TEColors.red)
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
                .foregroundColor(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 16) {
                HStack {
                    Text("BASE OCTAVE")
                        .font(TEFonts.mono(10, weight: .medium))
                        .foregroundColor(TEColors.midGray)

                    Spacer()

                    HStack(spacing: 0) {
                        ForEach(2...5, id: \.self) { octave in
                            Button {
                                baseOctave = octave
                            } label: {
                                Text("\(octave)")
                                    .font(TEFonts.mono(12, weight: .bold))
                                    .foregroundColor(baseOctave == octave ? .white : TEColors.black)
                                    .frame(width: 44, height: 36)
                                    .background(baseOctave == octave ? TEColors.orange : TEColors.cream)
                            }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 2))
                }

                Text("The octave where chord notes will be played (4 = middle C octave)")
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

    // MARK: - Secondary Zone Section

    private var secondaryZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPLIT CONTROLLER")
                    .font(TEFonts.mono(10, weight: .bold))
                    .foregroundColor(TEColors.midGray)
                    .tracking(2)

                Spacer()

                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TEColors.midGray)
            }

            VStack(spacing: 16) {
                // Enable toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SECONDARY ZONE")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.darkGray)

                        Text("Route a second set of buttons to a different track")
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundColor(TEColors.midGray)
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

                    // Target channel picker
                    HStack {
                        Text("TARGET TRACK")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)

                        Spacer()

                        Menu {
                            Button("NONE") {
                                secondaryTargetChannel = nil
                            }
                            ForEach(0..<audioEngine.channelStrips.count, id: \.self) { index in
                                let strip = audioEngine.channelStrips[index]
                                Button("CH \(index + 1): \(strip.name.uppercased())") {
                                    secondaryTargetChannel = index
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(secondaryTargetLabel)
                                    .font(TEFonts.mono(12, weight: .bold))
                                    .foregroundColor(secondaryTargetChannel == nil ? TEColors.midGray : TEColors.black)
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

                    if audioEngine.channelStrips.isEmpty {
                        Text("Add channels first to select a target track")
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundColor(TEColors.orange)
                    }

                    Rectangle()
                        .fill(TEColors.lightGray)
                        .frame(height: 1)

                    // Secondary zone - learn just the first button
                    VStack(spacing: 12) {
                        Text("These buttons will play scale degrees 1-7 as single notes")
                            .font(TEFonts.mono(9, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Learn first button
                        HStack {
                            Text("FIRST BUTTON")
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundColor(TEColors.midGray)

                            Spacer()

                            if let startNote = secondaryStartNote {
                                HStack(spacing: 8) {
                                    Text(noteName(for: startNote))
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .foregroundColor(TEColors.black)

                                    Text("→ \(noteName(for: startNote + 6))")
                                        .font(TEFonts.mono(10, weight: .medium))
                                        .foregroundColor(TEColors.midGray)

                                    Button {
                                        secondaryStartNote = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(TEColors.red)
                                    }
                                }
                            }

                            Button {
                                if isLearningSecondaryStart {
                                    isLearningSecondaryStart = false
                                    midiEngine.isLearningMode = false
                                } else {
                                    learningDegree = nil
                                    isLearningSecondaryStart = true
                                    midiEngine.isLearningMode = true
                                }
                            } label: {
                                Text(isLearningSecondaryStart ? "CANCEL" : (secondaryStartNote == nil ? "LEARN" : "RELEARN"))
                                    .font(TEFonts.mono(10, weight: .bold))
                                    .foregroundColor(isLearningSecondaryStart ? TEColors.red : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isLearningSecondaryStart ? TEColors.warmWhite : TEColors.blue)
                                    .overlay(Rectangle().strokeBorder(isLearningSecondaryStart ? TEColors.red : TEColors.black, lineWidth: 2))
                            }
                        }

                        if isLearningSecondaryStart {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(TEColors.blue)

                                Text("PRESS THE FIRST BUTTON OF YOUR SECOND SET...")
                                    .font(TEFonts.mono(10, weight: .bold))
                                    .foregroundColor(TEColors.blue)

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                Rectangle()
                                    .strokeBorder(TEColors.blue, lineWidth: 2)
                                    .background(TEColors.warmWhite)
                            )
                        }

                        // Visual indicator of the 7 notes
                        if let startNote = secondaryStartNote {
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { offset in
                                    VStack(spacing: 2) {
                                        Text("\(offset + 1)")
                                            .font(TEFonts.mono(10, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(noteName(for: startNote + offset))
                                            .font(TEFonts.mono(8, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(TEColors.darkGray)
                                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 1))
                                }
                            }
                        }
                    }

                    // Secondary octave picker
                    HStack {
                        Text("OUTPUT OCTAVE")
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundColor(TEColors.midGray)

                        Spacer()

                        HStack(spacing: 0) {
                            ForEach(2...5, id: \.self) { octave in
                                Button {
                                    secondaryBaseOctave = octave
                                } label: {
                                    Text("\(octave)")
                                        .font(TEFonts.mono(12, weight: .bold))
                                        .foregroundColor(secondaryBaseOctave == octave ? .white : TEColors.black)
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

    private var secondaryTargetLabel: String {
        guard let index = secondaryTargetChannel,
              index < audioEngine.channelStrips.count else {
            return "NONE"
        }
        let strip = audioEngine.channelStrips[index]
        return "CH \(index + 1): \(strip.name.uppercased())"
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

        midiEngine.chordMapping = ChordMapping(
            chordPadChannel: midiEngine.chordMapping.chordPadChannel,
            buttonMap: buttonMap,
            baseOctave: baseOctave,
            secondaryZoneEnabled: secondaryEnabled,
            secondaryStartNote: secondaryStartNote,
            secondaryTargetChannel: secondaryTargetChannel,
            secondaryBaseOctave: secondaryBaseOctave
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
                            .foregroundColor(isLearning ? .white.opacity(0.7) : .white.opacity(0.8))
                    } else {
                        Text("TAP")
                            .font(TEFonts.mono(8, weight: .medium))
                            .foregroundColor(TEColors.midGray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .foregroundColor(mappedNote != nil || isLearning ? .white : TEColors.darkGray)
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
                        .foregroundColor(TEColors.red)
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
