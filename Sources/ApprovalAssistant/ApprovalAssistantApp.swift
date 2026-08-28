import SwiftUI

@main
struct ApprovalAssistantApp: App {
    private static let menuBarPositionKey = "NSStatusItem Preferred Position Item-0"
    private static let visibleMenuBarPosition = 235

    @StateObject private var monitor = ApprovalMonitor()

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.menuBarPositionKey) == nil {
            defaults.set(Self.visibleMenuBarPosition, forKey: Self.menuBarPositionKey)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(monitor: monitor)
        } label: {
            Image(systemName: monitor.isEnabled ? "checkmark.shield.fill" : "shield.slash")
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("Approval Assistant")
        }
        .menuBarExtraStyle(.menu)
    }
}
