# Changelog

## 0.1.5 — 2026-09-14

- Continue scanning and locating approval targets past unreadable Terminal windows that return AppleEvent error -10000.
- Add live coverage for approval in an inactive native Terminal tab while another app retains focus and the selected Terminal tab remains unchanged.

## 0.1.4 — 2026-09-14

- Send approvals directly to the requesting tab in the background, without bringing Terminal forward or changing its selected tab or minimized state.
- Remove explicit Terminal activation that could switch macOS Spaces.
- Add a live regression test verifying another app keeps focus and a minimized Terminal fixture stays minimized while receiving approval.

## 0.1.3 — 2026-09-14

- Continue scanning Terminal windows when a window ID is missing.
- Locate approval tabs by TTY so approvals do not depend on window IDs or stale window positions.
- Recheck the target session after bringing its window forward.

## 0.1.2 — 2026-08-28

- Added support for current Codex command and permission approval prompts.
- Recognized both `Yes, proceed` and `Yes, just this once` choice layouts.
- Added matcher, Terminal action, and installed-app regression coverage for the current Codex CLI wording.

## 0.1.1 — 2026-08-28

- Added a native Approval Log window for successful automatic approvals.
- Stored bounded structured metadata locally with owner-only file permissions.
- Added a confirmed Clear Log action and corruption-safe loading.
- Added persistence, retention, metadata-extraction, and installed-app regression tests.

## 0.1.0 — 2026-08-28

- Initial native macOS menu-bar release.
- Added exact two-choice and three-choice Codex prompt matching.
- Added multi-window Terminal monitoring, safe tab activation, and Open at Login.
