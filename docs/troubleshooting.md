# Troubleshooting

```bash
claude-guard status
tail -30 ~/.claude/usage-guard/guard.log
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
grep -c 'claude-guard hook' ~/.claude/settings.json    # expect 3
```

If it says 3, reopen the session with `claude --continue`.

**A bypass is active.** `status` says so. `claude-guard unbypass`.

**You are inside the grace window.** Over the threshold but resetting within
`SESSION_GRACE_MIN` — allowing is correct. `status` shows the countdown.

## It blocks when it should not

Read `decision now`: it states the percentage, threshold and minutes to reset.
If those numbers disagree with your other usage tool, the parser picked the
wrong figure — open an issue with `~/.claude/usage-guard/usage-raw.json`.

With only ccusage as a source, under-reporting is expected (local logs only).
Over-blocking is unusual.

Immediate escape: `claude-guard bypass 30`.

## The watcher is not running

```bash
# macOS
launchctl list | grep claudeguard
cat ~/.claude/usage-guard/watch.err.log

# Linux
systemctl --user status claude-guard.timer
journalctl --user -u claude-guard.service -n 30
```

Without it the guard still blocks — hooks refresh the cache inline — but you
lose threshold alerts and auto-resume.

## Auto-resume does nothing

```bash
cat ~/.claude/usage-guard/resume.log
claude-guard pending
```

- **`claude` not on the watcher's PATH** — launchd and systemd do not load your
  shell profile. Set `CLAUDE_BIN` to an absolute path.
- **Nothing was queued** — only sessions claude-guard blocked are recorded.
- **Records expired** — anything older than `AUTO_RESUME_MAX_AGE_H` is dropped.
- **Resumed then stalled** — headless `claude -p` waits forever on a permission
  prompt. See [auto-resume.md](auto-resume.md).

## Blocked and I need to work

```bash
claude-guard bypass 30
```

Or `GUARD_ENABLED=false` in `guard.conf` to disable blocking entirely while
keeping notifications. Applies immediately.

## Notifications

See [notifications.md](notifications.md).

## My prompt disappeared

Blocked prompts are appended to `~/.claude/usage-guard/blocked-prompts.log` with
a timestamp and directory.

## Remove it

```bash
./install.sh --uninstall
```

Removes hooks (restoring `settings.json`, leaving your other hooks intact), the
watcher and the binary. Config and logs stay in `~/.claude/usage-guard/`.
