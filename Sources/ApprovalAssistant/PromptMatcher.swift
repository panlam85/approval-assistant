import CryptoKit
import Foundation

enum ApprovalPromptKind: String, Codable, Equatable {
    case command
    case fileEdits = "file_edits"
    case permissions

    var title: String {
        switch self {
        case .command:
            return "Command"
        case .fileEdits:
            return "File edits"
        case .permissions:
            return "Permissions"
        }
    }
}

struct CodexApprovalPrompt: Equatable {
    let signature: String
    let supportsRemember: Bool
    let kind: ApprovalPromptKind
    let description: String?
    let destinations: [String]

    func responseNumber(for choice: ApprovalChoice) -> Int {
        choice == .approveAndRemember && supportsRemember ? 2 : 1
    }
}

enum PromptMatcher {
    private static let promptTitles: [(text: String, kind: ApprovalPromptKind)] = [
        ("Would you like to proceed?", .command),
        ("Would you like to run the following command?", .command),
        ("Would you like to make the following edits?", .fileEdits),
        ("Would you like to grant these permissions?", .permissions),
    ]
    private static let approveOncePattern = #"(?m)^[ \t›>]*1\.\s+Yes(?:,|\b)"#
    private static let approveAndRememberPattern = #"(?m)^[ \t›>]*2\.\s+Yes(?:,|\b)"#
    private static let threeChoiceRejectPattern = #"(?m)^[ \t›>]*3\.\s+No(?:,|\b)"#
    private static let twoChoiceRejectPattern = #"(?m)^[ \t›>]*2\.\s+No(?:,|\b)"#
    private static let maximumPromptCharacters = 8_000
    private static let maximumTrailingNonEmptyLines = 3
    private static let maximumLogFieldCharacters = 500
    private static let maximumLoggedDestinations = 10

    static func match(contents: String) -> CodexApprovalPrompt? {
        let normalized = normalize(contents)
        let searchableSuffix = String(normalized.suffix(maximumPromptCharacters))

        guard let matchedTitle = promptTitles
            .compactMap({ title -> (range: Range<String.Index>, kind: ApprovalPromptKind)? in
                guard let range = searchableSuffix.range(of: title.text, options: .backwards) else {
                    return nil
                }
                return (range, title.kind)
            })
            .max(by: { $0.range.lowerBound < $1.range.lowerBound })
        else {
            return nil
        }

        let promptBlock = String(searchableSuffix[matchedTitle.range.lowerBound...])
        guard let onceRange = promptBlock.range(of: approveOncePattern, options: .regularExpression) else {
            return nil
        }

        let rememberRange = promptBlock.range(of: approveAndRememberPattern, options: .regularExpression)
        let threeChoiceRejectRange = promptBlock.range(of: threeChoiceRejectPattern, options: .regularExpression)
        let twoChoiceRejectRange = promptBlock.range(of: twoChoiceRejectPattern, options: .regularExpression)

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
        let description = firstField(named: "Description", in: promptBlock)
            ?? firstField(named: "Reason", in: promptBlock)
        let destinations = fields(named: "Destination", in: promptBlock)

        return CodexApprovalPrompt(
            signature: signature,
            supportsRemember: supportsRemember,
            kind: matchedTitle.kind,
            description: description,
            destinations: destinations
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func firstField(named name: String, in promptBlock: String) -> String? {
        fields(named: name, in: promptBlock, limit: 1).first
    }

    private static func fields(
        named name: String,
        in promptBlock: String,
        limit: Int = maximumLoggedDestinations
    ) -> [String] {
        let prefix = "\(name):"
        let values = promptBlock
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix(prefix) else {
                    return nil
                }
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else {
                    return nil
                }
                return String(value.prefix(maximumLogFieldCharacters))
            }
        return Array(values.prefix(limit))
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
