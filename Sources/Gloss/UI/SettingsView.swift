import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Bindable private var preferences = AppPreferences.shared
    private let permissions = PermissionsManager.shared
    private let modelManager = ModelManager.shared
    private let coordinator = TranslationCoordinator.shared

    public init() {}

    public var body: some View {
        Form {
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

            Section("On-Device LLM Engine") {
                Picker("Translation Engine", selection: $preferences.enginePreference) {
                    ForEach(EnginePreference.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                LabeledContent("Apple Intelligence") {
                    let status = coordinator.appleBackend.availabilityStatus()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.isAvailable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(status.statusDescription)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                }

                LabeledContent("Local GGUF Model") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(modelManager.modelStatusSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if modelManager.isDownloading {
                            HStack(spacing: 8) {
                                ProgressView(value: modelManager.downloadProgress)
                                    .frame(width: 140)
                                Text("\(Int((modelManager.downloadProgress * 100).rounded()))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Button("Cancel") {
                                    modelManager.cancelDownload()
                                }
                                .controlSize(.small)
                            }
                        } else {
                            HStack(spacing: 8) {
                                if modelManager.resolvedModelURL == nil {
                                    Button("Download Qwen 2.5 1.5B (~986 MB)") {
                                        Task {
                                            try? await modelManager.downloadDefaultModel()
                                        }
                                    }
                                    .controlSize(.small)
                                }

                                Button("Choose Custom .gguf…") {
                                    chooseCustomGGUF()
                                }
                                .controlSize(.small)

                                if preferences.customModelPath != nil {
                                    Button("Use Default") {
                                        preferences.customModelPath = nil
                                        Task { await LlamaCppBackend.shared.unload() }
                                        modelManager.refreshState()
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }

                        if let err = modelManager.downloadError {
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                }
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 430)
        .onAppear {
            permissions.refresh()
            modelManager.refreshState()
        }
    }

    private func chooseCustomGGUF() {
        let panel = NSOpenPanel()
        panel.title = "Select Local GGUF Model"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let ggufType = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [ggufType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            preferences.customModelPath = url.path
            Task { await LlamaCppBackend.shared.unload() }
            modelManager.refreshState()
        }
    }
}
