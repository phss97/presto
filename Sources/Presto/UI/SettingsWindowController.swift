import AppKit
import SwiftUI

/// Owns the settings window. Presto runs as a background agent with no Dock icon;
/// while this window is open it becomes a regular app so it shows in the Dock and Cmd-Tab.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        PermissionsManager.shared.refresh()
        LoginItemManager.shared.refresh()

        NSApp.setActivationPolicy(.regular)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Presto"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
