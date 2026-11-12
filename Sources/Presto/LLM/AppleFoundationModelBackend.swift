import Foundation
import FoundationModels

public enum AppleFoundationModelStatus: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unavailableOther(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var statusDescription: String {
        switch self {
        case .available:
            return "Available (On-Device Apple Intelligence)"
        case .appleIntelligenceNotEnabled:
            return "Unavailable (Enable Apple Intelligence in System Settings)"
        case .deviceNotEligible:
            return "Unavailable (Mac not eligible for Apple Intelligence)"
        case .modelNotReady:
            return "Preparing on-device Apple model…"
        case .unavailableOther(let detail):
            return "Unavailable (\(detail))"
        }
    }
}

public struct AppleFoundationModelBackend: Sendable {
    public init() {}

    public func availabilityStatus() -> AppleFoundationModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .deviceNotEligible:
                return .deviceNotEligible
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unavailableOther(String(describing: reason))
            }
        }
    }

    public func translate(text: String, to targetLanguage: Language) async throws -> String {
        let rootSchema = DynamicGenerationSchema(
            name: "TranslationOutput",
            description: "Exact translation of the input text into the target language",
            properties: [
                .init(
                    name: "translatedText",
                    description: "Only the translated text, preserving original line breaks, punctuation, capitalization, and formatting",
                    schema: DynamicGenerationSchema(type: String.self)
                )
            ]
        )
        let schema = try GenerationSchema(root: rootSchema, dependencies: [])

        let instructions = TranslationPromptBuilder.systemInstructions(for: targetLanguage)
        let userPrompt = TranslationPromptBuilder.userPrompt(for: text, targetLanguage: targetLanguage)

        let session = LanguageModelSession(
            model: .default,
            instructions: instructions
        )

        let options = GenerationOptions(
            samplingMode: .greedy,
            temperature: 0.1
        )

        let response = try await session.respond(
            to: userPrompt,
            schema: schema,
            options: options
        )

        let raw = try response.content.value(String.self, forProperty: "translatedText")
        return TranslationPromptBuilder.cleanOutput(raw, originalSource: text)
    }
}
