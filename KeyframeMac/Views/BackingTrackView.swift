import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// View for managing backing tracks on a preset
struct BackingTrackView: View {
    @Binding var backingTrack: BackingTrack?
    @EnvironmentObject var audioEngine: MacAudioEngine

    @State private var showingFilePicker = false
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup("Backing Track", isExpanded: $isExpanded) {
            if let track = backingTrack {
                trackEditorView(track: Binding(
                    get: { track },
                    set: { backingTrack = $0 }
                ))
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No backing track assigned")
                .foregroundColor(.secondary)

            Button("Add Backing Track...") {
                showingFilePicker = true
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Track Editor

    private func trackEditorView(track: Binding<BackingTrack>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info
            HStack {
                Image(systemName: "music.note")
                Text(track.wrappedValue.name)
                    .font(.headline)

                Spacer()

                // Remove button
                Button(action: { backingTrack = nil }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }

            // Transport controls
            HStack(spacing: 16) {
                Button(action: { audioEngine.playBackingTrack() }) {
                    Image(systemName: audioEngine.isBackingTrackPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)

                Button(action: { audioEngine.stopBackingTrack() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)

                // Position slider
                Slider(
                    value: Binding(
                        get: { audioEngine.backingTrackPosition },
                        set: { audioEngine.seekBackingTrack(to: $0) }
                    ),
                    in: 0...max(audioEngine.backingTrackDuration, 1)
                )

                // Time display
                Text(formatTime(audioEngine.backingTrackPosition))
                    .monospacedDigit()
                    .font(.caption)

                Text("/")
                    .foregroundColor(.secondary)

                Text(formatTime(audioEngine.backingTrackDuration))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Volume
            HStack {
                Text("Volume")
                Slider(value: track.volume, in: 0...1)
                Text("\(Int(track.wrappedValue.volume * 100))%")
                    .frame(width: 40)
                    .monospacedDigit()
            }

            // Auto-start toggle
            Toggle("Auto-start when preset is selected", isOn: track.autoStart)

            // Loop toggle
            Toggle("Loop playback", isOn: track.loopEnabled)

            // Stereo split option
            Toggle("Stereo split (left=click, right=music)", isOn: track.isStereoSplit)

            if track.wrappedValue.isStereoSplit {
                // Click volume
                HStack {
                    Text("Click Volume")
                    Slider(value: track.clickVolume, in: 0...1)
                    Text("\(Int(track.wrappedValue.clickVolume * 100))%")
                        .frame(width: 40)
                        .monospacedDigit()
                }

                // Music volume
                HStack {
                    Text("Music Volume")
                    Slider(value: track.musicVolume, in: 0...1)
                    Text("\(Int(track.wrappedValue.musicVolume * 100))%")
                        .frame(width: 40)
                        .monospacedDigit()
                }
            }

            // Replace track button
            Button("Replace Track...") {
                showingFilePicker = true
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Create security-scoped bookmark
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }

                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                var track = BackingTrack(
                    name: url.lastPathComponent,
                    fileBookmark: bookmark,
                    filePath: url.path
                )
                track.autoStart = true

                backingTrack = track

                // Load into audio engine for preview
                audioEngine.loadBackingTrack(track)

            } catch {
                print("BackingTrackView: Failed to create bookmark: \(error)")
            }

        case .failure(let error):
            print("BackingTrackView: File selection failed: \(error)")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform View (Future Enhancement)

struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !samples.isEmpty else { return }

                let width = geometry.size.width
                let height = geometry.size.height
                let middle = height / 2

                let step = max(1, samples.count / Int(width))

                path.move(to: CGPoint(x: 0, y: middle))

                for (index, i) in stride(from: 0, to: samples.count, by: step).enumerated() {
                    let x = CGFloat(index) * width / CGFloat(samples.count / step)
                    let sample = samples[i]
                    let y = middle - CGFloat(sample) * middle

                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.accentColor, lineWidth: 1)
        }
    }
}

// MARK: - UTType Extensions

extension UTType {
    static var mp3: UTType { UTType(filenameExtension: "mp3")! }
    static var wav: UTType { UTType(filenameExtension: "wav")! }
    static var aiff: UTType { UTType(filenameExtension: "aiff")! }
}
