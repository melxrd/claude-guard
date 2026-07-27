# claude-guard

**A usage kill switch for Claude Code.** Stops Claude at 90% of your usage
window so you keep a reserve, then resumes the interrupted work when the window
resets.

```bash
curl -fsSL https://raw.githubusercontent.com/melxrd/claude-guard/main/install.sh | bash
```

macOS and Linux. Restart your Claude Code sessions afterwards — hooks load at
startup. Uninstall: same command with `--uninstall`.

Prefer to read first? `git clone`, then `./install.sh --dry-run`.

## Why this exists

You burn the 5-hour window on routine work by eleven. The urgent thing arrives
at half past. Nothing left for four hours.

Existing tools show you a percentage and let you walk off the cliff, or retry
after you have already hit it. claude-guard stops you before it, keeping the
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

- **Fails open.** Missing or stale usage data never blocks you. Set
  `FAIL_MODE=closed` if you disagree.
- **Every block says how to undo it.** `claude-guard bypass 30` — the command is
  in the message, so you never have to remember it.
- **Nothing is lost.** The blocked prompt is saved; the working directory is
  queued for resume.

## What it looks like

```
claude-guard
  guard          : enabled
  bypass         : no
  data source    : oauth (updated 12s ago)
  plan           : Max
  5h window      : 91.4% (limit 90%) - resets in 96 min
  weekly         : 58.2% (limit 95%) - resets in 83h
  pending resume : 1 session(s) - run: claude-guard resume

  decision now   : BLOCK 5h window at 91.4% (limit 90%), resets in 96 min. Reserve protected.
```

`data source` is whichever of the three answered first. `oauth` is the default
and needs nothing installed.

## Commands

```bash
claude-guard status         # usage, limits, and the decision right now
claude-guard bypass 60      # let everything through for an hour
claude-guard unbypass       # re-arm
claude-guard pending        # sessions waiting to resume
claude-guard resume --run   # resume them
claude-guard selftest       # re-run the policy tests
```

Config lives in `~/.claude/usage-guard/guard.conf` and applies immediately — no
restart. To test a threshold, lower it below your current percentage and watch
the `decision now` line.

## Install details

The installer copies one script to `~/.claude/usage-guard/`, adds three hooks to
`~/.claude/settings.json` (backing it up, leaving your existing hooks alone),
schedules a watcher every 90 seconds (launchd or systemd user timer), and puts
`claude-guard` on your `PATH`.

**Requires:** bash, `curl`, `python3`. Optional: `terminal-notifier` (macOS),
`libnotify-bin` (Linux).

## Resuming after a reset

Blocked sessions record their working directory. When the window rolls over,
claude-guard runs:

```bash
cd <blocked directory> && claude --continue -p "Continue where you left off."
```

**`AUTO_RESUME` is on by default** — an agent restarts while you are away,
spends quota and may edit files. Capped at 3 sessions and 12 hours. Set
`AUTO_RESUME=false` for a notification instead.
See [docs/auto-resume.md](docs/auto-resume.md).

## Where the numbers come from

