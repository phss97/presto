import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    @Bindable private var preferences = AppPreferences.shared
    private let permissions = PermissionsManager.shared
    private let coordinator = TranslationCoordinator.shared
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gloss", systemImage: "character.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(preferences.enginePreference.shortTitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            if !permissions.isAccessibilityGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility Permission Needed", systemImage: "hand.raised.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("Gloss needs Accessibility access to read & replace highlighted text.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Grant Access…") {
                        permissions.requestAccessibilityPrompt()
                        permissions.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Default Language")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("Default Language", selection: $preferences.defaultLanguageCode) {
                    ForEach(Language.catalog) { lang in
                        Text(lang.displayLabel).tag(lang.code)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Translate to \(preferences.defaultLanguage.englishName)")
                        .font(.system(size: 12))
                    Spacer()
                    Text(preferences.quickTranslateShortcut.displayString)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Choose Language…")
                        .font(.system(size: 12))
                    Spacer()
                    Text(preferences.pickerTranslateShortcut.displayString)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(engineIndicatorColor)
                    .frame(width: 7, height: 7)
                Text(coordinator.activeEngineSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                Button("Quit Gloss") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(width: 280)
        .onAppear {
            permissions.refresh()
            ModelManager.shared.refreshState()
        }
    }

    private var engineIndicatorColor: Color {
        if coordinator.appleBackend.availabilityStatus().isAvailable && preferences.enginePreference != .llamaCppOnly {
            return .green
        }
        if ModelManager.shared.resolvedModelURL != nil && preferences.enginePreference != .appleOnly {
            return .green
        }
        return .orange
    }
}
