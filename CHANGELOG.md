# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-07-27

First public release.

### Added
- Threshold-based blocking for the 5-hour and weekly usage windows, via the
  `PreToolUse` and `UserPromptSubmit` hooks.
- Grace window: no blocking when the window resets within `GRACE` minutes,
  because there is nothing left to save at that point.
- Fail-open by default when usage data is missing or stale, with
  `FAIL_MODE=closed` available for the opposite preference.
- `bypass` / `unbypass` with an expiry, surfaced in every block message.
- Auto-resume: blocked sessions are recorded with their working directory and
  relaunched when the window rolls over. Bounded by `AUTO_RESUME_MAX` and
  `AUTO_RESUME_MAX_AGE_H`; `claude-guard resume` for the manual path.
- Three usage sources tried in order: OpenUsage local API, the Anthropic OAuth
  usage endpoint, and ccusage.
- Desktop notifications on macOS and Linux; optional phone push via ntfy, with
  blocks sent at high priority.
- Turn-finished notifications with duration, usage and project directory,
  suppressed for turns shorter than `NOTIFY_MIN_TURN_SEC`.
- Non-destructive `settings.json` patching with automatic backups.
- launchd (macOS) and systemd user timer (Linux) watcher installation.
- 25-check test suite with fake usage and push servers; CI on macOS and Ubuntu.

### Deliberately not implemented
- OAuth token refresh. Rotation gone wrong could sign you out of Claude Code,
  which is not an acceptable risk for an unattended background process. See
  `docs/data-sources.md`.
