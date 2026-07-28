# Troubleshooting

```bash
claude-reserve status
tail -30 ~/.claude/claude-reserve/reserve.log
```

`status` shows the data source, its age, and the decision it would make now.
Most problems are visible there.

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

## Auto-resume does nothing

```bash
cat ~/.claude/claude-reserve/resume.log
claude-reserve pending
```

- **`claude` not on the watcher's PATH** — launchd and systemd do not load your
  shell profile. Set `CLAUDE_BIN` to an absolute path.
- **Nothing was queued** — only sessions claude-reserve blocked are recorded.
- **Records expired** — anything older than `AUTO_RESUME_MAX_AGE_H` is dropped.
- **Resumed then stalled** — headless `claude -p` waits forever on a permission
  prompt. See [auto-resume.md](auto-resume.md).

## Blocked and I need to work

```bash
claude-reserve bypass 30
```

Or `GUARD_ENABLED=false` in `reserve.conf` to disable blocking entirely while
keeping notifications. Applies immediately.

## Notifications

See [notifications.md](notifications.md).

## My prompt disappeared

Blocked prompts are appended to `~/.claude/claude-reserve/blocked-prompts.log` with
a timestamp and directory.

## Remove it

```bash
./install.sh --uninstall
```

Removes hooks (restoring `settings.json`, leaving your other hooks intact), the
watcher and the binary. Config and logs stay in `~/.claude/claude-reserve/`.