| Source | Accuracy | Notes |
|---|---|---|
| [OpenUsage](https://github.com/robinebers/openusage) local API | authoritative | Instant, no rate limit. Optional. |
| Anthropic OAuth usage endpoint | authoritative | Undocumented, rate-limited; queried every 5 min at most. |
| [ccusage](https://github.com/ryoppippi/ccusage) | estimate | Local logs only; blind to other machines. |

First one that answers wins. claude-guard reads your Claude Code token and never
rewrites it — including no token refresh, since a bad rotation could sign you
out. See [docs/data-sources.md](docs/data-sources.md).

Hooks make no network calls: they read a cache the watcher refreshes in the
background. A few milliseconds per tool call.

## Notifications

| Channel | Covers | Part of |
|---|---|---|
| Claude app (Remote Control) | "Claude is asking you something" — prompts, questions | Claude Code |
| ntfy | "work finished", "the guard stopped you" | claude-guard |
| Desktop | everything, while you are at the machine | claude-guard |

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

---

## Agent guide

*Setting this up for someone? Follow this — you do not need to read the source.
Run the commands, read the output, say the "**Say:**" lines.*

**Goal:** installed, reading real usage, thresholds matching how they work, and
the user knows the one command that unblocks them.

### 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/melxrd/claude-guard/main/install.sh | bash
```

`✓` fine, `!` warning, `✗` stop. The only likely `✗` is a missing `python3`
(macOS: `xcode-select --install`). If it warns about `PATH`, add
`export PATH="$HOME/.local/bin:$PATH"` and open a new shell.

### 2. Check it sees real usage

```bash
claude-guard status
```

The `data source` line must not be `none`. If it is, the guard is installed but
inert — fix it before saying the user is protected:

- OpenUsage installed → open it, then `claude-guard refresh`.
- Otherwise the OAuth source should work: `claude-guard refresh`, then
  `tail -5 ~/.claude/usage-guard/guard.log`. **On macOS the first read may raise
  a keychain prompt — warn them before it appears.**
- Log says `token rejected` → have them run any Claude Code command once, retry.

> **Say:** "It's reading your real usage from *<source>*. You're at *<N>%* of the
> 5-hour window, *<M>%* of the weekly one."

### 3. Set thresholds to how they work

Ask: **"When you run out, what does it cost you?"** Losing a morning → 90% is
fine. Locked out when a client calls → 80%.

Then check `status`: if the weekly percentage runs far ahead of the 5-hour one
(common on smaller plans), the weekly limit is their real constraint:

```bash
sed -i'' -e 's/^WEEKLY_THRESHOLD=.*/WEEKLY_THRESHOLD=85/' ~/.claude/usage-guard/guard.conf
```

macOS needs `sed -i '' -e ...` — space after `-i`. Verify with `status`.

### 4. Decide about auto-resume

It is on by default and it acts while nobody is watching. Do not skip this.

> **Say:** "When your window resets, claude-guard can restart the work it
> interrupted by itself, while you're away — capped at 3 sessions, forgetting
> anything older than 12 hours. On, or would you rather just get a notification?"

Off:

```bash
sed -i'' -e 's/^AUTO_RESUME=.*/AUTO_RESUME=false/' ~/.claude/usage-guard/guard.conf
```

On, and their work edits files: warn that a headless resume stalls on permission
prompts, and that the fix (`AUTO_RESUME_ARGS="--permission-mode acceptEdits"`)
widens what an unattended agent may do. Only with explicit agreement.

### 5. Notifications

```bash
claude-guard notify-test
```

If nothing appears on macOS, the permission belongs to "Script Editor" or
"terminal-notifier" in System Settings → Notifications — say so, they will look
for "claude-guard".

**Set up both phone channels; they cover different events.**

**Native** (reaches them when Claude asks a question): Claude app, same account
and organisation, notifications allowed. Then `/config` → `Enable Remote Control
for all sessions`, `Push when actions required`, `Push when Claude decides`.
Restart sessions; the app's **Code** tab should show a green dot.

Settings missing from `/config`? Run `claude doctor`. If feature-flag evaluation
is disabled, they have `DO_NOT_TRACK=1`. Offer the narrow fix:

```bash
# ~/.zshrc — keeps DO_NOT_TRACK everywhere except Claude Code
alias claude='env -u DO_NOT_TRACK claude'
```

> **Say:** "That variable turns off Anthropic's feature-flag service, and phone
> notifications are gated behind it. The alias removes it only for Claude Code."

Test by having them walk away — push is suppressed while they are at the
terminal.

**ntfy** (finished work, blocks):

```bash
python3 -c 'import secrets;print("claude-"+secrets.token_hex(8))'
# put it in NTFY_TOPIC in ~/.claude/usage-guard/guard.conf
claude-guard ntfy-test
```

App installed, subscribed to exactly that string.

> **Say:** "That topic is the only thing protecting these notifications — anyone
> who knows it can read them. Don't paste it anywhere public."

**Sent but nothing arrives?** Check the server before any phone setting:

```bash
curl "https://ntfy.sh/$TOPIC/json?poll=1&since=1h"
```

Listed → the phone is the problem. Either the app was in the foreground (iOS
delivers to the app, no banner — retest closed and locked), or it never
registered for push (reinstall, allow notifications **before** subscribing).
Reviewing notification settings will not help; they are already correct.

### 6. Prove it, then hand over

```bash
claude-guard status                      # note the 5h percentage
sed -i'' -e 's/^SESSION_THRESHOLD=.*/SESSION_THRESHOLD=5/' ~/.claude/usage-guard/guard.conf
claude-guard status                      # must now say BLOCK
sed -i'' -e 's/^SESSION_THRESHOLD=.*/SESSION_THRESHOLD=90/' ~/.claude/usage-guard/guard.conf
claude-guard status                      # back to ALLOW
```

> **Say:** "Three things. It stops Claude at *<N>%* and leaves you a reserve. If
> it stops you and you need to work, run `claude-guard bypass 30` — the block
> message tells you every time. And it can't stop Cowork: if an alert arrives
> while Cowork tasks are running, close those yourself."

### Rules

- **Restart their sessions** after installing, or nothing happens.
- **Never leave a lowered threshold behind.** Restore and verify in the same
  session.
- **Do not edit `bin/claude-guard`.** Everything tunable is in `guard.conf`.
- **Do not claim it protects Cowork** or their other machines.
- **If the source is `none`, say so.** Silence leaves them believing they are
  protected when they are not.

---

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

25 checks: the policy table (thresholds, grace, fail-open, fail-closed, bypass
expiry) plus integration tests against fake usage and push servers — blocking,
resume queue, window-reset detection, notification throttling, and behaviour
when every source is down. No network, no effect on real state. CI runs them on
macOS and Ubuntu.

## Docs

- [Configuration](docs/configuration.md) — every setting
- [Data sources](docs/data-sources.md) — where the percentages come from
- [Auto-resume](docs/auto-resume.md) — what an unattended restart means
- [Notifications](docs/notifications.md) — desktop, phone, and the iOS gotchas
- [Troubleshooting](docs/troubleshooting.md) — wrong blocks, and missing ones

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
