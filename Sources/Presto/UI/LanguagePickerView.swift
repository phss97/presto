import AppKit
import Carbon
import Observation
import SwiftUI

@MainActor
@Observable
final class LanguagePickerState {
    var query: String = ""
    var highlightedIndex: Int = 0
}

public struct LanguagePickerView: View {
    public let selection: CapturedSelection
    public let onSelect: (Language) -> Void
    public let onCancel: () -> Void

    @Bindable private var state: LanguagePickerState
    @FocusState private var isSearchFocused: Bool

    private let preferences = AppPreferences.shared

    public init(
        selection: CapturedSelection,
        onSelect: @escaping (Language) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selection = selection
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.state = LanguagePickerState()
    }

    private var orderedLanguages: [Language] {
        let trimmed = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let defaultLang = preferences.defaultLanguage
            let recents = preferences.recentLanguages.filter { $0.code != defaultLang.code }
            let recentSet = Set(recents.map(\.code) + [defaultLang.code])
            let remaining = Language.catalog.filter { !recentSet.contains($0.code) }
            return [defaultLang] + recents + remaining
        }

        return Language.catalog
            .map { ($0, $0.matchScore(query: trimmed)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.englishName < rhs.0.englishName
            }
            .map(\.0)
    }

    public var body: some View {
        let languages = orderedLanguages
        let clampedIndex = languages.isEmpty ? 0 : min(max(state.highlightedIndex, 0), languages.count - 1)

        VStack(spacing: 0) {
            // Selected text preview bar
            HStack(spacing: 8) {
                PrestoTemplateMarkView(size: 13)
                    .opacity(0.68)

                Text(snippetPreview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let appName = selection.sourceAppName {
                    Text(appName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 8)

            // Search bar
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Translate to language…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFocused)
                    .onSubmit {
                        if !languages.isEmpty {
                            onSelect(languages[clampedIndex])
                        }
                    }

                if !state.query.isEmpty {
                    Button {
                        state.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
                .opacity(0.5)

            // Language list
            if languages.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("No matching language")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(languages.enumerated()), id: \.element.code) { idx, lang in
                                LanguageRow(
                                    language: lang,
                                    isSelected: idx == clampedIndex,
                                    isDefault: lang.code == preferences.defaultLanguageCode,
                                    isRecent: preferences.recentLanguageCodes.contains(lang.code)
                                )
                                .id(lang.code)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(lang)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: clampedIndex) { _, newIdx in
                        if languages.indices.contains(newIdx) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(languages[newIdx].code, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()
                .opacity(0.5)

            // Subtle keyboard hints footer
            HStack(spacing: 12) {
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Translate", systemImage: "return")
                Spacer()
                Text("esc to cancel")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: 380, height: 340)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 10)
        .padding(18)
        .onAppear {
            state.highlightedIndex = 0
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: state.query) { _, _ in
            state.highlightedIndex = 0
        }
        .background(
            PickerKeyEventCatcher(
                onMoveUp: {
                    let count = orderedLanguages.count
                    guard count > 0 else { return }
                    state.highlightedIndex = (clampedIndex - 1 + count) % count
                },
                onMoveDown: {
                    let count = orderedLanguages.count
                    guard count > 0 else { return }
                    state.highlightedIndex = (clampedIndex + 1) % count
                },
                onConfirm: {
                    let current = orderedLanguages
                    if current.indices.contains(clampedIndex) {
                        onSelect(current[clampedIndex])
                    }
                },
                onEscape: {
                    onCancel()
                }
            )
        )
    }

    private var snippetPreview: String {
        selection.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LanguageRow: View {
    let language: Language
    let isSelected: Bool
    let isDefault: Bool
    let isRecent: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(language.englishName)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                if language.nativeName != language.englishName {
                    Text(language.nativeName)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }

            Spacer()

            if isDefault {
                Text("Default")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08)),
                        in: Capsule()
                    )
            } else if isRecent {
                Text("Recent")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }

            Text(language.code)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
    }
}

private struct PickerKeyEventCatcher: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onConfirm: onConfirm,
            onEscape: onEscape
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onConfirm: () -> Void
        var onEscape: () -> Void
        private nonisolated(unsafe) var monitor: Any?

        init(
            onMoveUp: @escaping () -> Void,
            onMoveDown: @escaping () -> Void,
            onConfirm: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onConfirm = onConfirm
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch Int(event.keyCode) {
                case kVK_UpArrow:
                    self.onMoveUp()
                    return nil
                case kVK_DownArrow:
                    self.onMoveDown()
                    return nil
                case kVK_Escape:
                    self.onEscape()
                    return nil
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    self.onConfirm()
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
