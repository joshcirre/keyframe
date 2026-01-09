import SwiftUI

/// Simplified chord mapping view - just learn 7 buttons for 7 scale degrees
struct ChordMapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var midiEngine = MIDIEngine.shared

    @State private var mappings: [Int: Int] = [:]  // degree (1-7) -> MIDI note
    @State private var baseOctave: Int = 4
    @State private var learningDegree: Int? = nil

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
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            midiEngine.onNoteLearn = { note, channel, source in
                if let degree = learningDegree {
                    // Remove this note from any other degree first
                    for (d, n) in mappings where n == note && d != degree {
                        mappings.removeValue(forKey: d)
                    }
                    mappings[degree] = note
                    learningDegree = nil
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
            baseOctave: baseOctave
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
