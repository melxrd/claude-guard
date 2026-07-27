# Notifications

| Channel | Covers | Part of |
|---|---|---|
| Claude app (Remote Control) | "Claude is asking you something" — prompts, questions | Claude Code |
| ntfy | "work finished", "the guard stopped you" | claude-guard |
| Desktop | everything, while you are at the machine | claude-guard |

Only Claude Code's push can reach you while Claude waits for an answer —
claude-guard cannot see that state. Its "task finished" push is the less
reliable half, which is where ntfy comes in. **Turn both on.**

---

## 1. Claude app — native push

Part of Claude Code, not this project.

1. Install the Claude app, sign in with **the same account and organisation** as
   your terminal, accept notifications.
2. Run `claude`, then `/config`, and enable:
   - `Enable Remote Control for all sessions`
   - `Push when actions required` — permission prompts, questions
   - `Push when Claude decides` — long task finished
3. Restart your sessions.

Check: the app's **Code** tab shows your session with a green dot; the terminal
shows `/rc active` below the input box.

### Settings missing from `/config`

They only appear once Remote Control is available.

```bash
claude doctor
```

If it reports feature-flag evaluation disabled, you have `DO_NOT_TRACK=1` (or
`DISABLE_TELEMETRY`) set. Remote Control is gated behind that service, so the
toggles never render. Narrow fix:

```bash
# ~/.zshrc — keeps DO_NOT_TRACK everywhere except Claude Code
alias claude='env -u DO_NOT_TRACK claude'
```

Interactive shells only. Launching Claude Code from a desktop app bypasses your
shell rc.

### Not bugs

- **No push while you are at the terminal.** Suppressed on purpose. Test by
  walking away.
- **Signed out breaks it silently.** With no registered device, Claude Code
  reports the push as sent and nothing arrives. Sign in, then start a *new*
  Remote Control session — archived ones cannot be revived.
- **Proactive pushes are less reliable than action-required ones.** "Claude
  needs a decision" arrives consistently; "the task finished" often does not.
  That gap is what ntfy covers — do not spend an evening on it.

---

## 2. ntfy — finished work and blocks

[ntfy](https://ntfy.sh) needs no account. A topic is a secret string acting as
an address.

```bash
python3 -c 'import secrets;print("claude-"+secrets.token_hex(8))'
```

Put it in `NTFY_TOPIC` in `~/.claude/usage-guard/guard.conf`, install the app
([iOS](https://apps.apple.com/app/ntfy/id1625396347),
[Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)),
subscribe to the same topic, then:

```bash
claude-guard ntfy-test
```

You get a push when a turn exceeds `NOTIFY_MIN_TURN_SEC`, when the guard blocks,
and at each of `ALERT_LEVELS`.

**The topic is the only secret** — anyone who knows it can read your
notifications. To rotate it, change `guard.conf` and update the app **in the
same sitting**: a mismatch is silent, the sender keeps reporting success.

Blocks go out at `high` priority to cut through Focus modes; routine ones use
`NTFY_PRIORITY` (`default`). Self-hosting: set `NTFY_SERVER`.

Unlike Remote Control, ntfy does not touch Anthropic's feature flags — it works
with `DO_NOT_TRACK` set.

---

## 3. Desktop

First available wins:

1. `terminal-notifier` (macOS, `brew install terminal-notifier`) — best result
2. `osascript` (macOS, built in) — works, but shows as "Script Editor"
3. `notify-send` (Linux, `apt install libnotify-bin`)

```bash
claude-guard notify-test
```

Nothing? The permission belongs to "Script Editor" or "terminal-notifier" in
System Settings → Notifications, not "claude-guard".

Claude Code's own desktop notification only works in Ghostty, Kitty and iTerm2
(iTerm2 also needs *Settings → Profiles → Terminal → Notification Center
Alerts* and *Filter Alerts → Send escape sequence-generated alerts*).
claude-guard's `Stop` hook works in any terminal and adds turn duration, usage
and project name.

---

## Sent but not arriving

Check the server first — it tells you which side is broken:

```bash
curl "https://ntfy.sh/$YOUR_TOPIC/json?poll=1&since=1h"
```

Message listed → the sending side is fine, the phone is the problem. Do not
change any phone setting before running this.

- **The app was in the foreground.** iOS delivers the push to the running app
  instead of drawing a banner. Retest with the app closed from the switcher and
  the phone locked.
- **Messages appear in the app but never as banners.** The app failed to
  register for push and only fetches history when opened. Reinstall it and grant
  notifications *before* subscribing. Checking the notification settings will
  not help — they are already correct.
- **A Focus mode or Scheduled Summary is holding them.** Both produce "in
  Notification Center, never a banner". On macOS also check Focus sharing across
  devices: a Do Not Disturb on your Mac silences your iPhone — which bites
  exactly while you test from the Mac.
