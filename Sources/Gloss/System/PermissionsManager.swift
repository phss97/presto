import AppKit
import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
public final class PermissionsManager {
    public static let shared = PermissionsManager()

    public private(set) var isAccessibilityGranted: Bool = false
    private var monitorTask: Task<Void, Never>?

    private init() {
        refresh()
        startMonitoringIfNeeded()
    }

    public func refresh() {
        isAccessibilityGranted = AXIsProcessTrusted()
        if isAccessibilityGranted {
            monitorTask?.cancel()
            monitorTask = nil
        } else {
            startMonitoringIfNeeded()
        }
    }

    public func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startMonitoringIfNeeded() {
        guard monitorTask == nil, !isAccessibilityGranted else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = trusted
                }
                if trusted {
                    self.monitorTask = nil
                    return
                }
            }
        }
    }
}
