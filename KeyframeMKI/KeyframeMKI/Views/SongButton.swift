import SwiftUI

struct SongButton: View {
    let song: Song
    let isActive: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    
    // Color for the song based on its root note
    private var songColor: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .cyan,
            .blue, .indigo, .purple, .pink, .red, .orange
        ]
        return colors[song.rootNote % colors.count]
    }
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 6) {
                // Song name
                Text(song.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(isActive ? .black : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Key info
                Text(song.keyShortName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isActive ? .black.opacity(0.7) : songColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isActive ? Color.white.opacity(0.3) : songColor.opacity(0.2))
                    )
                
                // Controls count, BPM & filter mode
                HStack(spacing: 6) {
                    // Filter mode
                    HStack(spacing: 2) {
                        Image(systemName: song.filterMode == .block ? "nosign" : "arrow.trianglehead.turn.up.right.circle.fill")
                            .font(.system(size: 9))
                        Text(song.filterMode.rawValue)
                            .font(.system(size: 9))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isActive ? .black.opacity(0.6) : .gray)
                    
                    // BPM (if set)
                    if let bpm = song.bpm {
                        Text("•")
                            .foregroundColor(isActive ? .black.opacity(0.4) : .gray.opacity(0.5))
                        
                        Text("\(bpm)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isActive ? .black.opacity(0.7) : .purple)
                    }
                    
                    // Controls count
                    if !song.preset.controls.isEmpty {
                        Text("•")
                            .foregroundColor(isActive ? .black.opacity(0.4) : .gray.opacity(0.5))
                        
                        Text("\(song.preset.controls.count) CC")
                            .font(.system(size: 9))
                            .fontWeight(.medium)
                            .foregroundColor(isActive ? .black.opacity(0.6) : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            isActive
                                ? LinearGradient(
                                    colors: [songColor, songColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                    
                    // Glow effect for active state
                    if isActive {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(songColor.opacity(0.3))
                            .blur(radius: 20)
                    }
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isActive ? Color.white.opacity(0.5) : songColor.opacity(0.3),
                            lineWidth: isActive ? 2 : 1
                        )
                }
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    onLongPress()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Chord Display Badge

struct ChordDisplayBadge: View {
    let song: Song
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(song.romanNumerals.prefix(4).enumerated()), id: \.offset) { index, numeral in
                Text(numeral)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                SongButton(
                    song: Song.sampleSongs[0],
                    isActive: true,
                    onTap: {},
                    onLongPress: {}
                )
                
                SongButton(
                    song: Song.sampleSongs[1],
                    isActive: false,
                    onTap: {},
                    onLongPress: {}
                )
            }
            
            HStack(spacing: 16) {
                SongButton(
                    song: Song.sampleSongs[2],
                    isActive: false,
                    onTap: {},
                    onLongPress: {}
                )
                
                SongButton(
                    song: Song.sampleSongs[3],
                    isActive: false,
                    onTap: {},
                    onLongPress: {}
                )
            }
        }
        .padding()
    }
}
