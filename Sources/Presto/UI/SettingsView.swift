import AppKit
import SwiftUI

public struct SettingsView: View {
    @Bindable private var preferences = AppPreferences.shared
    private let permissions = PermissionsManager.shared
    private let modelManager = ModelManager.shared
    private let loginItems = LoginItemManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    PrestoAppIconView(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Presto")
                                .font(.system(size: 16, weight: .semibold))
                            Text("1.0")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Text("On-device macOS translation · Zero cloud calls")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(permissions.isAccessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(permissions.isAccessibilityGranted ? "Granted" : "Not Granted")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if !permissions.isAccessibilityGranted {
                            Button("Open Accessibility Settings") {
                                permissions.requestAccessibilityPrompt()
                                permissions.openAccessibilitySettings()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if !permissions.isAccessibilityGranted {
                    Text("Presto needs Accessibility access to read and replace the text you highlight. Shortcuts do nothing until it's granted. After installing a new build, you may need to remove Presto from the list and add it again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("General") {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }
                ))

                if loginItems.requiresApproval {
                    HStack {
                        Text("Allow Presto in System Settings → General → Login Items.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") {
                            loginItems.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }

                if let error = loginItems.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                Toggle("Show Icon in Menu Bar", isOn: $preferences.showMenuBarIcon)

                HStack {
                    Text("Closing this window keeps Presto running in the background, so your shortcuts keep working. Open Presto again to return here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Quit Presto") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                }
            }

            Section("Shortcuts & Language") {
                Picker("Default Target Language", selection: $preferences.defaultLanguageCode) {
                    ForEach(Language.catalog) { language in
                        Text(language.displayLabel).tag(language.code)
                    }
                }

                ShortcutRecorderButton(
                    title: "Quick Translate (Default Language)",
                    slot: .quickTranslate,
                    shortcut: $preferences.quickTranslateShortcut
                )

                ShortcutRecorderButton(
                    title: "Translate with Language Picker",
                    slot: .languagePicker,
                    shortcut: $preferences.pickerTranslateShortcut
                )

                HStack {
                    Spacer()
                    Button("Reset Shortcuts to Defaults") {
                        preferences.resetShortcutsToDefaults()
                    }
                    .controlSize(.small)
                }
            }

            ModelSelectionSection()
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .onAppear {
            permissions.refresh()
            loginItems.refresh()
            modelManager.refreshState()
        }
    }
}
