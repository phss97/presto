import AppKit
import Carbon
import Observation
import SwiftUI

@MainActor
@Observable
public final class ShortcutRecorderModel {
    public static let shared = ShortcutRecorderModel()

    public enum Slot: Equatable {
        case quickTranslate
        case languagePicker
    }

    public var activeSlot: Slot?

    private init() {}
}

public struct ShortcutRecorderButton: View {
    public let title: String
    public let slot: ShortcutRecorderModel.Slot
    @Binding public var shortcut: KeyShortcut

    @Bindable private var recorder = ShortcutRecorderModel.shared

    public init(title: String, slot: ShortcutRecorderModel.Slot, shortcut: Binding<KeyShortcut>) {
        self.title = title
        self.slot = slot
        self._shortcut = shortcut
    }

    private var isRecording: Bool {
        recorder.activeSlot == slot
    }

    public var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                recorder.activeSlot = isRecording ? nil : slot
            } label: {
                Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minWidth: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(.plain)
            .background(
                ShortcutCaptureRepresentable(
                    isRecording: Binding(
                        get: { recorder.activeSlot == slot },
                        set: { active in
                            if !active && recorder.activeSlot == slot {
                                recorder.activeSlot = nil
                            }
                        }
                    ),
                    onCaptured: { captured in
                        shortcut = captured
                        recorder.activeSlot = nil
                    }
                )
            )
        }
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCaptured: (KeyShortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, onCaptured: onCaptured)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCaptured = onCaptured
        context.coordinator.setRecording(isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setRecording(false)
    }

    @MainActor
    final class Coordinator {
        @Binding var isRecording: Bool
        var onCaptured: (KeyShortcut) -> Void
        private nonisolated(unsafe) var monitor: Any?

        init(isRecording: Binding<Bool>, onCaptured: @escaping (KeyShortcut) -> Void) {
            self._isRecording = isRecording
            self.onCaptured = onCaptured
        }

        func setRecording(_ active: Bool) {
            if active && monitor == nil {
                HotkeyManager.shared.unregisterAll()
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    if Int(event.keyCode) == kVK_Escape {
                        self.isRecording = false
                        self.restoreHotkeys()
                        return nil
                    }

                    let carbonMods = KeyShortcut.carbonModifiers(from: event.modifierFlags)
                    let candidate = KeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
                    guard candidate.hasRequiredModifier else {
                        NSSound.beep()
                        return nil
                    }

                    self.onCaptured(candidate)
                    return nil
                }
            } else if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
                restoreHotkeys()
            }
        }

        private func restoreHotkeys() {
            let prefs = AppPreferences.shared
            HotkeyManager.shared.register(
                quickTranslate: prefs.quickTranslateShortcut,
                languagePicker: prefs.pickerTranslateShortcut
            )
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
