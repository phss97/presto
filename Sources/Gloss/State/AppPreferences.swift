import Foundation
import Observation

public enum EnginePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case appleOnly
    case llamaCppOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            return "Automatic (Apple Intelligence, then Local GGUF)"
        case .appleOnly:
            return "Apple Intelligence Only"
        case .llamaCppOnly:
            return "Embedded Local GGUF (llama.cpp) Only"
        }
    }

    public var shortTitle: String {
        switch self {
        case .auto:
            return "Auto"
        case .appleOnly:
            return "Apple LLM"
        case .llamaCppOnly:
            return "Local GGUF"
        }
    }
}

@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    private enum Keys {
        static let defaultLanguageCode = "gloss.defaultLanguageCode"
        static let recentLanguageCodes = "gloss.recentLanguageCodes"
        static let quickTranslateShortcut = "gloss.quickTranslateShortcut"
        static let pickerTranslateShortcut = "gloss.pickerTranslateShortcut"
        static let enginePreference = "gloss.enginePreference"
        static let customModelPath = "gloss.customModelPath"
    }

    private let defaults = UserDefaults.standard

    public var defaultLanguageCode: String {
        didSet {
            defaults.set(defaultLanguageCode, forKey: Keys.defaultLanguageCode)
        }
    }

    public var recentLanguageCodes: [String] {
        didSet {
            defaults.set(recentLanguageCodes, forKey: Keys.recentLanguageCodes)
        }
    }

    public var quickTranslateShortcut: KeyShortcut {
        didSet {
            saveCodable(quickTranslateShortcut, forKey: Keys.quickTranslateShortcut)
            onShortcutsChanged?()
        }
    }

    public var pickerTranslateShortcut: KeyShortcut {
        didSet {
            saveCodable(pickerTranslateShortcut, forKey: Keys.pickerTranslateShortcut)
            onShortcutsChanged?()
        }
    }

    public var enginePreference: EnginePreference {
        didSet {
            defaults.set(enginePreference.rawValue, forKey: Keys.enginePreference)
        }
    }

    public var customModelPath: String? {
        didSet {
            if let customModelPath, !customModelPath.isEmpty {
                defaults.set(customModelPath, forKey: Keys.customModelPath)
            } else {
                defaults.removeObject(forKey: Keys.customModelPath)
            }
        }
    }

    public var onShortcutsChanged: (() -> Void)?

    public var defaultLanguage: Language {
        get { Language.find(code: defaultLanguageCode) }
        set { defaultLanguageCode = newValue.code }
    }

    public var recentLanguages: [Language] {
        recentLanguageCodes.compactMap { code in
            Language.catalog.first { $0.code == code }
        }
    }

    private init() {
        self.defaultLanguageCode = defaults.string(forKey: Keys.defaultLanguageCode) ?? Language.defaultLanguage.code
        self.recentLanguageCodes = defaults.stringArray(forKey: Keys.recentLanguageCodes) ?? ["en", "pt-BR", "es", "fr", "de"]
        self.quickTranslateShortcut = Self.loadCodable(KeyShortcut.self, from: defaults, key: Keys.quickTranslateShortcut)
            ?? .defaultQuickTranslate
        self.pickerTranslateShortcut = Self.loadCodable(KeyShortcut.self, from: defaults, key: Keys.pickerTranslateShortcut)
            ?? .defaultLanguagePicker
        if let rawEngine = defaults.string(forKey: Keys.enginePreference),
           let parsed = EnginePreference(rawValue: rawEngine) {
            self.enginePreference = parsed
        } else {
            self.enginePreference = .auto
        }
        self.customModelPath = defaults.string(forKey: Keys.customModelPath)
    }

    public func recordLanguageUse(_ language: Language) {
        var updated = recentLanguageCodes.filter { $0 != language.code }
        updated.insert(language.code, at: 0)
        if updated.count > 6 {
            updated = Array(updated.prefix(6))
        }
        recentLanguageCodes = updated
    }

    public func resetShortcutsToDefaults() {
        quickTranslateShortcut = .defaultQuickTranslate
        pickerTranslateShortcut = .defaultLanguagePicker
    }

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
