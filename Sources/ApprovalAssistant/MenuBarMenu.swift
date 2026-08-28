import AppKit
import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var monitor: ApprovalMonitor

    var body: some View {
        Button(monitor.isEnabled ? "Pause Automatic Approval" : "Enable Automatic Approval") {
            monitor.isEnabled.toggle()
        }

        Menu("When Codex asks") {
            ForEach(ApprovalChoice.allCases) { choice in
                Button {
                    monitor.approvalChoiceRawValue = choice.rawValue
                } label: {
                    if monitor.approvalChoice == choice {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        }

        Divider()

        Text(monitor.lastEvent)

        Button(monitor.isScanning ? "Scanning Terminal…" : "Scan Without Approving") {
            monitor.probeNow()
        }
        .disabled(monitor.isScanning)

        Toggle(
            "Open at Login",
            isOn: Binding(
                get: { monitor.launchAtLoginEnabled },
                set: { monitor.setLaunchAtLogin($0) }
            )
        )

        Button("Automation Settings…") {
            monitor.openAutomationSettings()
        }

        Divider()

        Button("Quit Approval Assistant") {
            NSApplication.shared.terminate(nil)
        }
    }
}
