import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Model list used in Presto settings: one row per engine, each with its own download action.
struct ModelSelectionSection: View {
    @Bindable private var preferences = AppPreferences.shared
    private let modelManager = ModelManager.shared
    private let coordinator = TranslationCoordinator.shared

    var body: some View {
        Section("Translation Model") {
            VStack(spacing: 0) {
                ForEach(EnginePreference.allCases) { engine in
                    if engine != .hyMT {
                        Divider().padding(.leading, 26)
                    }
                    row(for: engine)
                }
            }

            Picker("Fallback", selection: fallbackBinding) {
                Text("None").tag(Optional<EnginePreference>.none)
                ForEach(fallbackOptions) { engine in
                    Text(engine.displayName).tag(Optional(engine))
                }
            }

            Text("Presto switches to the fallback only when the selected model isn't ready. Nothing is downloaded until you click Download.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = modelManager.downloadError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(for engine: EnginePreference) -> some View {
        let selected = preferences.enginePreference == engine
        return HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(engine.displayName)
                            .font(.system(size: 13, weight: .medium))
                        if engine == .hyMT {
                            Text("Recommended")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(subtitle(for: engine))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { select(engine) }

            trailing(for: engine)
                .padding(.top, 1)
        }
        .padding(.vertical, 7)
    }

    private func subtitle(for engine: EnginePreference) -> String {
        switch engine {
        case .hyMT, .qwen, .translateGemma:
            guard let model = engine.localModel else { return "" }
            return "\(model.summary) · \(model.sizeLabel)"
        case .appleOnly:
            let status = coordinator.appleBackend.availabilityStatus()
            return status.isAvailable ? "On-device · no download" : status.statusDescription
        case .custom:
            return modelManager.customModelURL?.lastPathComponent ?? "Pick any .gguf file on this Mac"
        }
    }

    @ViewBuilder
    private func trailing(for engine: EnginePreference) -> some View {
        switch engine {
        case .appleOnly:
            statusTag(available: coordinator.appleBackend.availabilityStatus().isAvailable)
        case .custom:
            if modelManager.customModelURL != nil {
                readyTag
            } else {
                Button("Choose…") { chooseCustomModel() }
                    .controlSize(.small)
            }
        case .hyMT, .qwen, .translateGemma:
            if let model = engine.localModel {
                if modelManager.isDownloading, modelManager.downloadingModel == model {
                    HStack(spacing: 6) {
                        ProgressView(value: modelManager.downloadProgress)
                            .frame(width: 64)
                        Button("Cancel") { modelManager.cancelDownload() }
                            .controlSize(.small)
                    }
                } else if modelManager.resolvedURL(for: model) != nil {
                    readyTag
                } else {
                    Button("Download") {
                        Task { try? await modelManager.download(model) }
                    }
                    .controlSize(.small)
                    .disabled(modelManager.isDownloading)
                }
            }
        }
    }

    private func statusTag(available: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(available ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(available ? "Available" : "Unavailable")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var readyTag: some View {
        Text("Ready")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func select(_ engine: EnginePreference) {
        if engine == .custom, modelManager.customModelURL == nil {
            chooseCustomModel()
            return
        }
        preferences.enginePreference = engine
    }

    private var fallbackOptions: [EnginePreference] {
        EnginePreference.allCases.filter { $0 != preferences.enginePreference && $0 != .custom }
    }

    private var fallbackBinding: Binding<EnginePreference?> {
        Binding(
            get: { preferences.fallbackEngine },
            set: { preferences.fallbackEngine = $0 == preferences.enginePreference ? nil : $0 }
        )
    }

    private func chooseCustomModel() {
        let panel = NSOpenPanel()
        panel.title = "Select Custom GGUF Model"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let ggufType = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [ggufType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard modelManager.isGGUFFile(url) else {
            let alert = NSAlert()
            alert.messageText = "Not a GGUF model"
            alert.informativeText = "Choose a file that starts with GGUF. Presto runs llama.cpp models in GGUF format only."
            alert.runModal()
            return
        }

        preferences.customModelPath = url.path
        preferences.enginePreference = .custom
        Task { await LlamaCppBackend.shared.unload() }
        modelManager.refreshState()
    }
}
