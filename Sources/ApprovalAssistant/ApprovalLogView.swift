import SwiftUI

struct ApprovalLogView: View {
    @ObservedObject var logStore: ApprovalLogStore
    @State private var isShowingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let persistenceError = logStore.persistenceError {
                ContentUnavailableView(
                    "Approval Log Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(persistenceError)
                )
            } else if logStore.entries.isEmpty {
                ContentUnavailableView(
                    "No Approvals Yet",
                    systemImage: "checkmark.shield",
                    description: Text("Successful automatic approvals will appear here.")
                )
            } else {
                List(logStore.entries) { entry in
                    ApprovalLogRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .alert("Clear approval log?", isPresented: $isShowingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Log", role: .destructive) {
                logStore.clear()
            }
        } message: {
            Text("This permanently removes all locally stored approval entries.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Approval Log")
                    .font(.title2.bold())
                Text("\(logStore.entries.count) of \(ApprovalLogStore.defaultMaximumEntries) locally stored entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear Log", role: .destructive) {
                isShowingClearConfirmation = true
            }
            .disabled(logStore.entries.isEmpty && logStore.persistenceError == nil)
        }
        .padding()
    }
}

private struct ApprovalLogRow: View {
    let entry: ApprovalLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(entry.promptKind.title, systemImage: iconName)
                    .font(.headline)

                Spacer()

                Text(entry.approvedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.description ?? "Codex approval prompt")
                .textSelection(.enabled)

            ForEach(entry.destinations, id: \.self) { destination in
                Text(destination)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Text("Response \(entry.responseNumber)")
                if entry.remembered {
                    Text("Remembered")
                }
                Text(entry.tty)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch entry.promptKind {
        case .command:
            return "terminal"
        case .fileEdits:
            return "doc.badge.ellipsis"
        case .permissions:
            return "lock.shield"
        }
    }
}
