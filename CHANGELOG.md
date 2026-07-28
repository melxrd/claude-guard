# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.2] — 2026-07-28

### Documented
- `docs/menu-bar.md`: what each menu bar state means, why the plugin folder is
  whatever SwiftBar asked for at first launch rather than a fixed path, why the
  `.30s.` in the filename matters, and the one cause behind each of `CR ?` and
  `CR 0%`.
- The agent setup guide gained a menu bar step, including the trap that updating
  the repo does not update the installed copy under `~/.claude/`.
- `claude-reserve decision` is now listed among the commands in the README.

## [1.2.1] — 2026-07-28

### Fixed
- Numbers were parsed and formatted in the user's locale. On a system where the
  decimal separator is a comma, the menu bar plugin failed with
  `printf: 25.0: invalid number` and showed `0%`, and threshold comparisons
  could read `89.9` as `89`. Both now force `LC_ALL=C` on the individual awk
  call rather than on the shell, so the environment inherited by resumed
  sessions is untouched.

## [1.2.0] — 2026-07-28

### Added
- **macOS menu bar plugin** (`extras/swiftbar/claude-reserve.30s.sh`) for
  SwiftBar or xbar. Shows the 5-hour percentage, red with an alert icon while
  blocking, orange while bypassed or unguarded. The dropdown carries both
  windows with countdowns, pending resumes, the data source, and one-click
  bypass, resume and refresh.
- `claude-reserve decision` prints just the ALLOW/BLOCK line, so integrations do
  not have to scrape `status`.

## [1.1.3] — 2026-07-28

Fixes from a third external audit.

### Fixed
- `AUTO_RESUME` defaulted to `true` in the script while the installer and the
  shipped config set `false`. Running `bin/claude-reserve` from a clone with no
  config therefore had auto-resume on, contradicting the opt-in principle
  stated everywhere else. The script default is now `false`; the installer
  writes `true` when you say yes at the prompt.
- `file_mtime` fell back to the current time when `stat` failed, which would
  make a stale lock look eternally fresh and block refreshes forever. It now
  falls back to the epoch, so an unreadable timestamp makes things look old.

### Added
- A test asserting the script default, the shipped config and the installer all
  agree that auto-resume is off until asked. That is the exact invariant that
  drifted apart unnoticed.

### Documented
- `SECURITY.md` now states that ntfy topics are world-readable to anyone who
  guesses them, and that notifications carry usage percentages and project
  directory names.
- The portable timeout kills direct children only — macOS has no `setsid`, so
  there is no portable process-group kill. A grandchild can outlive the
  timeout but cannot hang the refresh, because output goes to a file rather
  than a pipe. Noted in the code.
- Why hook JSON parsing uses `grep`/`sed` rather than python: it runs on every
  hook call, and an interpreter start on the hot path costs more than it buys.

## [1.1.2] — 2026-07-28

### Fixed
- `claude-reserve help` printed a fixed range of lines, so as the header grew it
  spilled past the comment block into shell code. It now prints the header and
  stops at the first non-comment line.
- The header listed neither `statusline` — the primary usage source — nor
  `version` and `help`.

## [1.1.1] — 2026-07-28

### Fixed
- The line suggesting how to wrap an existing status line quoted the command
  with hand-written single quotes, so a command containing one produced broken
  shell to copy. Now uses `printf %q`. Cosmetic — it was text to copy, never
  executed by the installer.
- The test suite used fixed ports, so a run whose sockets had not been released
  yet could latch onto the previous run's server and read stale data. Ports are
  now allocated by the OS at startup; two suites can run concurrently.

## [1.1.0] — 2026-07-27

### Renamed
The project is now **claude-reserve**. `claude-guard` collided with two
unrelated projects, one of them also a Claude Code plugin that blocks things —
different things. The installer migrates an existing claude-guard install:
config, log and state move to `~/.claude/claude-reserve/`, the old watcher and
hooks are removed, and every setting is kept.

### Added
- **Status line capture, now the primary usage source.** Claude Code hands its
  `statusLine` command a `rate_limits` blob after every response; capturing it
  costs nothing, needs no request, and is server-side truth. Most installs will
  never reach the undocumented OAuth endpoint again. The installer claims the
  status line only when the slot is free; otherwise it prints how to wrap an
  existing one with `claude-reserve statusline --exec '...'`.
  Idea from [ecerutti/claude-usage-guard](https://github.com/ecerutti/claude-usage-guard).
- `claude-reserve statusline` prints a compact usage line, flagged `[BLOCKED]`
  when the guard is holding you back.

### Fixed
- `file_mtime` used BSD `stat` syntax first, which on Linux returned
  non-numeric output and poisoned arithmetic. It had also silently broken stale
  lock recovery. Now picks by platform and validates the result.
- The installer's closing banner announced auto-resume as ON regardless of what
  it had just written. It now reports the real value.
- Upgrades no longer inherit `AUTO_RESUME=true` silently: existing configs are
  still never modified, but the installer says the setting is on.
- `reserve.conf.example` ships with `AUTO_RESUME=false`, so copying it by hand
  is not a surprise either. The installer writes `true` when you say yes.

## [1.0.2] — 2026-07-27

Fixes from a second external audit, focused on supply chain and disclosure.

### Changed — auto-resume is now a question, not a default
The installer asks whether to enable auto-resume and records the answer. With no
terminal to ask on — `curl | bash` — it stays off, because silence is not
consent. Existing `reserve.conf` files are never touched, so upgrades keep
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
  `AUTO_RESUME_MAX_AGE_H`; `claude-reserve resume` for the manual path.
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
