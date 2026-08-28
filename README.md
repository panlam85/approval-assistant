# Approval Assistant

Approval Assistant is a small native macOS menu-bar app that watches Apple Terminal tabs running the Codex CLI and answers recognized approval prompts automatically.

It brings the requesting Terminal tab to the front and sends the selected **yes** response. It does not close Terminal windows or tabs.

## What it does

- Runs only in the macOS menu bar, with no Dock icon or permanent window.
- Can be enabled, paused, or quit from a native menu.
- Scans every Apple Terminal window and tab whose process list contains `codex`.
- Recognizes Codex command and file-edit approval prompts.
- Selects the requesting tab before responding.
- Supports approve-once and approve-and-remember modes.
- Can start automatically when you log in.
- Keeps terminal contents on your Mac and makes no network requests.

### Response behavior

| Codex prompt | Approve once | Approve and remember |
| --- | ---: | ---: |
| Three choices: yes / yes and remember / no | `1` | `2` |
| Two choices: yes / no | `1` | `1` |

The app never sends the rejection response. When Codex does not offer a remember option, the remember setting safely falls back to `1`.

## Requirements

- macOS 14 or later
- Apple Terminal
- Codex CLI running in the Terminal tab
- Xcode Command Line Tools to build from source

Other terminal applications are not currently supported.

## Build and run

```sh
git clone https://github.com/panlam85/approval-assistant.git
cd approval-assistant
./scripts/build-app.sh
open "build/Approval Assistant.app"
```

To install it for your user account:

```sh
mkdir -p "$HOME/Applications"
ditto --rsrc "build/Approval Assistant.app" "$HOME/Applications/Approval Assistant.app"
open "$HOME/Applications/Approval Assistant.app"
```

On first use, macOS asks whether Approval Assistant may control Terminal. Allow it under **System Settings → Privacy & Security → Automation**. The app cannot inspect or answer prompts without that permission.

## Using the menu-bar app

Click the shield icon in the menu bar to:

- enable or pause automatic approval;
- choose approve once or approve and remember;
- perform a read-only scan;
- enable Open at Login;
- open macOS Automation settings; or
- quit the app.

The app is intentionally menu-bar-only. Quitting removes its icon and stops all monitoring. If the icon is hidden by a crowded menu bar or a MacBook notch, hold Command and drag the icon closer to the right side of the menu bar.

## Safety model

Automatic approval can allow Codex to execute commands and edit files without another confirmation. Review the risk before enabling it, especially in repositories containing important data or credentials.

Approval Assistant uses a deliberately narrow matcher:

- the tab must report a running `codex` process;
- the prompt title and numbered yes/no options must match a known layout;
- the prompt must still be at the bottom of the terminal output;
- the app re-reads the same tab and revalidates the prompt immediately before sending input;
- each visible prompt is handled once per TTY;
- stale windows or tabs that disappear during a scan are skipped and retried.

Terminal contents are read only for local matching. They are not logged, stored, or sent over the network.

## Tests

Run the unit tests:

```sh
swift test --disable-index-store
```

Run the read-only live Terminal scan:

```sh
CODEX_APPROVAL_LIVE_TEST=1 swift test --disable-index-store \
  --filter TerminalAutomationLiveTests/testScansCodexTerminalTabsWithoutSendingInput
```

The action tests create their own controlled Terminal fixture and close only that fixture window:

```sh
CODEX_APPROVAL_ACTION_TEST=1 swift test --disable-index-store \
  --filter TerminalAutomationLiveTests
```

## Distribution status

The build script creates an ad-hoc signed local app. The repository does not currently publish a notarized binary release, so build from source unless a future release explicitly says otherwise.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please do not include private Terminal output, credentials, or repository contents in bug reports.
