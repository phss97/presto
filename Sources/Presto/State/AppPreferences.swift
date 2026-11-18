import Foundation
import Observation

public enum EnginePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case hyMT
    case appleOnly
    case qwen
    case translateGemma
    case custom

    public var id: String { rawValue }

    /// Local model this engine translates with; `nil` for Apple Intelligence and custom GGUFs.
    public var localModel: LocalModel? {
        switch self {
        case .hyMT:
            return .hyMT
        case .translateGemma:
            return .translateGemma
        case .qwen:
            return .qwen
        case .appleOnly, .custom:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .hyMT:
            return "HY-MT1.5 1.8B"
        case .appleOnly:
            return "Apple Intelligence"
        case .qwen:
            return "Qwen 2.5 1.5B"
        case .translateGemma:
            return "TranslateGemma 4B"
        case .custom:
            return "Custom GGUF"
        }
    }

    public var shortTitle: String {
        switch self {
        case .custom:
            return "Custom"
        case .appleOnly:
            return "Apple LLM"
        case .hyMT:
            return "HY-MT 1.8B"
        case .translateGemma:
            return "TranslateGemma 4B"
        case .qwen:
            return "Qwen 1.5B"
        }
    }
}

@MainActor
@Observable
public final class AppPreferences {
    public static let shared = AppPreferences()

    private enum Keys {
        static let defaultLanguageCode = "presto.defaultLanguageCode"
        static let recentLanguageCodes = "presto.recentLanguageCodes"
        static let quickTranslateShortcut = "presto.quickTranslateShortcut"
        static let pickerTranslateShortcut = "presto.pickerTranslateShortcut"
        static let enginePreference = "presto.enginePreference"
        static let fallbackEngine = "presto.fallbackEngine"
        static let customModelPath = "presto.customModelPath"
        static let showMenuBarIcon = "presto.showMenuBarIcon"
        static let didOfferLaunchAtLogin = "presto.didOfferLaunchAtLogin"
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
            if fallbackEngine == enginePreference {
                fallbackEngine = nil
            }
        }
    }

    /// Optional model used only when the selected engine isn't ready. `nil` means none.
    public var fallbackEngine: EnginePreference? {
        didSet {
            if let fallbackEngine {
                defaults.set(fallbackEngine.rawValue, forKey: Keys.fallbackEngine)
            } else {
                defaults.removeObject(forKey: Keys.fallbackEngine)
            }
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

    /// Off by default: Presto runs in the background and settings open when you launch the app.
    public var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
        }
    }

    /// Set once Presto has turned on launch at login for the first time, so it never re-enables it after you turn it off.
    public var didOfferLaunchAtLogin: Bool {
        didSet {
            defaults.set(didOfferLaunchAtLogin, forKey: Keys.didOfferLaunchAtLogin)
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
        let customPath = defaults.string(forKey: Keys.customModelPath)
        var engine: EnginePreference
        if let rawEngine = defaults.string(forKey: Keys.enginePreference) {
            // Legacy values: "auto" was Apple-then-Qwen, "llamaCppOnly" was the Qwen engine.
            // A custom .gguf used to override every local engine, so migrate it to its own choice.
            engine = rawEngine == "auto" ? .hyMT
                : rawEngine == "llamaCppOnly" ? .qwen
                : EnginePreference(rawValue: rawEngine) ?? .hyMT
            if (rawEngine == "auto" || rawEngine == "llamaCppOnly"),
               let customPath, !customPath.isEmpty {
                engine = .custom
            }
        } else {
            engine = .hyMT
        }
        self.enginePreference = engine
        if let rawFallback = defaults.string(forKey: Keys.fallbackEngine),
           let parsed = EnginePreference(rawValue: rawFallback),
           parsed != .custom,
           parsed != engine {
            self.fallbackEngine = parsed
        } else {
            self.fallbackEngine = nil
        }
        self.customModelPath = customPath
        self.showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        self.didOfferLaunchAtLogin = defaults.bool(forKey: Keys.didOfferLaunchAtLogin)
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
