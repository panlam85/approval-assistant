import Combine
import Foundation

struct ApprovalLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let approvedAt: Date
    let tty: String
    let responseNumber: Int
    let promptKind: ApprovalPromptKind
    let description: String?
    let destinations: [String]
    let remembered: Bool

    init(
        id: UUID = UUID(),
        approvedAt: Date = .now,
        tty: String,
        responseNumber: Int,
        prompt: CodexApprovalPrompt
    ) {
        self.id = id
        self.approvedAt = approvedAt
        self.tty = tty
        self.responseNumber = responseNumber
        self.promptKind = prompt.kind
        self.description = prompt.description
        self.destinations = prompt.destinations
        self.remembered = responseNumber == 2 && prompt.supportsRemember
    }
}

@MainActor
final class ApprovalLogStore: ObservableObject {
    static let defaultMaximumEntries = 500

    @Published private(set) var entries: [ApprovalLogEntry] = []
    @Published private(set) var persistenceError: String?

    let fileURL: URL
    private let maximumEntries: Int
    private let fileManager: FileManager
    private var isBlockedByCorruptLog = false

    init(
        fileURL: URL? = nil,
        maximumEntries: Int = defaultMaximumEntries,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.maximumEntries = max(1, maximumEntries)
        load()
    }

    @discardableResult
    func record(_ entry: ApprovalLogEntry) -> Bool {
        guard !isBlockedByCorruptLog else {
            return false
        }
        var updatedEntries = [entry] + entries.filter { $0.id != entry.id }
        if updatedEntries.count > maximumEntries {
            updatedEntries.removeLast(updatedEntries.count - maximumEntries)
        }
        return persist(updatedEntries)
    }

    @discardableResult
    func clear() -> Bool {
        persist([])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("Approval Assistant", isDirectory: true)
            .appendingPathComponent("approval-log.json")
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try Self.decoder.decode([ApprovalLogEntry].self, from: data)
                .sorted { $0.approvedAt > $1.approvedAt }
                .prefix(maximumEntries)
                .map { $0 }
            isBlockedByCorruptLog = false
            persistenceError = nil
        } catch {
            isBlockedByCorruptLog = true
            persistenceError = "The approval log could not be read: \(error.localizedDescription)"
        }
    }

    private func persist(_ updatedEntries: [ApprovalLogEntry]) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try Self.encoder.encode(updatedEntries)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            entries = updatedEntries
            isBlockedByCorruptLog = false
            persistenceError = nil
            return true
        } catch {
            persistenceError = "The approval log could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
