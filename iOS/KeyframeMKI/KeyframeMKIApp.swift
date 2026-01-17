import SwiftUI

@main
struct KeyframeMKIApp: App {
    // Performance Engine stores
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var midiEngine = MIDIEngine.shared
    @StateObject private var sessionStore = SessionStore.shared
    @StateObject private var pluginManager = AUv3HostManager.shared

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .preferredColorScheme(.dark)
        }
    }
}
