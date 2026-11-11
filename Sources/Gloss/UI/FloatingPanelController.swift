import AppKit
import SwiftUI

private final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class KeyCapableFloatingPanel: NSPanel {
    var onResignKeyPanel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKeyPanel?()
    }
}

@MainActor
public final class FloatingPanelController {
    public static let shared = FloatingPanelController()

    private var hudPanel: NonActivatingHUDPanel?
    private var pickerPanel: KeyCapableFloatingPanel?

    private init() {}

    public func showHUD(near anchorPoint: CGPoint) {
        let panel: NonActivatingHUDPanel
        if let existing = hudPanel {
            panel = existing
        } else {
            let created = NonActivatingHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .statusBar
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            created.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView: TranslationHUDView(coordinator: .shared))
            created.contentView = hosting
            self.hudPanel = created
            panel = created
        }

        if let contentView = panel.contentView {
            let fitting = contentView.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                panel.setContentSize(fitting)
            }
        }

        let origin = clampedOrigin(
            for: panel.frame.size,
            near: anchorPoint,
            verticalOffset: -panel.frame.height - 8
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    public func hideHUD() {
        hudPanel?.orderOut(nil)
    }

    public func showLanguagePicker(for selection: CapturedSelection) {
        hidePicker(notifyCancel: false)

        let panelSize = NSSize(width: 416, height: 376)
        let panel = KeyCapableFloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.onResignKeyPanel = {
            Task { @MainActor in
                if TranslationCoordinator.shared.activeSelection != nil {
                    TranslationCoordinator.shared.cancelPicker()
                }
            }
        }

        let pickerView = LanguagePickerView(
            selection: selection,
            onSelect: { language in
                TranslationCoordinator.shared.confirmPickerTranslation(to: language)
            },
            onCancel: {
                TranslationCoordinator.shared.cancelPicker()
            }
        )
        let hosting = NSHostingView(rootView: pickerView)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting

        let origin = clampedOrigin(
            for: panelSize,
            near: selection.anchorPoint,
            verticalOffset: -panelSize.height - 6
        )
        panel.setFrameOrigin(origin)

        self.pickerPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hidePicker(notifyCancel: Bool = false) {
        guard let panel = pickerPanel else { return }
        panel.onResignKeyPanel = nil
        panel.orderOut(nil)
        pickerPanel = nil
        if notifyCancel {
            TranslationCoordinator.shared.cancelPicker()
        }
    }

    private func clampedOrigin(for size: NSSize, near point: CGPoint, verticalOffset: CGFloat) -> CGPoint {
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = targetScreen?.visibleFrame else {
            return CGPoint(x: point.x - size.width / 2, y: point.y + verticalOffset)
        }

        let margin: CGFloat = 12
        var x = point.x - (size.width / 2)
        var y = point.y + verticalOffset

        // If below bottom of screen, place above the selection instead
        if y < visibleFrame.minY + margin {
            y = point.y + 24
        }

        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)

        return CGPoint(x: x, y: y)
    }
}
