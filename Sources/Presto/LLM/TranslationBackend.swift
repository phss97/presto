import AppKit
import Foundation
import Observation

public enum TranslationPromptBuilder {
    public static func systemInstructions(for targetLanguage: Language) -> String {
        """
        You are a precise, native-quality translation engine.
        Translate the user's text inside <source_text> tags into \(targetLanguage.englishName) (language code: \(targetLanguage.code)).
        Rules:
        - Output ONLY the translated text. Do not include notes, explanations, greetings, or surrounding XML tags.
        - Preserve original line breaks, paragraph structure, bullet points, markdown, URLs, and code identifiers.
        - Match the register, tone, and punctuation style of the source text.
        - If the text is already in \(targetLanguage.englishName), return it unchanged.
        """
    }

    public static func userPrompt(for text: String, targetLanguage: Language) -> String {
        """
        Translate into \(targetLanguage.englishName) (\(targetLanguage.nativeName)):
        <source_text>
        \(text)
        </source_text>
        """
    }

    public static func cleanOutput(_ raw: String, originalSource: String) -> String {
        var result = raw

        // Strip any <think>...</think> blocks produced by reasoning models
        if let thinkRegex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = thinkRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip accidental <source_text> or <translation> wrappers
        for tag in ["<source_text>", "</source_text>", "<translation>", "</translation>"] {
            result = result.replacingOccurrences(of: tag, with: "")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Preserve leading/trailing newline structure if the original source had trailing newline
        if originalSource.hasSuffix("\n") && !result.hasSuffix("\n") && !result.isEmpty {
            result += "\n"
        }

        return result
    }
}

public enum HUDStatus: Equatable, Sendable {
    case idle
    case downloadingModel(progress: Double, languageName: String)
    case loadingModel(languageName: String)
    case translating(languageName: String, engineBadge: String)
    case completed(languageName: String)
    case error(message: String)
}

@MainActor
@Observable
public final class TranslationCoordinator {
    public static let shared = TranslationCoordinator()

    public private(set) var hudStatus: HUDStatus = .idle
    public private(set) var activeSelection: CapturedSelection?
    public private(set) var isBusy: Bool = false

    public let appleBackend = AppleFoundationModelBackend()

    private var currentTask: Task<Void, Never>?
    private var hudDismissTask: Task<Void, Never>?

    public var onShowHUD: ((CGPoint) -> Void)?
    public var onHideHUD: (() -> Void)?
    public var onShowLanguagePicker: ((CapturedSelection) -> Void)?
    public var onHideLanguagePicker: (() -> Void)?
    public var onAccessibilityMissing: (() -> Void)?

    private init() {}

    public var activeEngineSummary: String {
        let appleStatus = appleBackend.availabilityStatus()
        switch AppPreferences.shared.enginePreference {
        case .auto:
            if appleStatus.isAvailable {
                return "Apple Intelligence (On-Device)"
            }
            return "Local GGUF · \(ModelManager.shared.modelStatusSummary)"
        case .appleOnly:
            return appleStatus.statusDescription
        case .llamaCppOnly:
            return "Local GGUF · \(ModelManager.shared.modelStatusSummary)"
        }
    }

    public func triggerQuickTranslate() {
        onHideLanguagePicker?()
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            await performQuickTranslate()
        }
    }

