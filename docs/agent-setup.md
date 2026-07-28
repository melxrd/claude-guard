# Setting up claude-reserve for someone else

*Written for an AI assistant doing the setup. You do not need to read the
source: run the commands, read the output, say the "**Say:**" lines.*

*Setting this up for someone? Follow this — you do not need to read the source.
Run the commands, read the output, say the "**Say:**" lines.*

**Goal:** installed, reading real usage, thresholds matching how they work, and
the user knows the one command that unblocks them.

## 1. Install

```bash
curl -fsSL https://raw.githubusercontent.com/melxrd/claude-reserve/main/install.sh | bash
```

`✓` fine, `!` warning, `✗` stop. The only likely `✗` is a missing `python3`
(macOS: `xcode-select --install`). If it warns about `PATH`, add
`export PATH="$HOME/.local/bin:$PATH"` and open a new shell.

## 2. Check it sees real usage

```bash
claude-reserve status
```

The `data source` line must not be `none`. If it is, the guard is installed but
inert — fix it before saying the user is protected:

- OpenUsage installed → open it, then `claude-reserve refresh`.
- Otherwise the OAuth source should work: `claude-reserve refresh`, then
  `tail -5 ~/.claude/claude-reserve/reserve.log`. **On macOS the first read may raise
  a keychain prompt — warn them before it appears.**
- Log says `token rejected` → have them run any Claude Code command once, retry.

> **Say:** "It's reading your real usage from *<source>*. You're at *<N>%* of the
> 5-hour window, *<M>%* of the weekly one."

## 3. Set thresholds to how they work

Ask: **"When you run out, what does it cost you?"** Losing a morning → 90% is
fine. Locked out when a client calls → 80%.

Then check `status`: if the weekly percentage runs far ahead of the 5-hour one
(common on smaller plans), the weekly limit is their real constraint:

```bash
sed -i'' -e 's/^WEEKLY_THRESHOLD=.*/WEEKLY_THRESHOLD=85/' ~/.claude/claude-reserve/reserve.conf
```

macOS needs `sed -i '' -e ...` — space after `-i`. Verify with `status`.

## 4. Decide about auto-resume

The installer asks about this. If you piped it through `curl` there was no
terminal to answer on, so it is off — check and decide with the user:

```bash
grep '^AUTO_RESUME=' ~/.claude/claude-reserve/reserve.conf
```

> **Say:** "When your window resets, claude-reserve can restart the work it
> interrupted by itself, while you're away — capped at 3 sessions, forgetting
> anything older than 12 hours. Right now it's *<on/off>*. Keep it that way?"

Off:

```bash
sed -i'' -e 's/^AUTO_RESUME=.*/AUTO_RESUME=false/' ~/.claude/claude-reserve/reserve.conf
```

On, and their work edits files: tell them a headless resume stalls on permission
prompts. Do **not** propose `AUTO_RESUME_ARGS="--permission-mode acceptEdits"`
as a fix on your own — that combination is an unattended agent with widened
write permissions. Describe the stall, let them ask for the trade, and only then
set it.

## 5. Notifications

```bash
claude-reserve notify-test
```

If nothing appears on macOS, the permission belongs to "Script Editor" or
"terminal-notifier" in System Settings → Notifications — say so, they will look
for "claude-reserve".

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
# put it in NTFY_TOPIC in ~/.claude/claude-reserve/reserve.conf
claude-reserve ntfy-test
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

## 6. Menu bar (macOS, optional)

Only if they want usage visible outside the terminal. It is a plugin for
[SwiftBar](https://swiftbar.app) or xbar, not an app of ours:

```bash
brew install --cask swiftbar && open -a SwiftBar
```

**SwiftBar asks for a plugin folder on first launch — ask them which one they
picked**, do not assume the default. Then:

```bash
cp extras/swiftbar/claude-reserve.30s.sh <their-folder>/
chmod +x <their-folder>/claude-reserve.30s.sh
```

Verify before touching the menu bar — the plugin just prints text:

```bash
./extras/swiftbar/claude-reserve.30s.sh | head -1
```

`CR 42%` is right. `CR ?` means claude-reserve is not installed or not on PATH.
`CR 0%` means the installed copy predates 1.2.1 — re-run `./install.sh`, since
updating the repo does not update `~/.claude/claude-reserve/`.

See [menu-bar.md](menu-bar.md).

## 7. Prove it, then hand over

```bash
claude-reserve status                      # note the 5h percentage
sed -i'' -e 's/^SESSION_THRESHOLD=.*/SESSION_THRESHOLD=5/' ~/.claude/claude-reserve/reserve.conf
claude-reserve status                      # must now say BLOCK
sed -i'' -e 's/^SESSION_THRESHOLD=.*/SESSION_THRESHOLD=90/' ~/.claude/claude-reserve/reserve.conf
claude-reserve status                      # back to ALLOW
```

> **Say:** "Three things. It stops Claude at *<N>%* and leaves you a reserve. If
> it stops you and you need to work, run `claude-reserve bypass 30` — the block
> message tells you every time. And it can't stop Cowork: if an alert arrives
> while Cowork tasks are running, close those yourself."

## Rules

- **Restart their sessions** after installing, or nothing happens.
- **Never leave a lowered threshold behind.** Restore and verify in the same
  session.
- **Do not edit `bin/claude-reserve`.** Everything tunable is in `reserve.conf`.
- **Do not claim it protects Cowork** or their other machines.
- **If the source is `none`, say so.** Silence leaves them believing they are
  protected when they are not.

---
