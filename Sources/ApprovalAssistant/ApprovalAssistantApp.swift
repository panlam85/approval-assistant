import SwiftUI

@main
struct ApprovalAssistantApp: App {
    @StateObject private var monitor = ApprovalMonitor()

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
