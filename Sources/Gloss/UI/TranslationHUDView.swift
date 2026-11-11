import SwiftUI

public struct TranslationHUDView: View {
    public let coordinator: TranslationCoordinator

    public init(coordinator: TranslationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 10) {
            leadingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = secondaryText {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(14)
        .fixedSize()
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch coordinator.hudStatus {
        case .idle:
            GlossTemplateMarkView(size: 15)
                .opacity(0.75)
        case .downloadingModel(let progress, _):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .loadingModel, .translating:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private var primaryText: String {
        switch coordinator.hudStatus {
        case .idle:
            return "Gloss"
        case .downloadingModel(let progress, _):
            let pct = Int((progress * 100).rounded())
            return "Downloading local model (\(pct)%)…"
        case .loadingModel(let languageName):
            return "Loading local model for \(languageName)…"
        case .translating(let languageName, _):
            return "Translating to \(languageName)…"
        case .completed(let languageName):
            return "Translated to \(languageName)"
        case .error(let message):
            return message
        }
    }

    private var secondaryText: String? {
        switch coordinator.hudStatus {
        case .downloadingModel:
            return "One-time setup · Stored on Mac"
        case .translating(_, let badge):
            return badge
        default:
            return nil
        }
    }
}
