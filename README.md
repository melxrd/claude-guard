# claude-reserve

**A usage kill switch for Claude Code.** Stops Claude at 90% of your usage
window so you keep a reserve, then resumes the interrupted work when the window
resets.

```bash
curl -fsSL https://raw.githubusercontent.com/melxrd/claude-reserve/main/install.sh | bash
```

macOS and Linux. Restart your Claude Code sessions afterwards — hooks load at
startup. Uninstall: same command with `--uninstall`.

**Before you run that**, read [SECURITY.md](SECURITY.md). This tool reads your
Claude Code OAuth token, and the command above executes whatever `main` contains
at the moment you run it. Pinning a release is the safer habit:

```bash
git clone https://github.com/melxrd/claude-reserve
cd claude-reserve
git checkout v1.2.3        # a tag you can audit, not a moving branch
./install.sh --dry-run     # see exactly what it would do
./install.sh
```

## Why this exists

You burn the 5-hour window on routine work by eleven. The urgent thing arrives
at half past. Nothing left for four hours.

Existing tools show you a percentage and let you walk off the cliff, or retry
after you have already hit it. claude-reserve stops you before it, keeping the
last 10% for the moment you actually need it.

## The rule

```
block  if  usage ≥ THRESHOLD  and  the window resets in more than GRACE minutes
allow  otherwise
```

Defaults: **90%** and **30 minutes**, separately for the 5-hour and weekly
window. The grace window matters — with 20 minutes left there is nothing to
save, so blocking would be pure friction.

Three deliberate choices:

- **Fails open.** If usage data is missing or stale, you are not blocked. Set
  `FAIL_MODE=closed` if you disagree. One deliberate exception: when the
  percentage is known and over the limit but the reset time is not, it blocks —
  it cannot tell whether you are inside the grace window.
- **Every block says how to undo it.** `claude-reserve bypass 30` — the command is
  in the message, so you never have to remember it.
- **Nothing is lost.** The blocked prompt is saved; the working directory is
  queued for resume.

## What it looks like

```
claude-reserve
  guard          : enabled
  bypass         : no
  data source    : oauth (updated 12s ago)
  plan           : Max
  5h window      : 91.4% (limit 90%) - resets in 96 min
  weekly         : 58.2% (limit 95%) - resets in 83h
  pending resume : 1 session(s) - run: claude-reserve resume

  decision now   : BLOCK 5h window at 91.4% (limit 90%), resets in 96 min. Reserve protected.
```

`data source` is whichever of the three answered first. `oauth` is the default
and needs nothing installed.

## Commands

```bash
claude-reserve status         # usage, limits, and the decision right now
claude-reserve bypass 60      # let everything through for an hour
claude-reserve unbypass       # re-arm
claude-reserve pending        # sessions waiting to resume
claude-reserve resume --run   # resume them
claude-reserve selftest       # re-run the policy tests
claude-reserve decision       # just the ALLOW/BLOCK line, for scripts
```

Config lives in `~/.claude/claude-reserve/reserve.conf` and applies immediately — no
restart. To test a threshold, lower it below your current percentage and watch
the `decision now` line.

## Install details

The installer copies one script to `~/.claude/claude-reserve/`, adds three hooks to
`~/.claude/settings.json` (backing it up, leaving your existing hooks alone),
schedules a watcher every 90 seconds (launchd or systemd user timer), registers
the status line if that slot is free, and puts `claude-reserve` on your `PATH`.

Upgrading from **claude-guard**? The installer moves your old config, log and
state across, removes the old watcher and hooks, and keeps every setting.

**Requires:** bash, `curl`, `python3`. Optional: `terminal-notifier` (macOS),
`libnotify-bin` (Linux).

## Resuming after a reset

Blocked sessions record their working directory. When the window rolls over,
claude-reserve runs:

```bash
cd <blocked directory> && claude --continue -p "Continue where you left off."
```

**The installer asks before enabling this.** An agent restarting while you are
away spends quota and may edit files, so it is a question rather than a default.
Answer at the prompt, or set `AUTO_RESUME` in `reserve.conf` later. Piped through
`curl` there is no terminal to ask, so it stays **off** — silence is not
consent. Capped at 3 sessions and 12 hours.
See [docs/auto-resume.md](docs/auto-resume.md).

## Where the numbers come from

