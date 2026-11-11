import AppKit
import Carbon
import Foundation

public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public static let defaultQuickTranslate = KeyShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    public static let defaultLanguagePicker = KeyShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | optionKey | shiftKey)
    )

    public var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyLabel(for: keyCode)
        return result
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    public var hasRequiredModifier: Bool {
        let nonShiftMask = UInt32(controlKey | optionKey | cmdKey)
        return (carbonModifiers & nonShiftMask) != 0
    }

    public static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}

private let hotkeySignature: OSType = 0x474C_4F53 // 'GLOS'

private func glossHotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotkeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let id = hotKeyID.id
    Task { @MainActor in
        HotkeyManager.shared.handleTriggeredHotkey(id: id)
    }
    return noErr
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()

    public var onQuickTranslate: (() -> Void)?
    public var onLanguagePicker: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var quickHotKeyRef: EventHotKeyRef?
    private var pickerHotKeyRef: EventHotKeyRef?

    private init() {
        installHandlerIfNeeded()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            glossHotkeyEventHandler,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }

    public func register(quickTranslate: KeyShortcut, languagePicker: KeyShortcut) {
        unregisterAll()

        let quickID = EventHotKeyID(signature: hotkeySignature, id: 1)
        RegisterEventHotKey(
            quickTranslate.keyCode,
            quickTranslate.carbonModifiers,
            quickID,
            GetApplicationEventTarget(),
            0,
            &quickHotKeyRef
        )

        if languagePicker != quickTranslate {
            let pickerID = EventHotKeyID(signature: hotkeySignature, id: 2)
            RegisterEventHotKey(
                languagePicker.keyCode,
                languagePicker.carbonModifiers,
                pickerID,
                GetApplicationEventTarget(),
                0,
                &pickerHotKeyRef
            )
        }
    }

    public func unregisterAll() {
        if let quickHotKeyRef {
            UnregisterEventHotKey(quickHotKeyRef)
            self.quickHotKeyRef = nil
        }
        if let pickerHotKeyRef {
            UnregisterEventHotKey(pickerHotKeyRef)
            self.pickerHotKeyRef = nil
        }
    }

    fileprivate func handleTriggeredHotkey(id: UInt32) {
        switch id {
        case 1:
            onQuickTranslate?()
        case 2:
            onLanguagePicker?()
        default:
            break
        }
    }
}
