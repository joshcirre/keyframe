import SwiftUI
import AppKit
import CoreAudioKit

/// Manages floating windows for plugin UIs
class PluginWindowManager: ObservableObject {
    static let shared = PluginWindowManager()

    /// Active plugin windows keyed by a unique identifier
    private var windows: [String: NSWindow] = [:]

    /// Keep strong references to window delegates to prevent deallocation
    private var windowDelegates: [String: WindowDelegate] = [:]

    private init() {}

    /// Open a plugin editor window for an instrument
    func openInstrumentEditor(for channel: MacChannelStrip, channelName: String) {
        let windowId = "instrument-\(channel.id)"

        // If window already exists (even if hidden), bring to front
        if let existing = windows[windowId] {
            if !existing.isVisible {
                existing.orderFront(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            print("PluginWindowManager: Showing existing window for instrument")
            return
        }

        channel.getInstrumentViewController { [weak self] viewController in
            guard let self = self, let vc = viewController else {
                print("PluginWindowManager: No view controller for instrument")
                return
            }

            self.createWindow(
                id: windowId,
                title: "\(channelName) - \(channel.instrumentInfo?.name ?? "Instrument")",
                viewController: vc
            )
        }
    }

    /// Open a plugin editor window for an effect
    func openEffectEditor(for channel: MacChannelStrip, effectIndex: Int, channelName: String) {
        let windowId = "effect-\(channel.id)-\(effectIndex)"

        // If window already exists (even if hidden), bring to front
        if let existing = windows[windowId] {
            if !existing.isVisible {
                existing.orderFront(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            print("PluginWindowManager: Showing existing window for effect")
            return
        }

        channel.getEffectViewController(at: effectIndex) { [weak self] viewController in
            guard let self = self, let vc = viewController else {
                print("PluginWindowManager: No view controller for effect \(effectIndex)")
                return
            }

            let effectName = effectIndex < channel.effectInfos.count
                ? channel.effectInfos[effectIndex].name
                : "Effect \(effectIndex + 1)"

            self.createWindow(
                id: windowId,
                title: "\(channelName) - \(effectName)",
                viewController: vc
            )
        }
    }

    /// Create and show a new plugin window
    private func createWindow(id: String, title: String, viewController: NSViewController) {
        // Get preferred size from the view controller or use default
        let preferredSize = viewController.preferredContentSize
        let size = preferredSize.width > 0 && preferredSize.height > 0
            ? preferredSize
            : CGSize(width: 600, height: 400)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.contentViewController = viewController
        window.isReleasedWhenClosed = false
        window.center()

        // Track window closing - store delegate strongly to prevent deallocation
        // Use the hiding delegate to keep the window around
        let delegate = WindowDelegate(windowId: id, manager: self)
        windowDelegates[id] = delegate
        window.delegate = delegate

        windows[id] = window
        window.makeKeyAndOrderFront(nil)

        print("PluginWindowManager: Opened window '\(title)'")
    }

    /// Close a plugin window
    func closeWindow(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
        windowDelegates.removeValue(forKey: id)
    }

    /// Close all windows for a channel (when channel is removed)
    func closeAllWindows(for channelId: UUID) {
        let prefix = "instrument-\(channelId)"
        let effectPrefix = "effect-\(channelId)"

        for (id, window) in windows {
            if id.hasPrefix(prefix) || id.hasPrefix(effectPrefix) {
                window.close()
                windows.removeValue(forKey: id)
                windowDelegates.removeValue(forKey: id)
            }
        }
    }

    /// Called when a window is about to close by the user - hide instead of destroying
    fileprivate func windowShouldClose(id: String) -> Bool {
        // Hide the window instead of closing it, so we can reopen it later
        if let window = windows[id] {
            window.orderOut(nil)  // Hide instead of close
            print("PluginWindowManager: Hiding window '\(id)' (will reopen on next click)")
            return false  // Prevent actual close
        }
        return true
    }

    /// Actually remove a window (only called when channel is removed)
    fileprivate func windowWillClose(id: String) {
        windows.removeValue(forKey: id)
        windowDelegates.removeValue(forKey: id)
    }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
    let windowId: String
    weak var manager: PluginWindowManager?

    init(windowId: String, manager: PluginWindowManager) {
        self.windowId = windowId
        self.manager = manager
    }

    /// Intercept close to hide instead - this allows reopening the window
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return manager?.windowShouldClose(id: windowId) ?? true
    }

    func windowWillClose(_ notification: Notification) {
        manager?.windowWillClose(id: windowId)
    }
}

// MARK: - SwiftUI Integration

/// A view that shows a button to open a plugin editor
struct PluginEditorButton: View {
    let channel: MacChannelStrip
    let channelName: String
    let isInstrument: Bool
    let effectIndex: Int?

    private let windowManager = PluginWindowManager.shared

    var body: some View {
        Button(action: openEditor) {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
        }
        .help("Open Plugin Editor")
        .disabled(isInstrument ? !channel.isInstrumentLoaded : (effectIndex ?? 0) >= channel.effects.count)
    }

    private func openEditor() {
        if isInstrument {
            windowManager.openInstrumentEditor(for: channel, channelName: channelName)
        } else if let index = effectIndex {
            windowManager.openEffectEditor(for: channel, effectIndex: index, channelName: channelName)
        }
    }
}
