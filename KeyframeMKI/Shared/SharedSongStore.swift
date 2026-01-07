import Foundation

/// Shared data store accessible by both the main app and AUv3 extension via App Groups
final class SharedSongStore: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SharedSongStore()
    
    // MARK: - Published Properties
    
    @Published private(set) var activeSong: Song?
    @Published private(set) var songs: [Song] = []
    @Published private(set) var chordMapping: ChordMapping = .defaultMapping
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    private init() {
        userDefaults = UserDefaults(suiteName: AppConstants.appGroupID)
        loadAll()
        
        // Observe Darwin notifications for changes from extension
        observeDarwinNotifications()
    }
    
    // MARK: - Active Song Management
    
    /// Set the active song and notify observers
    func setActiveSong(_ song: Song?) {
        activeSong = song
        saveActiveSong()
        postSongChangedNotification()
    }
    
    /// Set active song by ID
    func setActiveSong(id: UUID) {
        if let song = songs.first(where: { $0.id == id }) {
            setActiveSong(song)
        }
    }
    
    // MARK: - Song List Management
    
    /// Add a new song
    func addSong(_ song: Song) {
        songs.append(song)
        saveSongs()
    }
    
    /// Update an existing song
    func updateSong(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index] = song
            saveSongs()
            
            // Update active song if it was modified
            if activeSong?.id == song.id {
                activeSong = song
                saveActiveSong()
                postSongChangedNotification()
            }
        }
    }
    
    /// Delete a song
    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        saveSongs()
        
        // Clear active song if it was deleted
        if activeSong?.id == song.id {
            setActiveSong(nil)
        }
    }
    
    /// Delete song at index
    func deleteSong(at offsets: IndexSet) {
        let idsToDelete = offsets.map { songs[$0].id }
        songs.remove(atOffsets: offsets)
        saveSongs()
        
        if let activeId = activeSong?.id, idsToDelete.contains(activeId) {
            setActiveSong(nil)
        }
    }
    
    /// Reorder songs
    func moveSongs(from source: IndexSet, to destination: Int) {
        songs.move(fromOffsets: source, toOffset: destination)
        saveSongs()
    }
    
    // MARK: - Chord Mapping Management
    
    /// Update chord mapping
    func updateChordMapping(_ mapping: ChordMapping) {
        chordMapping = mapping
        saveChordMapping()
        postSongChangedNotification()
    }
    
    // MARK: - Persistence
    
    private func loadAll() {
        loadSongs()
        loadActiveSong()
        loadChordMapping()
    }
    
    private func loadSongs() {
        guard let data = userDefaults?.data(forKey: AppConstants.songListKey),
              let decoded = try? decoder.decode([Song].self, from: data) else {
            // Initialize with sample songs if empty
            songs = Song.sampleSongs
            saveSongs()
            return
        }
        songs = decoded
    }
    
    private func saveSongs() {
        guard let data = try? encoder.encode(songs) else { return }
        userDefaults?.set(data, forKey: AppConstants.songListKey)
    }
    
    private func loadActiveSong() {
        guard let data = userDefaults?.data(forKey: AppConstants.activeSongKey),
              let decoded = try? decoder.decode(Song.self, from: data) else {
            return
        }
        activeSong = decoded
    }
    
    private func saveActiveSong() {
        if let song = activeSong {
            guard let data = try? encoder.encode(song) else { return }
            userDefaults?.set(data, forKey: AppConstants.activeSongKey)
        } else {
            userDefaults?.removeObject(forKey: AppConstants.activeSongKey)
        }
    }
    
    private func loadChordMapping() {
        guard let data = userDefaults?.data(forKey: AppConstants.chordMappingKey),
              let decoded = try? decoder.decode(ChordMapping.self, from: data) else {
            chordMapping = .defaultMapping
            saveChordMapping()
            return
        }
        chordMapping = decoded
    }
    
    private func saveChordMapping() {
        guard let data = try? encoder.encode(chordMapping) else { return }
        userDefaults?.set(data, forKey: AppConstants.chordMappingKey)
    }
    
    // MARK: - Darwin Notifications
    
    private func observeDarwinNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        CFNotificationCenterAddObserver(
            center,
            observer,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let store = Unmanaged<SharedSongStore>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    store.reloadFromDisk()
                }
            },
            AppConstants.songChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
    }
    
    private func postSongChangedNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(AppConstants.songChangedNotification as CFString),
            nil,
            nil,
            true
        )
    }
    
    /// Reload data from disk (called when Darwin notification received)
    func reloadFromDisk() {
        loadActiveSong()
        loadSongs()
        loadChordMapping()
    }
    
    // MARK: - Quick Access for AUv3
    
    /// Get current scale configuration for MIDI processing
    var currentScaleConfig: (root: Int, scale: ScaleType, mode: FilterMode)? {
        guard let song = activeSong else { return nil }
        return (song.rootNote, song.scaleType, song.filterMode)
    }
}
