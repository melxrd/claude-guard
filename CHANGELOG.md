# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.2] — 2026-07-27

Fixes from a second external audit, focused on supply chain and disclosure.

### Changed — auto-resume is now a question, not a default
The installer asks whether to enable auto-resume and records the answer. With no
terminal to ask on — `curl | bash` — it stays off, because silence is not
consent. Existing `guard.conf` files are never touched, so upgrades keep
whatever you already chose.

### Added
- `SECURITY.md`: every network destination, what happens to the OAuth token,
  what gets executed unattended, and how to pin a release instead of tracking
  `main`.
- The README now shows a tag-pinned install alongside the one-liner, and states
  plainly that `curl | bash` runs whatever `main` holds at that moment.

### Fixed
- State directory is created `chmod 700`. It holds usage data, blocked prompts
  and working directory paths — not credentials, but not world-readable either.
- README claimed 25 tests; there are 28.

### Changed
- The undocumented status of the OAuth endpoint is stated in the README, not
  only in the docs, together with `USE_OAUTH_FALLBACK=false` for anyone who
  would rather not use it.
- `docs/agent-setup.md` no longer offers `--permission-mode acceptEdits` as a
  fix an assistant may suggest on its own.

## [1.0.1] — 2026-07-27

Fixes from an external code audit.

### Fixed
- **Source order matched the documentation.** The code tried ccusage before the
  OAuth endpoint, so anyone with ccusage installed silently got a local estimate
  instead of authoritative data. Now: OpenUsage → OAuth → ccusage, with a
  regression test.
- **`ccusage` runs under a timeout** (`CCUSAGE_TIMEOUT`, 8s). It is a node app
  on the hot path and previously had none.
- **Auto-resume survives on Linux.** The systemd unit sets `KillMode=process`
  and resumes are launched with `setsid`; without both, systemd killed the
  resumed session when the watcher exited.
- **The installer records an absolute `CLAUDE_BIN`.** launchd and systemd do not
  load your shell profile, so auto-resume failed silently for anyone using nvm
  or a version manager.
- **`CACHE_TTL` raised to 150s**, above the 90s watcher interval. At 60s the
  cache was stale by design and hooks paid for an inline refresh.
- **The OAuth token no longer appears in `ps`.** Headers are passed through a
  curl config file on stdin instead of argv.
- **`settings.json` backups are pruned** to the five most recent.

### Changed
- The agent setup guide moved from the README to `docs/agent-setup.md`.
- README corrected where it overstated: hooks can make one bounded network call
  when the cache is stale, and "fails open" has one deliberate exception — an
  unknown reset time with a known over-limit percentage blocks.
- `OAUTH_USAGE_URL` is configurable, for proxies and for testing.

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
