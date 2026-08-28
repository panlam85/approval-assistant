import XCTest
@testable import ApprovalAssistant

@MainActor
final class ApprovalLogStoreTests: XCTestCase {
    func testPersistsNewestEntriesWithOwnerOnlyPermissions() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let store = ApprovalLogStore(fileURL: fixture.file, maximumEntries: 2)
        let first = makeEntry(index: 1)
        let second = makeEntry(index: 2)
        let third = makeEntry(index: 3)

        XCTAssertTrue(store.record(first))
        XCTAssertTrue(store.record(second))
        XCTAssertTrue(store.record(third))
        XCTAssertEqual(store.entries.map(\.id), [third.id, second.id])

        let reloadedStore = ApprovalLogStore(fileURL: fixture.file, maximumEntries: 2)
        XCTAssertEqual(reloadedStore.entries, [third, second])

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.directory.path
        )
        let directoryPermissions = try XCTUnwrap(
            directoryAttributes[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)
    }

    func testClearPersistsAnEmptyLog() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let store = ApprovalLogStore(fileURL: fixture.file)
        XCTAssertTrue(store.record(makeEntry(index: 1)))
        XCTAssertTrue(store.clear())
        XCTAssertTrue(store.entries.isEmpty)

        let reloadedStore = ApprovalLogStore(fileURL: fixture.file)
        XCTAssertTrue(reloadedStore.entries.isEmpty)
        XCTAssertNil(reloadedStore.persistenceError)
    }

    func testCorruptLogFailsClosedWithoutDeletingTheFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.file)

        let store = ApprovalLogStore(fileURL: fixture.file)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertFalse(store.record(makeEntry(index: 1)))
        XCTAssertEqual(try Data(contentsOf: fixture.file), Data("not-json".utf8))

        XCTAssertTrue(store.clear())
        XCTAssertNil(store.persistenceError)
        let clearedEntries = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [Any]
        )
        XCTAssertTrue(clearedEntries.isEmpty)
    }

    private func makeFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("approval-log-tests-\(UUID().uuidString)", isDirectory: true)
        return (
            directory,
            directory.appendingPathComponent("approval-log.json")
        )
    }

    private func makeEntry(index: Int) -> ApprovalLogEntry {
        ApprovalLogEntry(
            id: UUID(),
            approvedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            tty: "/dev/ttys00\(index)",
            responseNumber: index.isMultiple(of: 2) ? 2 : 1,
            prompt: CodexApprovalPrompt(
                signature: "signature-\(index)",
                supportsRemember: true,
                kind: .command,
                description: "Approval \(index)",
                destinations: ["/private/tmp/example-\(index)"]
            )
        )
    }
}