    public func triggerLanguagePicker() {
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            await prepareLanguagePicker()
        }
    }

    public func confirmPickerTranslation(to language: Language) {
        guard let selection = activeSelection else {
            onHideLanguagePicker?()
            return
        }
        onHideLanguagePicker?()
        AppPreferences.shared.recordLanguageUse(language)

        currentTask?.cancel()
        currentTask = Task { @MainActor in
            await executeTranslation(selection: selection, targetLanguage: language)
        }
    }

    public func cancelPicker() {
        let previousPID = activeSelection?.sourceAppPID
        activeSelection = nil
        onHideLanguagePicker?()
        if let pid = previousPID,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    private func performQuickTranslate() async {
        PermissionsManager.shared.refresh()
        guard PermissionsManager.shared.isAccessibilityGranted else {
            PermissionsManager.shared.requestAccessibilityPrompt()
            onAccessibilityMissing?()
            showTemporaryHUD(.error(message: "Grant Accessibility permission to Presto"), near: NSEvent.mouseLocation, duration: 3.2)
            return
        }

        do {
            let selection = try await TextSelectionBridge.shared.captureSelection()
            let language = AppPreferences.shared.defaultLanguage
            AppPreferences.shared.recordLanguageUse(language)
            await executeTranslation(selection: selection, targetLanguage: language)
        } catch {
            showTemporaryHUD(.error(message: error.localizedDescription), near: NSEvent.mouseLocation, duration: 2.2)
        }
    }

    private func prepareLanguagePicker() async {
        PermissionsManager.shared.refresh()
        guard PermissionsManager.shared.isAccessibilityGranted else {
            PermissionsManager.shared.requestAccessibilityPrompt()
            onAccessibilityMissing?()
            showTemporaryHUD(.error(message: "Grant Accessibility permission to Presto"), near: NSEvent.mouseLocation, duration: 3.2)
            return
        }

        do {
            let selection = try await TextSelectionBridge.shared.captureSelection()
            activeSelection = selection
            onHideHUD?()
            onShowLanguagePicker?(selection)
        } catch {
            showTemporaryHUD(.error(message: error.localizedDescription), near: NSEvent.mouseLocation, duration: 2.2)
        }
    }

    private func executeTranslation(selection: CapturedSelection, targetLanguage: Language) async {
        hudDismissTask?.cancel()
        isBusy = true
        defer {
            isBusy = false
            activeSelection = nil
        }

        let anchor = selection.anchorPoint

        do {
            let translated = try await runTranslationEngine(
                text: selection.text,
                targetLanguage: targetLanguage,
                anchor: anchor
            )
            try Task.checkCancellation()

            try await TextSelectionBridge.shared.replaceSelection(selection, with: translated)
            showTemporaryHUD(.completed(languageName: targetLanguage.englishName), near: anchor, duration: 1.0)
        } catch is CancellationError {
            onHideHUD?()
            hudStatus = .idle
        } catch {
            showTemporaryHUD(.error(message: error.localizedDescription), near: anchor, duration: 3.0)
        }
    }

    private func runTranslationEngine(
        text: String,
        targetLanguage: Language,
        anchor: CGPoint
    ) async throws -> String {
        let preference = AppPreferences.shared.enginePreference
        let appleAvailable = appleBackend.availabilityStatus().isAvailable

        let shouldUseApple: Bool
        switch preference {
        case .appleOnly:
            guard appleAvailable else {
                throw NSError(
                    domain: "Presto",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: appleBackend.availabilityStatus().statusDescription]
                )
            }
            shouldUseApple = true
        case .auto:
            shouldUseApple = appleAvailable
        case .llamaCppOnly:
            shouldUseApple = false
        }

        if shouldUseApple {
            hudStatus = .translating(languageName: targetLanguage.englishName, engineBadge: "Apple LLM")
            onShowHUD?(anchor)
            return try await appleBackend.translate(text: text, to: targetLanguage)
        }

        // Fallback / selected: embedded llama.cpp GGUF
        let modelURL: URL
        if let resolved = ModelManager.shared.resolvedModelURL {
            modelURL = resolved
        } else {
            hudStatus = .downloadingModel(progress: 0, languageName: targetLanguage.englishName)
            onShowHUD?(anchor)

            let progressPoller = Task { @MainActor in
                while !Task.isCancelled && ModelManager.shared.isDownloading {
                    self.hudStatus = .downloadingModel(
                        progress: ModelManager.shared.downloadProgress,
                        languageName: targetLanguage.englishName
                    )
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { progressPoller.cancel() }

            modelURL = try await ModelManager.shared.ensureModelAvailable()
        }

        let alreadyLoaded = await LlamaCppBackend.shared.isModelLoaded()
        if !alreadyLoaded {
            hudStatus = .loadingModel(languageName: targetLanguage.englishName)
            onShowHUD?(anchor)
        } else {
            hudStatus = .translating(languageName: targetLanguage.englishName, engineBadge: "Local GGUF")
            onShowHUD?(anchor)
        }

        return try await LlamaCppBackend.shared.translate(
            text: text,
            to: targetLanguage,
            modelURL: modelURL,
            onLoadingModel: {
                Task { @MainActor in
                    TranslationCoordinator.shared.hudStatus = .loadingModel(languageName: targetLanguage.englishName)
                }
            }
        )
    }

    private func showTemporaryHUD(_ status: HUDStatus, near anchor: CGPoint, duration: Double) {
        hudDismissTask?.cancel()
        hudStatus = status
        onShowHUD?(anchor)
        hudDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.onHideHUD?()
            self.hudStatus = .idle
        }
    }
}
