# Troubleshooting

```bash
claude-reserve status
tail -30 ~/.claude/claude-reserve/reserve.log
```

`status` shows the data source, its age, and the decision it would make now.
Most problems are visible there.

## A change I made did nothing

**The copy that runs is not the copy you edited.** `git pull` (or editing the
repo) touches the repo; the guard runs from `~/.claude/claude-reserve/`, and the
menu bar runs from SwiftBar's plugin folder. Three places, updated by two
commands:

```bash
cd /path/to/claude-reserve
./install.sh
cp extras/swiftbar/claude-reserve.30s.sh <your-plugin-folder>/
```

Then SwiftBar → *Refresh all*. Check what is actually installed:

```bash
grep -m1 CLAUDE_RESERVE_VERSION= ~/.claude/claude-reserve/claude-reserve
```

If that number is behind the repo's, every symptom you are debugging is the old
code. An unknown flag is not an error either — `resume --run --terminal` on an
older build silently resumes headlessly, which looks exactly like "the button
does nothing".

Hooks are read at session start, so restart open Claude Code sessions after an
upgrade.

## What is running right now

```bash
ps -eo pid,etime,%cpu,command | grep "[c]laude"
```

Read the command column: `-p "Continue where you left off."` is a headless
resume (works alone, output in `resume.log`), plain `--continue` is an
interactive session in a window, neither is a session you opened yourself.
`etime` is how long it has been going.

```bash
lsof -a -p <pid> -d cwd -Fn        # which directory that process is working in
tail -f ~/.claude/claude-reserve/resume.log
```

Stopping headless resumes without touching your own windows — the `-p` is what
tells them apart:

```bash
pkill -f "claude --continue -p"
```

## It never blocks

**Dead data source.** `data source : none`, or a cache minutes old → failing
open by design. Start OpenUsage, or check the log. See
[data-sources.md](data-sources.md).

**Hooks not loaded.** They are read at session start, so a session open during
installation has none:

```bash
grep -c 'claude-reserve hook' ~/.claude/settings.json    # expect 3
```

If it says 3, reopen the session with `claude --continue`.

**A bypass is active.** `status` says so. `claude-reserve unbypass`.

**The status line is not capturing.** If `data source` is not `statusline` and
you expected it to be, check that `statusLine` in `~/.claude/settings.json`
points at `claude-reserve statusline`, and that you have sent at least one
message since. API-key accounts never receive `rate_limits`.

**You are inside the grace window.** Over the threshold but resetting within
`SESSION_GRACE_MIN` — allowing is correct. `status` shows the countdown.

## It blocks when it should not

Read `decision now`: it states the percentage, threshold and minutes to reset.
If those numbers disagree with your other usage tool, the parser picked the
wrong figure — open an issue with `~/.claude/claude-reserve/usage-raw.json`.

With only ccusage as a source, under-reporting is expected (local logs only).
Over-blocking is unusual.

Immediate escape: `claude-reserve bypass 30`.

## The watcher is not running

```bash
# macOS
launchctl list | grep claudereserve
cat ~/.claude/claude-reserve/watch.err.log

# Linux
systemctl --user status claude-reserve.timer
journalctl --user -u claude-reserve.service -n 30
```

Without it the guard still blocks — hooks refresh the cache inline — but you
lose threshold alerts and auto-resume.

## Resume does nothing

First, the usual answer: **it did something, invisibly.** `resume --run` starts
a headless agent — no window opens, and the work shows up in `resume.log`.

```bash
grep resume ~/.claude/claude-reserve/reserve.log
tail -30 ~/.claude/claude-reserve/resume.log
claude-reserve pending
```

A `resume: /some/path` line means it ran. If you want a session you can see,
that is `--terminal`:

```bash
claude-reserve resume --run --terminal
```

If nothing at all happened:

- **Nothing was queued** — `pending` says so. Only sessions blocked by a hook
  are recorded, and Cowork has no hooks, so its blocks are never queued.
- **The installed copy is older than the flag you used** — see *A change I made
  did nothing* above.
- **`claude` not on the watcher's PATH** — launchd and systemd do not load your
  shell profile. Set `CLAUDE_BIN` to an absolute path.
- **Records expired** — anything older than `AUTO_RESUME_MAX_AGE_H` is dropped.
- **Resumed then stalled** — headless `claude -p` waits forever on a permission
  prompt. See [auto-resume.md](auto-resume.md).
- **The terminal never opened** — macOS asks the *calling* app for permission to
  control Terminal, so a click from SwiftBar needs SwiftBar allowed in System
  Settings → Privacy & Security → Automation. When it is refused the session
  stays in the queue and the command to run by hand is printed.

## Blocked and I need to work

```bash
claude-reserve bypass 30
```

Or `GUARD_ENABLED=false` in `reserve.conf` to disable blocking entirely while
keeping notifications. Applies immediately.

## Notifications

**Nothing arrives on the phone.** Check the topic first — a fresh install writes
an empty one, and an empty topic means ntfy is off, not broken:

```bash
grep NTFY_TOPIC ~/.claude/claude-reserve/reserve.conf
```

`NTFY_TOPIC=""` is the answer. Set one, subscribe the app to that exact string,
then `claude-reserve ntfy-test`. Reinstalling or renaming does not carry a topic
across.

The rest, including the Claude app path: [notifications.md](notifications.md).

## Menu bar

See [menu-bar.md](menu-bar.md) — `CR ?` and `CR 0%` each have one specific
cause.

## My prompt disappeared

Blocked prompts are appended to `~/.claude/claude-reserve/blocked-prompts.log` with
a timestamp and directory.

## Remove it

```bash
./install.sh --uninstall
```

Removes hooks (restoring `settings.json`, leaving your other hooks intact), the
watcher and the binary. Config and logs stay in `~/.claude/claude-reserve/`.