| Source | Accuracy | Notes |
|---|---|---|
| Claude Code's status line | authoritative | Free: no request at all. Registered by the installer if the slot is free. |
| [OpenUsage](https://github.com/robinebers/openusage) local API | authoritative | Instant, no rate limit. Optional. |
| Anthropic OAuth usage endpoint | authoritative | Undocumented, rate-limited; queried every 5 min at most. |
| [ccusage](https://github.com/ryoppippi/ccusage) | estimate | Local logs only; blind to other machines. |

First one that answers wins. claude-reserve reads your Claude Code token and never
rewrites it — including no token refresh, since a bad rotation could sign you
out. See [docs/data-sources.md](docs/data-sources.md).

Most installs never reach the OAuth endpoint at all: Claude Code hands its
status line a `rate_limits` blob after every response, and capturing that is
free and authoritative. The installer claims the status line only if you do not
already have one; if you do, it prints how to wrap yours.

The OAuth endpoint is **undocumented**: it is the one Claude Code itself uses,
queried with your own credentials for your own data, but Anthropic never
promised it would keep working and may change it without notice. If you would
rather not touch it, set `USE_OAUTH_FALLBACK=false` and run OpenUsage instead.

Hooks read a cache the watcher refreshes in the background — a few milliseconds
per tool call. They do not normally touch the network. The exception: if the
cache is older than `CACHE_TTL` (150s, deliberately longer than the 90s watcher
interval) a hook refreshes it inline, which costs up to a few seconds once. A
failure backoff then keeps the next calls fast.

## Notifications

| Channel | Covers | Part of |
|---|---|---|
| Claude app (Remote Control) | "Claude is asking you something" — prompts, questions | Claude Code |
| ntfy | "work finished", "the guard stopped you" | claude-reserve |
| Desktop | everything, while you are at the machine | claude-reserve |

Turn on the first two — they cover different events. Only Claude Code's push can
reach you while Claude waits for an answer; its "task finished" push is the less
reliable half, which is where ntfy comes in.

**Native:** Claude app, same account, then `/config` → enable `Enable Remote
Control for all sessions`, `Push when actions required`, `Push when Claude
decides`. **If those settings are missing from `/config`, you have
`DO_NOT_TRACK=1` set** — it disables the feature-flag service Remote Control
depends on.

**ntfy:** set `NTFY_TOPIC`, install the app, subscribe to the same topic. No
account, and it works with `DO_NOT_TRACK` set.

Details and the iOS gotchas: [docs/notifications.md](docs/notifications.md).

## Limits

- **Cannot stop Claude Cowork** — no hook system, and its sessions run in the
  cloud. You get an alert; closing them is manual.
- **Protects one machine** — the hooks are in that machine's `settings.json`.
- **Only as accurate as the source** — with ccusage alone, the numbers are a
  local estimate.

## Setting it up for someone else

If an AI assistant is installing this for you — or you are that assistant —
[docs/agent-setup.md](docs/agent-setup.md) is a six-step script with the exact
commands, what to check after each, and what to tell the user.

## How it works

| Hook | Purpose |
|---|---|
| `PreToolUse` | Deny the tool call and halt the turn when over the limit |
| `UserPromptSubmit` | Stop new turns; save the prompt |
| `Stop` | Notify when a turn finishes, with duration and usage |

A watcher (launchd / systemd user timer) refreshes the cache every 90 seconds,
fires threshold alerts once per window, and detects the rollover that triggers a
resume.

## Tests

```bash
./tests/run-tests.sh
```

49 checks: the policy table (thresholds, grace, fail-open, fail-closed, bypass
expiry) plus integration tests against fake usage and push servers — blocking,
resume queue, window-reset detection, source priority, timeouts, notification
throttling, input validation, the https-only rule for the token, and behaviour
when every source is down. No network, no effect on real state. CI runs them on
macOS and Ubuntu.

## Menu bar (macOS)

```
CR 42%      normal        CR 93% ⛔   blocking
CR 78%      past 75%      CR 42% ⊖   bypass active
```

`extras/swiftbar/claude-reserve.30s.sh` shows the 5-hour window in the menu bar
and puts both countdowns, pending resumes and one-click bypass/resume in the
dropdown. Works with [SwiftBar](https://swiftbar.app) or
[xbar](https://xbarapp.com):

```bash
brew install --cask swiftbar && open -a SwiftBar   # pick a plugin folder
cp extras/swiftbar/claude-reserve.30s.sh <that-folder>/
chmod +x <that-folder>/claude-reserve.30s.sh
```

Then SwiftBar → *Refresh all*. Keep the `.30s.` in the name: it is the refresh
interval. Full setup and troubleshooting in [docs/menu-bar.md](docs/menu-bar.md).

## Docs

- [Configuration](docs/configuration.md) — every setting
- [Data sources](docs/data-sources.md) — where the percentages come from
- [Auto-resume](docs/auto-resume.md) — what an unattended restart means
- [Notifications](docs/notifications.md) — desktop, phone, and the iOS gotchas
- [Menu bar](docs/menu-bar.md) — the macOS plugin, and what each state means
- [Troubleshooting](docs/troubleshooting.md) — wrong blocks, and missing ones
- [Security](SECURITY.md) — what it reads, what it runs, how to pin a release

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). A new data source is one `fetch_*`
function and one branch in the normaliser.

## Lifespan

Anthropic has open requests for this behaviour
([#47276](https://github.com/anthropics/claude-code/issues/47276),
[#43149](https://github.com/anthropics/claude-code/issues/43149),
[#34817](https://github.com/anthropics/claude-code/issues/34817)). If they ship
it, this becomes unnecessary — a good outcome. Until then, it is here.

## License

MIT — see [LICENSE](LICENSE).
