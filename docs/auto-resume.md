# Auto-resume

Blocking alone just moves the problem. Auto-resume restarts the interrupted work
once the usage window rolls over.

**The installer asks whether to enable it.** Press Enter to accept, `n` to
decline. When the installer is piped through `curl` there is no terminal to ask
on, so it stays off and you enable it yourself after reading this page.

## What happens

1. A session gets blocked. claude-reserve writes its working directory, time and
   reason to `~/.claude/claude-reserve/pending/<session-id>`.
2. The watcher notes the window's reset timestamp every 90 seconds.
3. When that timestamp changes, records older than `AUTO_RESUME_MAX_AGE_H` are
   dropped and the rest are run:

   ```bash
   cd <recorded directory> && claude --continue $AUTO_RESUME_ARGS -p "$AUTO_RESUME_PROMPT"
   ```

4. Output goes to `resume.log`; the record is deleted so nothing runs twice.

`claude --continue` picks up the most recent conversation in that directory, so
the agent keeps its context.

## The risks

**An agent runs unsupervised.** That is the point and the risk. It spends quota
and, depending on your permission settings, may edit files or run commands. If
that should not happen at 3am, set `AUTO_RESUME=false`.

**"Continue where you left off" is vague.** Fine for a long refactor, less so
for ambiguous work. Set `AUTO_RESUME_PROMPT` to something specific if your work
is repetitive.

**Headless runs stall on permission prompts.** `claude -p` is non-interactive:
without pre-granted permissions it waits forever. If your work edits files:

```bash
AUTO_RESUME_ARGS="--permission-mode acceptEdits"
```

Know what that grants before setting it.

**It resumes the directory, not your terminal.** The unattended relaunch is a
new headless process; your original blocked session is still open. Close it or
continue it yourself — two processes in one directory can conflict.

## Headless or in front of you

Two different moments, two behaviours:

| | Command | What you see |
|---|---|---|
| The watcher, at window reset | `resume --run` | nothing — a headless agent works, output lands in `resume.log` |
| You, clicking or typing | `resume --run --terminal` | a terminal window opens with an interactive `claude --continue` |

The headless form is right when nobody is at the keyboard, which is exactly when
the watcher fires. It is also why a click that "did nothing" usually did
everything — check `resume.log` before believing otherwise.

`--terminal` drops `-p` and `AUTO_RESUME_ARGS`: you are there, so the session
asks you rather than pre-granting itself permissions. The menu bar item uses it.

On macOS the window is opened with AppleScript, so the first use raises a
"wants to control Terminal" prompt. Refuse it and claude-reserve falls back to
opening the folder and telling you the command to type. Point
`RESUME_TERMINAL_APP` at another app, or override the whole thing:

```bash
RESUME_TERMINAL_CMD="tmux new-window"     # receives the command as last argument
```

If no terminal can be opened at all, the session **stays in the queue** — an
unopened resume that silently disappears is how work gets lost.

## Watching a resume, and stopping one

```bash
ps -eo pid,etime,command | grep "[c]laude"
tail -f ~/.claude/claude-reserve/resume.log
pkill -f "claude --continue -p"
```

The `-p` is the tell: headless resumes carry it, sessions you opened in a window
never do — so that `pkill` cannot touch your own work.

## The manual alternative

```bash
AUTO_RESUME=false
RESUME_NOTIFY=true
```

You get notified when the window resets and work is waiting, then:

```bash
claude-reserve pending                  # what is queued
claude-reserve resume                   # print the commands, run nothing
claude-reserve resume --run             # resume headlessly
claude-reserve resume --run --terminal  # resume in a terminal window
```

`resume` without `--run` prints commands so you can read them first. If the
guard is still blocking it refuses and explains why.

## Settings

| Setting | Default | Effect |
|---|---|---|
| `AUTO_RESUME` | `true` | Relaunch automatically on window reset |
| `RESUME_NOTIFY` | `true` | Notify on reset even when auto-resume is off |
| `AUTO_RESUME_MAX` | `3` | Cap on simultaneous relaunches |
| `AUTO_RESUME_MAX_AGE_H` | `12` | Drop records older than this |
| `AUTO_RESUME_PROMPT` | `Continue where you left off.` | Prompt sent on resume |
| `AUTO_RESUME_ARGS` | `""` | Extra flags, e.g. `--permission-mode acceptEdits` |
| `CLAUDE_BIN` | `claude` | Path to the Claude Code binary |
| `RESUME_TERMINAL_APP` | `Terminal` | macOS app used by `--terminal` |
| `RESUME_TERMINAL_CMD` | `""` | Overrides `--terminal` entirely; gets the command as its last argument |

`AUTO_RESUME_MAX` stops a day of blocked sessions becoming a dozen agents
starting at once.

`CLAUDE_BIN` matters because launchd and systemd do not load your shell profile.
The installer records the absolute path it finds at install time; if you later
switch node version manager or reinstall Claude Code, update it. If resumes
silently do nothing, check `resume.log` first.

On Linux the watcher runs as a `Type=oneshot` systemd unit, which by default
kills its whole control group when it exits — taking the resumed session with
it. The unit therefore sets `KillMode=process`, and resumes are launched with
`setsid` where available.

## Verifying without waiting

`tests/run-tests.sh` section 10 covers this end to end with a fake usage server
and a stub `claude`. Against your real setup: lower `SESSION_THRESHOLD` until
blocked, confirm `claude-reserve pending` lists the directory, restore the
threshold, then `claude-reserve resume` to see the command it would run.
