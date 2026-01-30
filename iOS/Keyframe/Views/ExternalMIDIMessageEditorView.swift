import SwiftUI

/// Editor for creating/editing external MIDI messages
struct ExternalMIDIMessageEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State var message: ExternalMIDIMessage
    let isNew: Bool
    let onSave: (ExternalMIDIMessage) -> Void

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
                        helixPresetsSection
                        typeSection
                        dataSection
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(TEColors.darkGray)
            }

            Spacer()

            Text(isNew ? "NEW MESSAGE" : "EDIT MESSAGE")
                .font(TEFonts.display(16, weight: .black))
                .foregroundStyle(TEColors.black)
                .tracking(2)

            Spacer()

            Button {
                onSave(message)
                dismiss()
            } label: {
                Text("SAVE")
                    .font(TEFonts.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(TEColors.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TEColors.warmWhite)
    }

    // MARK: - Helix Presets Section

    private var helixPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HELIX QUICK PRESETS")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 8) {
                // Presets row (Helix snapshots via CC 69)
                HStack {
                    Text("PRESETS")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .frame(width: 80, alignment: .leading)

                    HStack(spacing: 4) {
                        ForEach(1...8, id: \.self) { preset in
                            Button {
                                applyHelixPreset(type: .controlChange, data1: 69, data2: preset - 1)
                            } label: {
                                Text("\(preset)")
                                    .font(TEFonts.mono(11, weight: .bold))
                                    .foregroundStyle(isPresetSelected(preset) ? .white : TEColors.black)
                                    .frame(width: 32, height: 32)
                                    .background(isPresetSelected(preset) ? TEColors.orange : TEColors.cream)
                                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 1))
                            }
                        }
                    }
                }

                // Footswitch toggles row
                HStack {
                    Text("STOMPS")
                        .font(TEFonts.mono(9, weight: .medium))
                        .foregroundStyle(TEColors.midGray)
                        .frame(width: 80, alignment: .leading)

                    HStack(spacing: 4) {
                        ForEach(1...8, id: \.self) { fs in
                            Button {
                                applyHelixPreset(type: .controlChange, data1: 48 + fs, data2: 127)
                            } label: {
                                Text("FS\(fs)")
                                    .font(TEFonts.mono(9, weight: .bold))
                                    .foregroundStyle(isStompSelected(fs) ? .white : TEColors.black)
                                    .frame(width: 32, height: 32)
                                    .background(isStompSelected(fs) ? TEColors.orange : TEColors.cream)
                                    .overlay(Rectangle().strokeBorder(TEColors.black, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
                    .background(TEColors.warmWhite)
            )
        }
    }

    private func applyHelixPreset(type: MIDIMessageType, data1: Int, data2: Int) {
        message.type = type
        message.data1 = data1
        message.data2 = data2
    }

    private func isPresetSelected(_ preset: Int) -> Bool {
        message.type == .controlChange && message.data1 == 69 && message.data2 == preset - 1
    }

    private func isStompSelected(_ fs: Int) -> Bool {
        message.type == .controlChange && message.data1 == 48 + fs && message.data2 == 127
    }

    // MARK: - Type Section

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESSAGE TYPE")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)

            HStack(spacing: 0) {
                ForEach(MIDIMessageType.allCases) { type in
                    Button {
                        message.type = type
                    } label: {
                        Text(type.rawValue.uppercased())
                            .font(TEFonts.mono(10, weight: .bold))
                            .foregroundStyle(message.type == type ? .white : TEColors.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Rectangle()
                                    .fill(message.type == type ? TEColors.orange : TEColors.cream)
                            )
                    }
                }
            }
            .overlay(
                Rectangle()
                    .strokeBorder(TEColors.black, lineWidth: 2)
            )
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATA")
                .font(TEFonts.mono(10, weight: .bold))
                .foregroundStyle(TEColors.midGray)
                .tracking(2)

            VStack(spacing: 16) {
                // Data 1 (Note/CC/PC number)
                VStack(spacing: 8) {
                    HStack {
                        Text(message.type.data1Label)
                            .font(TEFonts.mono(10, weight: .medium))
                            .foregroundStyle(TEColors.midGray)
                        Spacer()
                        Text("\(message.data1)")
                            .font(TEFonts.mono(16, weight: .bold))
                            .foregroundStyle(TEColors.black)
                    }

                    TESlider(value: Binding(
                        get: { Float(message.data1) / 127.0 },
                        set: { message.data1 = Int($0 * 127) }
                    ))
                }

                // Data 2 (Velocity/Value) - only for certain message types
                if message.type.requiresData2 {
                    VStack(spacing: 8) {
                        HStack {
                            Text(message.type.data2Label)
                                .font(TEFonts.mono(10, weight: .medium))
                                .foregroundStyle(TEColors.midGray)
                            Spacer()
                            Text("\(message.data2)")
                                .font(TEFonts.mono(16, weight: .bold))
                                .foregroundStyle(TEColors.black)
                        }

                        TESlider(value: Binding(
                            get: { Float(message.data2) / 127.0 },
                            set: { message.data2 = Int($0 * 127) }
                        ))
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
}

// MARK: - Preview

#Preview {
    ExternalMIDIMessageEditorView(
        message: ExternalMIDIMessage(),
        isNew: true,
        onSave: { _ in }
    )
}
