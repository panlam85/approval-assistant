import Foundation

enum ApprovalChoice: Int, CaseIterable, Identifiable {
    case approveOnce = 1
    case approveAndRemember = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .approveOnce:
            return "1 — Approve once"
        case .approveAndRemember:
            return "2 — Approve and remember"
        }
    }

    var explanation: String {
        switch self {
        case .approveOnce:
            return "Approves only the command Codex is currently requesting."
        case .approveAndRemember:
            return "Allows matching future commands when Codex offers that option; otherwise approves once."
        }
    }
}
