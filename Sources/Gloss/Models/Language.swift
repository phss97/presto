import Foundation

public struct Language: Identifiable, Hashable, Codable, Sendable {
    public let code: String
    public let englishName: String
    public let nativeName: String
    public let aliases: [String]

    public var id: String { code }

    public init(code: String, englishName: String, nativeName: String, aliases: [String] = []) {
        self.code = code
        self.englishName = englishName
        self.nativeName = nativeName
        self.aliases = aliases
    }

    public var displayLabel: String {
        if englishName == nativeName {
            return englishName
        }
        return "\(englishName) · \(nativeName)"
    }

    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let candidates = [englishName, nativeName, code] + aliases
        return candidates.contains { candidate in
            candidate
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(needle)
        }
    }

    public func matchScore(query: String) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let englishFolded = englishName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let nativeFolded = nativeName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let codeFolded = code.lowercased()

        if englishFolded == needle || nativeFolded == needle || codeFolded == needle {
            return 100
        }
        if englishFolded.hasPrefix(needle) || nativeFolded.hasPrefix(needle) {
            return 80
        }
        if aliases.contains(where: {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).hasPrefix(needle)
        }) {
            return 70
        }
        if matches(query: trimmed) {
            return 40
        }
        return 0
    }
}

extension Language {
    public static let defaultLanguage = catalog[0]

    public static func find(code: String) -> Language {
        catalog.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) ?? defaultLanguage
    }

    public static let catalog: [Language] = [
        Language(code: "en", englishName: "English", nativeName: "English", aliases: ["us", "uk", "american", "british"]),
        Language(code: "pt-BR", englishName: "Portuguese (Brazil)", nativeName: "Português (Brasil)", aliases: ["pt", "portuguese", "portugues", "brazilian"]),
        Language(code: "pt-PT", englishName: "Portuguese (Portugal)", nativeName: "Português (Portugal)", aliases: ["pt", "portuguese", "portugues", "european portuguese"]),
        Language(code: "es", englishName: "Spanish", nativeName: "Español", aliases: ["espanol", "castellano"]),
        Language(code: "fr", englishName: "French", nativeName: "Français", aliases: ["francais"]),
        Language(code: "de", englishName: "German", nativeName: "Deutsch"),
        Language(code: "it", englishName: "Italian", nativeName: "Italiano"),
        Language(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
        Language(code: "ja", englishName: "Japanese", nativeName: "日本語", aliases: ["nihongo", "jp"]),
        Language(code: "ko", englishName: "Korean", nativeName: "한국어", aliases: ["hangul", "kr"]),
        Language(code: "zh-Hans", englishName: "Chinese (Simplified)", nativeName: "简体中文", aliases: ["zh", "mandarin", "chinese", "cn"]),
        Language(code: "zh-Hant", englishName: "Chinese (Traditional)", nativeName: "繁體中文", aliases: ["zh", "taiwanese", "cantonese", "tw", "hk"]),
        Language(code: "ar", englishName: "Arabic", nativeName: "العربية"),
        Language(code: "ru", englishName: "Russian", nativeName: "Русский"),
        Language(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
        Language(code: "pl", englishName: "Polish", nativeName: "Polski"),
        Language(code: "tr", englishName: "Turkish", nativeName: "Türkçe", aliases: ["turkce"]),
        Language(code: "hi", englishName: "Hindi", nativeName: "हिन्दी"),
        Language(code: "sv", englishName: "Swedish", nativeName: "Svenska"),
        Language(code: "da", englishName: "Danish", nativeName: "Dansk"),
        Language(code: "no", englishName: "Norwegian", nativeName: "Norsk"),
        Language(code: "fi", englishName: "Finnish", nativeName: "Suomi"),
        Language(code: "cs", englishName: "Czech", nativeName: "Čeština", aliases: ["cestina"]),
        Language(code: "el", englishName: "Greek", nativeName: "Ελληνικά"),
        Language(code: "he", englishName: "Hebrew", nativeName: "עברית"),
        Language(code: "id", englishName: "Indonesian", nativeName: "Bahasa Indonesia"),
        Language(code: "ms", englishName: "Malay", nativeName: "Bahasa Melayu"),
        Language(code: "th", englishName: "Thai", nativeName: "ไทย"),
        Language(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt", aliases: ["tieng viet"]),
        Language(code: "ro", englishName: "Romanian", nativeName: "Română", aliases: ["romana"]),
        Language(code: "hu", englishName: "Hungarian", nativeName: "Magyar"),
        Language(code: "ca", englishName: "Catalan", nativeName: "Català", aliases: ["catala"])
    ]
}
