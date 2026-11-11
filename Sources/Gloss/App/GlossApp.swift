import AppKit
import SwiftUI

@MainActor
public final class GlossAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let bundledIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = bundledIcon
        }

        let coordinator = TranslationCoordinator.shared
        let panelController = FloatingPanelController.shared
        let preferences = AppPreferences.shared
        let hotkeys = HotkeyManager.shared

        coordinator.onShowHUD = { point in
            panelController.showHUD(near: point)
        }
        coordinator.onHideHUD = {
            panelController.hideHUD()
        }
        coordinator.onShowLanguagePicker = { selection in
            panelController.showLanguagePicker(for: selection)
        }
        coordinator.onHideLanguagePicker = {
            panelController.hidePicker()
        }
        coordinator.onAccessibilityMissing = {
            SettingsWindowController.shared.show()
        }

        hotkeys.onQuickTranslate = {
            coordinator.triggerQuickTranslate()
        }
        hotkeys.onLanguagePicker = {
            coordinator.triggerLanguagePicker()
        }

        preferences.onShortcutsChanged = { [weak preferences] in
            guard let preferences else { return }
            HotkeyManager.shared.register(
                quickTranslate: preferences.quickTranslateShortcut,
                languagePicker: preferences.pickerTranslateShortcut
            )
        }

        hotkeys.register(
            quickTranslate: preferences.quickTranslateShortcut,
            languagePicker: preferences.pickerTranslateShortcut
        )

        PermissionsManager.shared.refresh()
        enableLaunchAtLoginOnFirstRun()

        // Opened by the user (Finder, Spotlight, Dock): show settings.
        // Started at login: stay in the background unless setup is incomplete.
        let launchedAtLogin = LoginItemManager.wasLaunchedAsLoginItem()
        if !launchedAtLogin || !PermissionsManager.shared.isAccessibilityGranted {
            SettingsWindowController.shared.show()
        }
    }

    /// Opening Gloss again while it is already running in the background.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func enableLaunchAtLoginOnFirstRun() {
        let preferences = AppPreferences.shared
        // Only register the installed copy, never a build run from dist/ or .build/.
        guard !preferences.didOfferLaunchAtLogin,
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        preferences.didOfferLaunchAtLogin = true
        LoginItemManager.shared.setEnabled(true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }
}

@main
public struct GlossApp: App {
    @NSApplicationDelegateAdaptor(GlossAppDelegate.self) private var appDelegate
    @Bindable private var preferences = AppPreferences.shared

    public init() {}

    public var body: some Scene {
        MenuBarExtra(isInserted: $preferences.showMenuBarIcon) {
            MenuBarContentView()
        } label: {
            Image(nsImage: GlossBrandIcon.menuBarTemplateImage())
                .accessibilityLabel("Gloss")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
