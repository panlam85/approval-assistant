import AppKit
import SwiftUI

@MainActor
final class ApprovalLogWindowController {
    private var windowController: NSWindowController?

    func show(logStore: ApprovalLogStore) {
        NSApplication.shared.setActivationPolicy(.accessory)

        if let windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            windowController.window?.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: ApprovalLogView(logStore: logStore)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Approval Log"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 520))
        window.minSize = NSSize(width: 620, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
