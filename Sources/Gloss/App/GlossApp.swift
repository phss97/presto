import AppKit
import SwiftUI

@MainActor
public final class GlossAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }
}

@main
public struct GlossApp: App {
    @NSApplicationDelegateAdaptor(GlossAppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        MenuBarExtra("Gloss", systemImage: "character.bubble") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
