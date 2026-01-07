import SwiftUI

@main
struct KeyframeMKIApp: App {
    // Legacy stores (for backwards compatibility)
    @StateObject private var songStore = SharedSongStore.shared
    @StateObject private var midiService = MIDIService.shared
    
    // New Performance Engine stores
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared
    
    @State private var usePerformanceMode = true  // Set to true to use new engine
    
    var body: some Scene {
        WindowGroup {
            if usePerformanceMode {
                // New Performance Engine
                PerformanceView()
                    .preferredColorScheme(.dark)
            } else {
                // Legacy MIDI Controller mode
                ContentView()
                    .environmentObject(songStore)
                    .environmentObject(midiService)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
