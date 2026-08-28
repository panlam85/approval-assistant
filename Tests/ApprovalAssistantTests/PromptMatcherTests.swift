import XCTest
@testable import ApprovalAssistant

final class PromptMatcherTests: XCTestCase {
    private let validPrompt = """
    Would you like to proceed?

    Description: Apply the requested change
    Destination: /private/tmp/example

    1. Yes, proceed (y)
    2. Yes, and don't ask again for commands that start with `git status` (a)
    3. No, and tell Codex what to do differently (esc)
    """

    private let validFileEditPrompt = """
    Would you like to make the following edits?

    Description: Apply proposed file edits
    Destination: /private/tmp/example.ts

    1. Yes, proceed (y)
    2. Yes, and don't ask again for these files (a)
    3. No, and tell Codex what to do differently (esc)

    Press enter to confirm or esc to cancel
    """

    private let validTwoChoicePrompt = """
    Would you like to proceed?

    Description: Run a command once

    1. Yes, proceed (y)
    2. No, and tell Codex what to do differently (esc)

    Press enter to confirm or esc to cancel
    """

    private let currentCommandPrompt = """
    Would you like to run the following command?

    Reason: Verify the Approval Assistant fix
    $ git status --short

    1. Yes, proceed (y)
    2. Yes, and don't ask again for commands that start with `git status` (a)
    3. No, and tell Codex what to do differently (esc)

    Press enter to confirm or esc to cancel
    """

    private let currentPermissionsPrompt = """
    Would you like to grant these permissions?

    1. Yes, just this once
    2. Yes, and allow these permissions for this session
    3. No, continue without running it

    Press enter to confirm or esc to cancel
    """

    func testMatchesCurrentThreeChoiceCodexPrompt() {
        XCTAssertNotNil(PromptMatcher.match(contents: validPrompt))
    }

    func testMatchesCurrentFileEditPrompt() {
        XCTAssertNotNil(PromptMatcher.match(contents: validFileEditPrompt))
    }

    func testExtractsOnlyStructuredLogMetadata() throws {
        let promptText = validFileEditPrompt.replacingOccurrences(
            of: "Destination: /private/tmp/example.ts",
            with: "Destination: /private/tmp/example.ts\nDestination: /private/tmp/second.ts"
        )
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: promptText))

        XCTAssertEqual(prompt.kind, .fileEdits)
        XCTAssertEqual(prompt.description, "Apply proposed file edits")
        XCTAssertEqual(
            prompt.destinations,
            ["/private/tmp/example.ts", "/private/tmp/second.ts"]
        )
    }

    func testMatchesTwoChoicePrompt() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: validTwoChoicePrompt))

        XCTAssertFalse(prompt.supportsRemember)
        XCTAssertEqual(prompt.responseNumber(for: .approveOnce), 1)
        XCTAssertEqual(prompt.responseNumber(for: .approveAndRemember), 1)
    }

    func testMatchesCurrentRunCommandPrompt() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: currentCommandPrompt))

        XCTAssertEqual(prompt.kind, .command)
        XCTAssertEqual(prompt.description, "Verify the Approval Assistant fix")
        XCTAssertTrue(prompt.supportsRemember)
        XCTAssertEqual(prompt.responseNumber(for: .approveAndRemember), 2)
    }

    func testMatchesCurrentPermissionsPrompt() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: currentPermissionsPrompt))

        XCTAssertEqual(prompt.kind, .permissions)
        XCTAssertTrue(prompt.supportsRemember)
        XCTAssertEqual(prompt.responseNumber(for: .approveOnce), 1)
        XCTAssertEqual(prompt.responseNumber(for: .approveAndRemember), 2)
    }

    func testThreeChoicePromptUsesRememberResponse() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: validPrompt))

        XCTAssertTrue(prompt.supportsRemember)
        XCTAssertEqual(prompt.kind, .command)
        XCTAssertEqual(prompt.description, "Apply the requested change")
        XCTAssertEqual(prompt.destinations, ["/private/tmp/example"])
        XCTAssertEqual(prompt.responseNumber(for: .approveOnce), 1)
        XCTAssertEqual(prompt.responseNumber(for: .approveAndRemember), 2)
    }

    func testRejectsPromptMissingRememberOption() {
        let incomplete = validPrompt.replacingOccurrences(
            of: "2. Yes, and don't ask again for commands that start with `git status` (a)\n",
            with: ""
        )

        XCTAssertNil(PromptMatcher.match(contents: incomplete))
    }

    func testRejectsPromptThatIsNoLongerAtBottomOfTerminal() {
        let stalePrompt = validPrompt + "\nCodex resumed working.\n" + String(repeating: "output\n", count: 5)

        XCTAssertNil(PromptMatcher.match(contents: stalePrompt))
    }

    func testUsesLatestPromptWhenOldPromptExistsInScrollback() {
        let contents = validPrompt + "\nCompleted.\n" + validPrompt

        XCTAssertNotNil(PromptMatcher.match(contents: contents))
    }

    func testLatchDoesNotHandleSameVisiblePromptTwice() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: validPrompt))
        var latch = PromptLatch()

        XCTAssertTrue(latch.shouldHandle(tty: "/dev/ttys001", prompt: prompt))
        latch.markHandled(tty: "/dev/ttys001", prompt: prompt)
        XCTAssertFalse(latch.shouldHandle(tty: "/dev/ttys001", prompt: prompt))

        latch.reconcile(activePromptTTYs: [])
        XCTAssertTrue(latch.shouldHandle(tty: "/dev/ttys001", prompt: prompt))
    }
}
