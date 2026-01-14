import SwiftUI

/// Editor for keyboard zones/splits on a channel
struct ZoneEditorView: View {
    @Binding var zones: [KeyboardZone]
    let channelName: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedZoneId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Zones - \(channelName)")
                    .font(.headline)

                Spacer()

                Button(action: addZone) {
                    Image(systemName: "plus")
                    Text("Add Zone")
                }
            }
            .padding()

            Divider()

            // Keyboard visualization
            KeyboardVisualization(zones: zones)
                .frame(height: 80)
                .padding()

            Divider()

            // Zone list and editor
            if zones.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    // Zone list
                    zoneListView
                        .frame(minWidth: 150, maxWidth: 200)

                    // Zone editor
                    if let selectedId = selectedZoneId,
                       let index = zones.firstIndex(where: { $0.id == selectedId }) {
                        ZoneDetailEditor(zone: $zones[index])
                    } else {
                        Text("Select a zone to edit")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("Zones filter which notes reach this channel. Overlapping zones send notes to the same channel multiple times.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Zone List

    private var zoneListView: some View {
        List(selection: $selectedZoneId) {
            ForEach(zones) { zone in
                HStack {
                    Circle()
                        .fill(zone.isEnabled ? Color.accentColor : Color.secondary)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading) {
                        Text(zone.name)
                            .font(.body)
                        Text("\(KeyboardZone.noteName(for: zone.lowNote)) - \(KeyboardZone.noteName(for: zone.highNote))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(zone.id)
                .contextMenu {
                    Button("Delete") {
                        deleteZone(zone)
                    }
                }
            }
            .onDelete(perform: deleteZones)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Keyboard Zones")
                .font(.headline)
            Text("Without zones, all notes are passed through.\nAdd zones to create splits or filter note ranges.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Zone") {
                addZone()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func addZone() {
        // Create a sensible default based on existing zones
        let newZone: KeyboardZone
        if zones.isEmpty {
            // First zone: full range
            newZone = KeyboardZone(name: "Zone 1")
        } else if zones.count == 1 {
            // Second zone: split at middle C
            let existingZone = zones[0]
            // Adjust existing zone to lower half
            zones[0].highNote = 59  // B below middle C
            zones[0].name = "Lower"
            newZone = KeyboardZone(name: "Upper", lowNote: 60, highNote: 127)
        } else {
            // Additional zones: small range
            newZone = KeyboardZone(name: "Zone \(zones.count + 1)", lowNote: 60, highNote: 72)
        }

        zones.append(newZone)
        selectedZoneId = newZone.id
    }

    private func deleteZone(_ zone: KeyboardZone) {
        zones.removeAll { $0.id == zone.id }
        if selectedZoneId == zone.id {
            selectedZoneId = zones.first?.id
        }
    }

    private func deleteZones(at offsets: IndexSet) {
        zones.remove(atOffsets: offsets)
    }
}

// MARK: - Zone Detail Editor

struct ZoneDetailEditor: View {
    @Binding var zone: KeyboardZone

    var body: some View {
        Form {
            Section("Zone Settings") {
                TextField("Name", text: $zone.name)

                Toggle("Enabled", isOn: $zone.isEnabled)
            }

            Section("Note Range") {
                // Low note picker
                HStack {
                    Text("Low Note")
                    Spacer()
                    Picker("", selection: $zone.lowNote) {
                        ForEach(0..<128, id: \.self) { note in
                            Text(KeyboardZone.noteName(for: note))
                                .tag(note)
                        }
                    }
                    .frame(width: 100)
                }

                // High note picker
                HStack {
                    Text("High Note")
                    Spacer()
                    Picker("", selection: $zone.highNote) {
                        ForEach(0..<128, id: \.self) { note in
                            Text(KeyboardZone.noteName(for: note))
                                .tag(note)
                        }
                    }
                    .frame(width: 100)
                }

                // Range display
                Text("Range: \(zone.highNote - zone.lowNote + 1) notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Transpose") {
                Stepper("Transpose: \(zone.transpose > 0 ? "+" : "")\(zone.transpose) semitones",
                       value: $zone.transpose,
                       in: -48...48)

                // Quick transpose buttons
                HStack {
                    Button("-12") { zone.transpose -= 12 }
                        .disabled(zone.transpose <= -36)
                    Button("-1") { zone.transpose -= 1 }
                        .disabled(zone.transpose <= -48)
                    Button("0") { zone.transpose = 0 }
                    Button("+1") { zone.transpose += 1 }
                        .disabled(zone.transpose >= 48)
                    Button("+12") { zone.transpose += 12 }
                        .disabled(zone.transpose >= 36)
                }
                .buttonStyle(.bordered)
            }

            Section("Velocity") {
                Picker("Velocity Curve", selection: $zone.velocityCurve) {
                    ForEach(VelocityCurve.allCases, id: \.self) { curve in
                        Text(curve.rawValue).tag(curve)
                    }
                }

                if zone.velocityCurve == .fixed {
                    Stepper("Fixed Velocity: \(zone.velocityFixed)",
                           value: $zone.velocityFixed,
                           in: 1...127)
                }

                // Curve visualization
                VelocityCurveView(curve: zone.velocityCurve)
                    .frame(height: 60)
            }
        }
        .padding()
    }
}

// MARK: - Keyboard Visualization

struct KeyboardVisualization: View {
    let zones: [KeyboardZone]

    // Display range (typically 2-3 octaves centered around middle C)
    private let displayLowNote = 36  // C2
    private let displayHighNote = 96 // C7

    private let whiteKeyWidth: CGFloat = 16
    private let blackKeyWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // White keys
                HStack(spacing: 1) {
                    ForEach(displayLowNote...displayHighNote, id: \.self) { note in
                        if isWhiteKey(note) {
                            Rectangle()
                                .fill(zoneColor(for: note))
                                .frame(width: whiteKeyWidth)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                    }
                }

                // Black keys overlay
                HStack(spacing: 1) {
                    ForEach(displayLowNote...displayHighNote, id: \.self) { note in
                        if isWhiteKey(note) {
                            ZStack {
                                Color.clear
                                    .frame(width: whiteKeyWidth)

                                if hasBlackKeyAfter(note) {
                                    Rectangle()
                                        .fill(zoneColor(for: note + 1))
                                        .frame(width: blackKeyWidth, height: 40)
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                                        )
                                        .offset(x: whiteKeyWidth / 2 + 1)
                                }
                            }
                        }
                    }
                }

                // Middle C marker
                let middleCPosition = whiteKeyPositionX(for: 60)
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: middleCPosition, y: 55)
            }
        }
    }

    private func isWhiteKey(_ note: Int) -> Bool {
        let n = note % 12
        return [0, 2, 4, 5, 7, 9, 11].contains(n)
    }

    private func hasBlackKeyAfter(_ note: Int) -> Bool {
        let n = note % 12
        return [0, 2, 5, 7, 9].contains(n)
    }

    private func zoneColor(for note: Int) -> Color {
        let activeZones = zones.filter { $0.isEnabled && $0.contains(note: note) }

        if activeZones.isEmpty {
            return isWhiteKey(note) ? Color.white : Color.black
        }

        // Use hue based on zone index for multiple zones
        let zoneIndex = zones.firstIndex { $0.id == activeZones.first?.id } ?? 0
        let hue = Double(zoneIndex) / max(Double(zones.count), 1.0)

        return Color(hue: hue, saturation: 0.7, brightness: isWhiteKey(note) ? 0.9 : 0.5)
    }

    private func whiteKeyPositionX(for note: Int) -> CGFloat {
        var x: CGFloat = 0
        for n in displayLowNote..<note {
            if isWhiteKey(n) {
                x += whiteKeyWidth + 1
            }
        }
        return x + whiteKeyWidth / 2
    }
}

// MARK: - Velocity Curve View

struct VelocityCurveView: View {
    let curve: VelocityCurve

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height

                path.move(to: CGPoint(x: 0, y: height))

                for x in stride(from: 0, through: width, by: 2) {
                    let inputVelocity = x / width
                    let outputVelocity: CGFloat

                    switch curve {
                    case .linear:
                        outputVelocity = inputVelocity
                    case .soft:
                        outputVelocity = sqrt(inputVelocity)
                    case .hard:
                        outputVelocity = inputVelocity * inputVelocity
                    case .fixed:
                        outputVelocity = 0.75  // Show as flat line
                    }

                    path.addLine(to: CGPoint(x: x, y: height - (outputVelocity * height)))
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)

            // Axes
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
            }
            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
        }
    }
}

// MARK: - Preview Support

#Preview {
    ZoneEditorView(
        zones: .constant([
            KeyboardZone(name: "Lower", lowNote: 0, highNote: 59),
            KeyboardZone(name: "Upper", lowNote: 60, highNote: 127)
        ]),
        channelName: "Piano",
        onSave: {}
    )
}
