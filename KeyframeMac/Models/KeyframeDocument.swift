import SwiftUI
import UniformTypeIdentifiers

// MARK: - Keyframe Document Type

extension UTType {
    static var keyframeSession: UTType {
        UTType(exportedAs: "com.keyframe.session")
    }
}

// MARK: - Keyframe Document

/// A document wrapper for MacSession that integrates with macOS document-based app features
struct KeyframeDocument: FileDocument {

    // MARK: - Content Types

    static var readableContentTypes: [UTType] { [.keyframeSession, .json] }
    static var writableContentTypes: [UTType] { [.keyframeSession] }

    // MARK: - Properties

    var session: MacSession

    // MARK: - Initialization

    init(session: MacSession = MacSession()) {
        self.session = session
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            session = try decoder.decode(MacSession.self, from: data)
        } catch {
            print("KeyframeDocument: Failed to decode session: \(error)")
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    // MARK: - File Writing

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(session)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - File Operations for MacSessionStore

extension MacSessionStore {

    // MARK: - Save to File

    /// Save the current session to a file
    /// - Parameter url: The URL to save to
    /// - Returns: True if save was successful
    @discardableResult
    func saveToFile(_ url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(currentSession)
            try data.write(to: url, options: .atomic)
            currentFileURL = url
            isDocumentDirty = false
            addToRecentDocuments(url)
            print("MacSessionStore: Saved session to \(url.path)")
            return true
        } catch {
            print("MacSessionStore: Failed to save session: \(error)")
            return false
        }
    }

    // MARK: - Load from File

    /// Load a session from a file
    /// - Parameter url: The URL to load from
    /// - Returns: True if load was successful
    @discardableResult
    func loadFromFile(_ url: URL) -> Bool {
        let decoder = JSONDecoder()

        do {
            let data = try Data(contentsOf: url)
            let session = try decoder.decode(MacSession.self, from: data)
            currentSession = session
            currentFileURL = url
            isDocumentDirty = false
            addToRecentDocuments(url)
            print("MacSessionStore: Loaded session from \(url.path)")
            return true
        } catch {
            print("MacSessionStore: Failed to load session: \(error)")
            return false
        }
    }

    // MARK: - New Session

    /// Create a new empty session
    func newSession() {
        currentSession = MacSession()
        currentFileURL = nil
        isDocumentDirty = false
    }

    // MARK: - Recent Documents

    private static let recentDocumentsKey = "mac.recentDocuments"
    private static let maxRecentDocuments = 10

    /// Get list of recent document URLs
    var recentDocuments: [URL] {
        let defaults = UserDefaults.standard
        guard let bookmarks = defaults.array(forKey: Self.recentDocumentsKey) as? [Data] else {
            return []
        }

        var urls: [URL] = []
        for bookmark in bookmarks {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
               !isStale {
                urls.append(url)
            }
        }
        return urls
    }

    /// Add a URL to recent documents
    func addToRecentDocuments(_ url: URL) {
        let defaults = UserDefaults.standard

        // Get existing bookmarks
        var bookmarks = defaults.array(forKey: Self.recentDocumentsKey) as? [Data] ?? []

        // Create bookmark for new URL
        guard let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }

        // Remove existing entry for this URL if present
        let existingUrls = recentDocuments
        if let existingIndex = existingUrls.firstIndex(where: { $0.path == url.path }) {
            bookmarks.remove(at: existingIndex)
        }

        // Add new bookmark at the beginning
        bookmarks.insert(newBookmark, at: 0)

        // Limit to max recent documents
        if bookmarks.count > Self.maxRecentDocuments {
            bookmarks = Array(bookmarks.prefix(Self.maxRecentDocuments))
        }

        defaults.set(bookmarks, forKey: Self.recentDocumentsKey)
    }

    /// Clear recent documents list
    func clearRecentDocuments() {
        UserDefaults.standard.removeObject(forKey: Self.recentDocumentsKey)
    }

    // MARK: - Document State

    /// Mark the document as dirty (has unsaved changes)
    func markDirty() {
        isDocumentDirty = true
    }
}
