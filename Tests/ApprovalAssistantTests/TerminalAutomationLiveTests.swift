import AppKit
import XCTest
@testable import ApprovalAssistant

@MainActor
final class TerminalAutomationLiveTests: XCTestCase {
    func testParsesTabsWithAndWithoutWindowIDs() {
        let separator = "\u{1f}"
        let records = [
            ["42", "1", "/dev/ttys001", "true", "prompt"],
            ["", "2", "/dev/ttys002", "true", "prompt"],
        ].map { $0.joined(separator: separator) }.joined(separator: "\u{1e}")
        let snapshots = TerminalAutomation().parseSnapshots(records)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?.windowID, 42)
        XCTAssertNil(snapshots.last?.windowID)
        XCTAssertEqual(snapshots.last?.tty, "/dev/ttys002")
    }

    func testAnswersWithMissingWindowIDAndStaleTabPosition() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }
        try runControlledAction(
            prompt: threeChoicePrompt,
            choice: .approveOnce,
            expectedResponse: "1",
            discardWindowLocation: true
        )
    }

    func testApprovesInBackgroundWithoutRestoringMinimizedWindow() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }
        try runControlledAction(
            prompt: threeChoicePrompt, choice: .approveOnce,
            expectedResponse: "1", background: true
        )
    }

    func testApprovesUnselectedTab() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }
        try runControlledAction(
            prompt: threeChoicePrompt, choice: .approveOnce,
            expectedResponse: "1", unselected: true
        )
    }

    func testScansCodexTerminalTabsWithoutSendingInput() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_LIVE_TEST=1 to run the read-only Terminal scan.")
        }

        let snapshots = try TerminalAutomation().scanTabs()
        let codexTabs = snapshots.filter(\.containsCodexProcess)
        let waitingPrompts = codexTabs.compactMap { snapshot -> (String, CodexApprovalPrompt)? in
            guard let prompt = PromptMatcher.match(contents: snapshot.contents) else {
                return nil
            }
            return (snapshot.tty, prompt)
        }

        XCTAssertFalse(codexTabs.isEmpty)
        XCTAssertTrue(codexTabs.allSatisfy { $0.tty.hasPrefix("/dev/ttys") })

        if ProcessInfo.processInfo.environment["CODEX_APPROVAL_EXPECT_PROMPT"] == "1" {
            XCTAssertFalse(waitingPrompts.isEmpty)
            for (tty, prompt) in waitingPrompts {
                print("recognized tty=\(tty), supportsRemember=\(prompt.supportsRemember)")
            }
        }
    }

    func testAnswersFixtureTabAndSendsApproveOnce() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }

        try runControlledAction(
            prompt: threeChoicePrompt,
            choice: .approveOnce,
            expectedResponse: "1"
        )
    }

    func testRememberModeFallsBackToApproveOnceForTwoChoicePrompt() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }

        try runControlledAction(
            prompt: twoChoicePrompt,
            choice: .approveAndRemember,
            expectedResponse: "1"
        )
    }

    func testAnswersCurrentCommandPromptAndSendsApproveOnce() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }

        try runControlledAction(
            prompt: currentTwoChoiceCommandPrompt,
            choice: .approveAndRemember,
            expectedResponse: "1"
        )
    }

    func testAnswersCurrentPermissionsPromptAndSendsRemember() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_ACTION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_ACTION_TEST=1 to run the controlled Terminal input test.")
        }

        try runControlledAction(
            prompt: currentPermissionsPrompt,
            choice: .approveAndRemember,
            expectedResponse: "2"
        )
    }

    func testInstalledAppAutomaticallyApprovesControlledPrompt() throws {
        guard ProcessInfo.processInfo.environment["CODEX_APPROVAL_INSTALLED_APP_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_APPROVAL_INSTALLED_APP_TEST=1 to test the running installed app.")
        }

        let fileManager = FileManager.default
        let fixtureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("approval-assistant-installed-\(UUID().uuidString)", isDirectory: true)
        let fixtureSource = fixtureDirectory.appendingPathComponent("codex.c")
        let fixtureExecutable = fixtureDirectory.appendingPathComponent("codex")
        let responseFile = fixtureDirectory.appendingPathComponent("response.txt")

        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        try controlledCodexSource.write(to: fixtureSource, atomically: true, encoding: .utf8)
        try compileFixture(source: fixtureSource, executable: fixtureExecutable)
        defer { try? fileManager.removeItem(at: fixtureDirectory) }

        let encodedPrompt = Data(currentTwoChoiceCommandPrompt.utf8).base64EncodedString()
        let command = "printf '%s' '\(encodedPrompt)' | /usr/bin/base64 -D; exec '\(fixtureExecutable.path)' '\(responseFile.path)'"
        let fixtureTTY = try openFixtureTab(command: command)
        defer { try? closeFixtureWindow(tty: fixtureTTY) }

        XCTAssertTrue(try waitForResponse(at: responseFile).hasPrefix("1"))

        let loggedEntry = try XCTUnwrap(waitForLogEntry(tty: fixtureTTY))
        XCTAssertEqual(loggedEntry.responseNumber, 1)
        XCTAssertEqual(loggedEntry.promptKind, .command)
        XCTAssertEqual(loggedEntry.description, "Controlled current command Approval Assistant test")
    }

    private func runControlledAction(
        prompt: String,
        choice: ApprovalChoice,
        expectedResponse: String,
        discardWindowLocation: Bool = false,
        background: Bool = false,
        unselected: Bool = false
    ) throws {
        let fileManager = FileManager.default
        let fixtureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("approval-assistant-\(UUID().uuidString)", isDirectory: true)
        let fixtureSource = fixtureDirectory.appendingPathComponent("codex.c")
        let fixtureExecutable = fixtureDirectory.appendingPathComponent("codex")
        let responseFile = fixtureDirectory.appendingPathComponent("response.txt")

        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        try controlledCodexSource.write(to: fixtureSource, atomically: true, encoding: .utf8)
        try compileFixture(source: fixtureSource, executable: fixtureExecutable)
        defer { try? fileManager.removeItem(at: fixtureDirectory) }

        let encodedPrompt = Data(prompt.utf8).base64EncodedString()
        let command = "printf '%s' '\(encodedPrompt)' | /usr/bin/base64 -D; exec '\(fixtureExecutable.path)' '\(responseFile.path)'"
        let fixtureTTY = try openFixtureTab(command: command)
        defer { try? closeFixtureWindow(tty: fixtureTTY) }

        let automation = TerminalAutomation()
        var snapshot = try waitForFixtureSnapshot(automation: automation, tty: fixtureTTY)
        if discardWindowLocation {
            snapshot = TerminalTabSnapshot(
                windowID: nil, tabIndex: 999, tty: snapshot.tty,
                containsCodexProcess: true, contents: snapshot.contents
            )
        }
        var matchedPrompt = try XCTUnwrap(PromptMatcher.match(contents: snapshot.contents))

        let previousApp = NSWorkspace.shared.frontmostApplication
        defer {
            if background || unselected { previousApp?.activate() }
        }
        if background {
            _ = try executeAppleScript("""
                tell application "Terminal"
                    set miniaturized of window id \(try XCTUnwrap(snapshot.windowID)) to true
                end tell
                tell application "Finder" to activate
                """)
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.finder")
        }
        var selectedTTY: String?
        if unselected {
            let windowID = try XCTUnwrap(snapshot.windowID)
            _ = try executeAppleScript("""
                tell application "Terminal"
                    set index of window id \(windowID) to 1
                    activate
                    if id of front window is not \(windowID) then error "Fixture is not frontmost"
                end tell
                tell application "System Events" to keystroke "t" using command down
                """)
            Thread.sleep(forTimeInterval: 0.5)
            selectedTTY = try executeAppleScript("tell application \"Terminal\" to get tty of selected tab of front window")
            try XCTSkipIf(selectedTTY == fixtureTTY, "Terminal did not create a separate fixture tab.")
            _ = try executeAppleScript("tell application \"Finder\" to activate")
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.finder")
            snapshot = try waitForFixtureSnapshot(automation: automation, tty: fixtureTTY)
            matchedPrompt = try XCTUnwrap(PromptMatcher.match(contents: snapshot.contents))
        }
        defer {
            if let selectedTTY, selectedTTY != fixtureTTY { try? closeFixtureWindow(tty: selectedTTY) }
        }
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let result = try automation.answer(
            snapshot: snapshot,
            expectedPrompt: matchedPrompt,
            responseNumber: matchedPrompt.responseNumber(for: choice)
        )

        XCTAssertEqual(result, .sent)
        XCTAssertTrue(try waitForResponse(at: responseFile).hasPrefix(expectedResponse))
        if let selectedTTY {
            let after = try executeAppleScript("tell application \"Terminal\" to get tty of selected tab of front window")
            XCTAssertEqual(after, selectedTTY)
        }
        if background || unselected {
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foregroundPID)
        }
        if background {
            let minimized = try executeAppleScript("""
                tell application "Terminal"
                    return miniaturized of window id \(try XCTUnwrap(snapshot.windowID)) as text
                end tell
                return "missing"
                """)
            XCTAssertEqual(minimized, "true")
        }
    }

    private func openFixtureTab(command: String) throws -> String {
        let script = #"""
        tell application "Terminal"
            set fixtureTab to do script "\#(escapeForAppleScript(command))"
            return tty of fixtureTab
        end tell
        """#
        return try executeAppleScript(script)
    }

    private func waitForFixtureSnapshot(
        automation: TerminalAutomation,
        tty: String
    ) throws -> TerminalTabSnapshot {
        for _ in 0..<100 {
            if let snapshot = try automation.scanTabs().first(where: {
                $0.tty == tty && $0.containsCodexProcess && PromptMatcher.match(contents: $0.contents) != nil
            }) {
                return snapshot
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("The controlled Terminal fixture did not become ready.")
        throw NSError(
            domain: "ApprovalAssistantTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The controlled Terminal fixture did not become ready."]
        )
    }

    private func waitForResponse(at url: URL) throws -> String {
        for _ in 0..<100 {
            if let response = try? String(contentsOf: url, encoding: .utf8), !response.isEmpty {
                return response
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("The controlled Terminal fixture did not receive a response.")
        return ""
    }

    private func waitForLogEntry(tty: String) -> ApprovalLogEntry? {
        for _ in 0..<100 {
            if let entry = ApprovalLogStore().entries.first(where: { $0.tty == tty }) {
                return entry
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("The installed app did not persist the controlled approval log entry.")
        return nil
    }

    private func closeFixtureWindow(tty: String) throws {
        let script = #"""
        tell application "Terminal"
            repeat with wi from 1 to count of windows
                try
                set currentWindow to window wi
                repeat with currentTab in tabs of currentWindow
                    if tty of currentTab is "\#(escapeForAppleScript(tty))" then
                        close currentWindow
                        return "closed"
                    end if
                end repeat
                on error errorMessage number errorNumber
                    if errorNumber is not -1728 and errorNumber is not -1719 and errorNumber is not -10000 then error errorMessage number errorNumber
                end try
            end repeat
            return "missing"
        end tell
        """#
        _ = try executeAppleScript(script)
    }

    private func executeAppleScript(_ source: String) throws -> String {
        let script = try XCTUnwrap(NSAppleScript(source: source))
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            XCTFail("AppleScript failed: \(errorInfo)")
        }
        return result.stringValue ?? ""
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func compileFixture(source: URL, executable: URL) throws {
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = [source.path, "-o", executable.path]
        compiler.standardError = Pipe()
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
    }

    private var controlledCodexSource: String {
        """
        #include <stdio.h>

        int main(int argc, char **argv) {
            if (argc != 2) return 2;

            char response[32];
            if (fgets(response, sizeof(response), stdin) == NULL) return 3;

            FILE *output = fopen(argv[1], "w");
            if (output == NULL) return 4;
            fputs(response, output);
            fclose(output);
            return 0;
        }
        """
    }

    private var threeChoicePrompt: String {
        """
        Would you like to proceed?

        Description: Controlled Approval Assistant test
        Destination: temporary fixture

        1. Yes, proceed (y)
        2. Yes, and don't ask again for commands that start with `fixture` (a)
        3. No, and tell Codex what to do differently (esc)
        """
    }

    private var twoChoicePrompt: String {
        """
        Would you like to proceed?

        Description: Controlled two-choice Approval Assistant test

        1. Yes, proceed (y)
        2. No, and tell Codex what to do differently (esc)

        Press enter to confirm or esc to cancel
        """
    }

    private var currentTwoChoiceCommandPrompt: String {
        """
        Would you like to run the following command?

        Reason: Controlled current command Approval Assistant test

        1. Yes, just this once
        2. No, and tell Codex what to do differently

        Press enter to confirm or esc to cancel
        """
    }

    private var currentPermissionsPrompt: String {
        """
        Would you like to grant these permissions?

        1. Yes, just this once
        2. Yes, and allow these permissions for this session
        3. No, continue without running it

        Press enter to confirm or esc to cancel
        """
    }
}
