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

    func testMatchesCurrentThreeChoiceCodexPrompt() {
        XCTAssertNotNil(PromptMatcher.match(contents: validPrompt))
    }

    func testMatchesCurrentFileEditPrompt() {
        XCTAssertNotNil(PromptMatcher.match(contents: validFileEditPrompt))
    }

    func testMatchesTwoChoicePrompt() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: validTwoChoicePrompt))

        XCTAssertFalse(prompt.supportsRemember)
        XCTAssertEqual(prompt.responseNumber(for: .approveOnce), 1)
        XCTAssertEqual(prompt.responseNumber(for: .approveAndRemember), 1)
    }

    func testThreeChoicePromptUsesRememberResponse() throws {
        let prompt = try XCTUnwrap(PromptMatcher.match(contents: validPrompt))

        XCTAssertTrue(prompt.supportsRemember)
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
