# Contributing to Approval Assistant

Thanks for helping improve Approval Assistant.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). For suspected security
vulnerabilities, use the private reporting process in [SECURITY.md](SECURITY.md)
instead of a public issue.

## Before opening an issue

- Check that Approval Assistant is enabled in **System Settings → Privacy & Security → Automation → Terminal**.
- Confirm the Codex CLI is running in Apple Terminal, not another terminal application.
- Include your macOS version and whether the prompt had two or three choices.
- Redact commands, paths, credentials, source code, and other private Terminal content.

## Development workflow

1. Fork the repository and create a focused branch.
2. Make the smallest change that solves the problem.
3. Add or update tests for changed prompt-matching or automation behavior.
4. Run `swift test --disable-index-store`.
5. Build the app with `./scripts/build-app.sh`.
6. Open a pull request describing the behavior before and after the change.

## Prompt-matcher changes

Approval Assistant intentionally fails closed on unfamiliar prompts. Changes to `PromptMatcher` should include fixtures covering:

- the exact newly supported prompt;
- both two-choice and three-choice response mapping where applicable;
- stale prompts left in scrollback;
- malformed or incomplete prompts that must remain rejected.

Do not replace exact matching with a broad check for words such as `yes`, `approve`, or `proceed`.

## Terminal automation changes

- Revalidate the tab, TTY, running Codex process, and prompt immediately before sending input.
- Never close, replace, or reuse a user's Terminal window in production code.
- Action tests may close only the controlled fixture window they created.
- Treat windows and tabs disappearing during a scan as a normal race and retry safely.
- Never log, persist, upload, or include full Terminal contents in analytics.
- Approval history may contain only the bounded structured fields represented by `ApprovalLogEntry`.

## Code style

- Keep the project dependency-free unless a dependency is clearly justified.
- Prefer small Swift types with explicit names and narrow responsibilities.
- Keep UI changes native to macOS and accessible through VoiceOver labels.
- Explain security-sensitive behavior in the pull request.
