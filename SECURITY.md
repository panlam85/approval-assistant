# Security policy

## Supported versions

Security fixes target the latest version on `main`. Older versions do not receive
separate backports; update and rebuild before checking whether a problem persists.

## Report a vulnerability

Use GitHub's [private vulnerability reporting form](https://github.com/panlam85/approval-assistant/security/advisories/new)
to report suspected security issues to the maintainer. If the form is unavailable,
email [p.lambis@gmail.com](mailto:p.lambis@gmail.com) with the subject
`Approval Assistant security report`.

Please include:

- The app version or commit, macOS version, and Codex CLI version.
- Reproduction steps using a harmless, controlled Terminal fixture.
- Expected and observed behavior, and the potential impact.
- A minimal, redacted prompt example if it helps reproduce the issue.

Do not publish vulnerabilities in public issues or pull requests before a fix or
coordinated disclosure. Never include credentials, private source code, full
Terminal scrollback, or an unredacted approval log in a report.

The maintainer will review reports and coordinate next steps through the private
reporting channel. This volunteer project cannot guarantee a response or fix
within a specific time.

## Security scope

Issues of particular interest include approving malformed or stale prompts,
sending input to the wrong Terminal tab, and exposing private Terminal or approval
log data. Automatic approval of recognized prompts while enabled is the app's
intended behavior; see the [safety model](README.md#safety-model) for its limits.

If you suspect unintended approvals, pause or quit Approval Assistant while
investigating. Disabling its Terminal permission in macOS Automation settings also
prevents further Terminal access.
