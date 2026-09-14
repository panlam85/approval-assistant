import AppKit
import Foundation

struct TerminalTabSnapshot {
    let windowID: Int?
    let tabIndex: Int
    let tty: String
    let containsCodexProcess: Bool
    let contents: String
}

enum TerminalActionResult: String {
    case sent
    case windowMissing = "window_missing"
    case tabMissing = "tab_missing"
    case tabChanged = "tab_changed"
    case codexMissing = "codex_missing"
    case promptGone = "prompt_gone"
}

struct TerminalAutomationError: LocalizedError {
    let code: Int
    let message: String

    var errorDescription: String? {
        if code == -1_743 {
            return "Terminal automation is not allowed. Enable Approval Assistant in System Settings → Privacy & Security → Automation."
        }
        return "Terminal automation failed (\(code)): \(message)"
    }
}

@MainActor
final class TerminalAutomation {
    private let recordSeparator = Character(UnicodeScalar(30))
    private let fieldSeparator = Character(UnicodeScalar(31))

    func scanTabs() throws -> [TerminalTabSnapshot] {
        let script = #"""
        tell application "Terminal"
            set recordSeparator to ASCII character 30
            set fieldSeparator to ASCII character 31
            set maximumContentCharacters to 8000
            set reportText to ""

            -- Enumerate by position: Terminal can report missing value for a window ID.
            -- Unreadable auxiliary windows (-10000) must not block later tabs.
            repeat with windowIndex from 1 to count of windows
                try
                    set currentWindow to window windowIndex
                    set currentWindowID to id of currentWindow
                    if currentWindowID is missing value then set currentWindowID to ""
                    set currentTabCount to count of tabs of currentWindow

                    repeat with tabIndex from 1 to currentTabCount
                        try
                            set currentTab to tab tabIndex of currentWindow
                            set currentTTY to tty of currentTab
                            set currentProcesses to processes of currentTab
                            set hasCodex to currentProcesses contains "codex"
                            set currentContents to get contents of tab tabIndex of window windowIndex
                            set currentContentLength to length of currentContents
                            if currentContentLength > maximumContentCharacters then
                                set currentContents to text (currentContentLength - maximumContentCharacters + 1) thru currentContentLength of currentContents
                            end if

                            set reportText to reportText & currentWindowID & fieldSeparator & tabIndex & fieldSeparator & currentTTY & fieldSeparator & hasCodex & fieldSeparator & currentContents & recordSeparator
                        on error errorMessage number errorNumber
                            if errorNumber is not -1728 and errorNumber is not -1719 and errorNumber is not -10000 then error errorMessage number errorNumber
                        end try
                    end repeat
                on error errorMessage number errorNumber
                    if errorNumber is not -1728 and errorNumber is not -1719 and errorNumber is not -10000 then error errorMessage number errorNumber
                end try
            end repeat

            return reportText
        end tell
        """#

        let rawResult = try execute(script)
        return parseSnapshots(rawResult)
    }

    func answer(
        snapshot: TerminalTabSnapshot,
        expectedPrompt: CodexApprovalPrompt,
        responseNumber: Int
    ) throws -> TerminalActionResult {
        guard snapshot.tty.range(of: #"^/dev/ttys[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
            throw TerminalAutomationError(code: -1, message: "Terminal returned an invalid TTY identifier.")
        }
        guard responseNumber == 1 || responseNumber == 2 else {
            throw TerminalAutomationError(code: -1, message: "The selected approval response is invalid.")
        }

        guard
            let currentSnapshot = try scanTabs().first(where: {
                $0.tty == snapshot.tty
                    && $0.containsCodexProcess
            }),
            PromptMatcher.match(contents: currentSnapshot.contents) == expectedPrompt
        else {
            return .promptGone
        }

        let script = #"""
        tell application "Terminal"
            -- Resolve the session afresh by TTY; window/tab positions can change.
            set targetWindowIndex to 0
            set targetTabIndex to 0
            repeat with wi from 1 to count of windows
                try
                    repeat with ti from 1 to count of tabs of window wi
                        if tty of tab ti of window wi is "\#(snapshot.tty)" then
                            set targetWindowIndex to wi as integer
                            set targetTabIndex to ti as integer
                            exit repeat
                        end if
                    end repeat
                on error errorMessage number errorNumber
                    if errorNumber is not -1728 and errorNumber is not -1719 and errorNumber is not -10000 then error errorMessage number errorNumber
                end try
                if targetWindowIndex is not 0 then exit repeat
            end repeat
            if targetWindowIndex is 0 then return "tab_missing"
            set targetTab to tab targetTabIndex of window targetWindowIndex

            if tty of targetTab is not "\#(snapshot.tty)" then return "tab_changed"
            if (processes of targetTab) does not contain "codex" then return "codex_missing"

            set currentContents to get contents of tab targetTabIndex of window targetWindowIndex
            set hasLegacyCommandPrompt to currentContents contains "Would you like to proceed?"
            set hasCommandPrompt to currentContents contains "Would you like to run the following command?"
            set hasFileEditPrompt to currentContents contains "Would you like to make the following edits?"
            set hasPermissionsPrompt to currentContents contains "Would you like to grant these permissions?"
            if not hasLegacyCommandPrompt and not hasCommandPrompt and not hasFileEditPrompt and not hasPermissionsPrompt then return "prompt_gone"
            if currentContents does not contain "1. Yes" then return "prompt_gone"
            set hasThreeChoiceLayout to (currentContents contains "2. Yes") and (currentContents contains "3. No")
            set hasTwoChoiceLayout to currentContents contains "2. No"
            if not hasThreeChoiceLayout and not hasTwoChoiceLayout then return "prompt_gone"

            -- Address the existing tab directly without activating Terminal,
            -- selecting a tab, restoring a window, or changing Spaces.
            if tty of targetTab is not "\#(snapshot.tty)" then return "tab_changed"
            if (processes of targetTab) does not contain "codex" then return "codex_missing"
            do script "\#(responseNumber)" in targetTab
            return "sent"
        end tell
        """#

        let rawResult = try execute(script)
        guard let result = TerminalActionResult(rawValue: rawResult) else {
            throw TerminalAutomationError(code: -1, message: "Terminal returned an unknown action result: \(rawResult)")
        }
        return result
    }

    func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func execute(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw TerminalAutomationError(code: -1, message: "The Terminal automation script could not be compiled.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo["NSAppleScriptErrorNumber"] as? Int ?? -1
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "Unknown AppleScript error"
            throw TerminalAutomationError(code: code, message: message)
        }
        return result.stringValue ?? ""
    }

    func parseSnapshots(_ rawValue: String) -> [TerminalTabSnapshot] {
        rawValue
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let fields = rawRecord.split(
                    separator: fieldSeparator,
                    maxSplits: 4,
                    omittingEmptySubsequences: false
                )
                guard
                    fields.count == 5,
                    let tabIndex = Int(fields[1])
                else {
                    return nil
                }

                return TerminalTabSnapshot(
                    windowID: Int(fields[0]),
                    tabIndex: tabIndex,
                    tty: String(fields[2]),
                    containsCodexProcess: fields[3] == "true",
                    contents: String(fields[4])
                )
            }
    }
}
