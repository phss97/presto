import AppKit
import Foundation
import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so Gloss can start in the background when the user logs in.
@MainActor
@Observable
public final class LoginItemManager {
    public static let shared = LoginItemManager()

    public private(set) var status: SMAppService.Status = .notRegistered
    public private(set) var lastError: String?

    private let service = SMAppService.mainApp

    private init() {
        refresh()
    }

    public var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    public var requiresApproval: Bool {
        status == .requiresApproval
    }

    public func refresh() {
        status = service.status
    }

    public func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// True when macOS started this process as a login item rather than the user opening it.
    public static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
