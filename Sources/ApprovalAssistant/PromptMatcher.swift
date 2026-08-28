import CryptoKit
import Foundation

struct CodexApprovalPrompt: Equatable {
    let signature: String
    let supportsRemember: Bool

    func responseNumber(for choice: ApprovalChoice) -> Int {
        choice == .approveAndRemember && supportsRemember ? 2 : 1
    }
}

enum PromptMatcher {
    private static let promptTitles = [
        "Would you like to proceed?",
        "Would you like to make the following edits?",
    ]
    private static let approveOnceOption = "1. Yes, proceed"
    private static let approveAndRememberOption = "2. Yes, and don't ask again"
    private static let threeChoiceRejectOption = "3. No,"
    private static let twoChoiceRejectOption = "2. No,"
    private static let maximumPromptCharacters = 8_000
    private static let maximumTrailingNonEmptyLines = 3

    static func match(contents: String) -> CodexApprovalPrompt? {
        let normalized = normalize(contents)
        let searchableSuffix = String(normalized.suffix(maximumPromptCharacters))

        guard let titleRange = promptTitles
            .compactMap({ searchableSuffix.range(of: $0, options: .backwards) })
            .max(by: { $0.lowerBound < $1.lowerBound })
        else {
            return nil
        }

        let promptBlock = String(searchableSuffix[titleRange.lowerBound...])
        guard let onceRange = promptBlock.range(of: approveOnceOption) else {
            return nil
        }

        let rememberRange = promptBlock.range(of: approveAndRememberOption)
        let threeChoiceRejectRange = promptBlock.range(of: threeChoiceRejectOption)
        let twoChoiceRejectRange = promptBlock.range(of: twoChoiceRejectOption)

        let supportsRemember: Bool
        let rejectRange: Range<String.Index>
        if
            let rememberRange,
            let threeChoiceRejectRange,
            onceRange.lowerBound < rememberRange.lowerBound,
            rememberRange.lowerBound < threeChoiceRejectRange.lowerBound
        {
            supportsRemember = true
            rejectRange = threeChoiceRejectRange
        } else if
            let twoChoiceRejectRange,
            onceRange.lowerBound < twoChoiceRejectRange.lowerBound
        {
            supportsRemember = false
            rejectRange = twoChoiceRejectRange
        } else {
            return nil
        }

        let textAfterRejectOption = promptBlock[rejectRange.upperBound...]
        let trailingNonEmptyLines = textAfterRejectOption
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard trailingNonEmptyLines.count <= maximumTrailingNonEmptyLines else {
            return nil
        }

        let digest = SHA256.hash(data: Data(promptBlock.utf8))
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return CodexApprovalPrompt(signature: signature, supportsRemember: supportsRemember)
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

struct PromptLatch {
    private var handledSignaturesByTTY: [String: String] = [:]

    mutating func shouldHandle(tty: String, prompt: CodexApprovalPrompt) -> Bool {
        handledSignaturesByTTY[tty] != prompt.signature
    }

    mutating func markHandled(tty: String, prompt: CodexApprovalPrompt) {
        handledSignaturesByTTY[tty] = prompt.signature
    }

    mutating func reconcile(activePromptTTYs: Set<String>) {
        handledSignaturesByTTY = handledSignaturesByTTY.filter { activePromptTTYs.contains($0.key) }
    }
}
