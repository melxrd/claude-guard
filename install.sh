#!/usr/bin/env bash
#
# claude-reserve installer.
#
#   ./install.sh              install
#   ./install.sh --dry-run    show what would happen, change nothing
#   ./install.sh --uninstall  remove hooks, timer and binary (config and logs stay)
#
# Installs to ~/.claude/claude-reserve, registers three Claude Code hooks in
# ~/.claude/settings.json (non-destructively, with a backup), and schedules a
# watcher every 90 seconds via launchd (macOS) or a systemd user timer (Linux).

set -uo pipefail

# Works two ways: from a clone, or piped straight from curl. When the sibling
# files are missing we fetch them from the repo instead.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SRC=""
REPO="${CLAUDE_RESERVE_REPO:-melxrd/claude-reserve}"
REF="${CLAUDE_RESERVE_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$REF"
DEST="$HOME/.claude/claude-reserve"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
BIN_DIR="$HOME/.local/bin"
LABEL="com.claudereserve.watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SYSTEMD_DIR="$HOME/.config/systemd/user"
DRY=0
MODE=install

for a in "$@"; do
  case "$a" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY=1 ;;
    -h|--help)   cat <<'USAGE'
claude-reserve installer

  install.sh              install
  install.sh --dry-run    show what would happen, change nothing
  install.sh --uninstall  remove hooks, timer and binary (config and logs stay)

Environment:
  CLAUDE_RESERVE_REPO   owner/name to fetch from when run via curl (default melxrd/claude-reserve)
  CLAUDE_RESERVE_REF    branch or tag to fetch (default main)
USAGE
                 exit 0 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) echo "unsupported platform: $(uname -s)"; exit 1 ;;
esac

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }
# shellcheck disable=SC2294  # commands are built as strings on purpose
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

PY=""
for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'pass' >/dev/null 2>&1; then PY="$c"; break; fi
done

# ============================================================ settings.json ==
# Removes any previous claude-reserve entries and re-adds the current three,
# leaving every other hook untouched.
patch_settings() {
  local action="$1" target="$2"
  [ -z "$PY" ] && die "python3 is required to edit settings.json"
  "$PY" - "$action" "$target" "$SETTINGS" <<'PYEOF'
import json, os, sys, shutil, time

action, target, path = sys.argv[1], sys.argv[2], sys.argv[3]

data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            txt = f.read().strip()
        data = json.loads(txt) if txt else {}
    except Exception as e:
        print("ERROR: %s is not valid JSON (%s). Fix it and re-run." % (path, e))
        sys.exit(1)
    shutil.copy2(path, path + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
    # keep the five most recent backups, discard the rest
    import glob
    old = sorted(glob.glob(path + '.bak-*'))[:-5]
    for f in old:
        try:
            os.remove(f)
        except OSError:
            pass

hooks = data.setdefault('hooks', {})
EVENTS = {'PreToolUse': 'hook-pretool',
          'UserPromptSubmit': 'hook-prompt',
          'Stop': 'hook-stop'}

def is_ours(entry):
    # 'claude-guard' is the pre-1.1 name: still matched so an upgrade replaces
    # the old hooks instead of leaving two sets registered.
    return any(('claude-reserve' in str(h.get('command', ''))
                or 'claude-guard' in str(h.get('command', '')))
               for h in (entry.get('hooks') or []))

for ev in EVENTS:
    if isinstance(hooks.get(ev), list):
        hooks[ev] = [e for e in hooks[ev]
                     if not (isinstance(e, dict) and is_ours(e))]

if action == 'add':
    for ev, sub in EVENTS.items():
        hooks.setdefault(ev, []).append({
            'hooks': [{'type': 'command',
                       'command': '%s %s' % (target, sub),
                       'timeout': 10}]})

for ev in list(hooks):
    if hooks[ev] == []:
        del hooks[ev]
if not hooks:
    data.pop('hooks', None)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('OK')
PYEOF
}

# set_conf <key> <value> — rewrite the key in reserve.conf, or append it.
set_conf() {
  "$PY" - "$DEST/reserve.conf" "$1" "$2" <<'PYSET'
import re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    s = open(path).read()
except OSError:
    s = ''
line = '%s=%s' % (key, val)
if re.search(r'(?m)^%s=' % re.escape(key), s):
    s = re.sub(r'(?m)^%s=.*$' % re.escape(key), line, s, count=1)
else:
    s = s.rstrip('\n') + '\n' + line + '\n'
open(path, 'w').write(s)
PYSET
}

# ============================================================== statusline ===
# Claude Code allows exactly one statusLine command, so we only ever claim an
# empty slot. If one is already there it stays, and we print how to wrap it.
setup_statusline() {
  "$PY" - "$SETTINGS" "$DEST/claude-reserve" "${1:-set}" <<'PYSL'
import json, os, sys

path, binpath, action = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        txt = open(path).read().strip()
        data = json.loads(txt) if txt else {}
    except Exception:
        print('ERROR'); sys.exit(1)

cur = data.get('statusLine')
cmd = cur.get('command', '') if isinstance(cur, dict) else (cur or '')
ours = 'claude-reserve statusline' in str(cmd) or 'claude-guard statusline' in str(cmd)

if action == 'remove':
    if not ours:
        print('SKIPPED'); sys.exit(0)
    data.pop('statusLine', None)
    result = 'REMOVED'
else:
    want = '%s statusline' % binpath
    if ours:
        data['statusLine'] = {'type': 'command', 'command': want}
        result = 'UPDATED'
    elif cmd:
        print('EXISTS:%s' % cmd); sys.exit(0)
    else:
        data['statusLine'] = {'type': 'command', 'command': want}
        result = 'SET'

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    json.dump(data, f, indent=2); f.write('\n')
print(result)
PYSL
}

# ================================================================= timer =====
install_timer_macos() {
  mkdir -p "$(dirname "$PLIST")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$DEST/claude-reserve</string>
    <string>watch</string>
  </array>
  <key>StartInterval</key><integer>90</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$DEST/watch.err.log</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null
}

install_timer_linux() {
  mkdir -p "$SYSTEMD_DIR"
  cat >"$SYSTEMD_DIR/claude-reserve.service" <<EOF
[Unit]
Description=claude-reserve usage watcher

[Service]
Type=oneshot
# Without this, systemd kills the whole cgroup when watch exits — including any
# session auto-resume just started in the background.
KillMode=process
ExecStart=/bin/bash $DEST/claude-reserve watch
EOF
  cat >"$SYSTEMD_DIR/claude-reserve.timer" <<EOF
[Unit]
Description=Run claude-reserve watcher every 90 seconds

[Timer]
OnBootSec=1min
OnUnitActiveSec=90s
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload 2>/dev/null
  systemctl --user enable --now claude-reserve.timer 2>/dev/null
}

remove_timer() {
  if [ "$OS" = macos ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
    launchctl unload "$PLIST" >/dev/null 2>&1
    rm -f "$PLIST"
  else
    systemctl --user disable --now claude-reserve.timer >/dev/null 2>&1
    rm -f "$SYSTEMD_DIR/claude-reserve.timer" "$SYSTEMD_DIR/claude-reserve.service"
    systemctl --user daemon-reload >/dev/null 2>&1
  fi
  return 0
}

# ============================================================== uninstall ====
if [ "$MODE" = uninstall ]; then
  echo ""; echo "Uninstalling claude-reserve"; echo ""
  run remove_timer && ok "watcher removed"
  if [ "$DRY" = 1 ]; then say "[dry-run] would remove hooks from $SETTINGS"
  else patch_settings remove "" >/dev/null && ok "hooks removed from settings.json (backup created)"; fi
  if [ "$DRY" = 1 ]; then say "[dry-run] would remove our statusLine entry"
  else
    case "$(setup_statusline remove)" in
      REMOVED) ok "status line entry removed" ;;
      SKIPPED) say "  status line belongs to something else, left alone" ;;
    esac
  fi
  run "rm -f '$BIN_DIR/claude-reserve'" && ok "claude-reserve command removed"
  run "rm -f '$DEST/claude-reserve'"    && ok "script removed"
  echo ""
  say "Config, logs and cache remain in $DEST — delete them yourself if you want:"
  say "  rm -rf $DEST"
  echo ""
  exit 0
fi

# =============================================================== migrate =====
# Pre-1.1 the project was called claude-guard. Move the old state across rather
# than leaving people with a stale install and a fresh empty one beside it.
OLD_DEST="$HOME/.claude/usage-guard"
OLD_LABEL="com.claudeguard.watch"
migrate_from_claude_guard() {
  [ -d "$OLD_DEST" ] || return 0
  [ -e "$DEST" ] && return 0

  # stop the old watcher first, whatever platform it was installed on
  launchctl bootout "gui/$(id -u)/$OLD_LABEL" >/dev/null 2>&1
  launchctl unload "$HOME/Library/LaunchAgents/$OLD_LABEL.plist" >/dev/null 2>&1
  rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
  systemctl --user disable --now claude-guard.timer >/dev/null 2>&1
  rm -f "$SYSTEMD_DIR/claude-guard.timer" "$SYSTEMD_DIR/claude-guard.service"
  systemctl --user daemon-reload >/dev/null 2>&1

  mv "$OLD_DEST" "$DEST" || return 1
  [ -f "$DEST/guard.conf" ] && mv "$DEST/guard.conf" "$DEST/reserve.conf"
  [ -f "$DEST/guard.log" ]  && mv "$DEST/guard.log"  "$DEST/reserve.log"
  rm -f "$DEST/claude-guard" "$BIN_DIR/claude-guard"
  return 0
}

if [ "$DRY" != 1 ] && [ -d "$OLD_DEST" ] && [ ! -e "$DEST" ]; then
  if migrate_from_claude_guard; then
    ok "migrated your claude-guard install (settings kept) to $DEST"
  else
    warn "could not migrate $OLD_DEST — install continues with a fresh config"
  fi
elif [ "$DRY" = 1 ] && [ -d "$OLD_DEST" ]; then
  say "[dry-run] would migrate $OLD_DEST to $DEST, keeping your settings"
fi

# ================================================================ install ====
echo ""; echo "Installing claude-reserve on $OS"; echo ""

[ -n "$PY" ] || die "python3 not found (macOS: xcode-select --install)"
ok "python3: $PY"
command -v curl >/dev/null 2>&1 || die "curl not found"

CLAUDE_PATH="$(command -v claude 2>/dev/null || true)"
if [ -n "$CLAUDE_PATH" ]; then ok "claude: $CLAUDE_PATH"
else warn "the 'claude' command is not on PATH — installing anyway"; fi

# --- usage source check
SOURCE_FOUND=""
if curl -fsS --max-time 2 http://127.0.0.1:6736/v1/usage >/dev/null 2>&1; then
  ok "OpenUsage is answering on 127.0.0.1:6736"; SOURCE_FOUND=openusage
fi
if [ -z "$SOURCE_FOUND" ]; then
  if [ "$OS" = macos ] && security find-generic-password -s 'Claude Code-credentials' -w >/dev/null 2>&1; then
    ok "Claude Code credentials found in the keychain (OAuth source available)"; SOURCE_FOUND=oauth
  elif [ -r "$HOME/.claude/.credentials.json" ]; then
    ok "Claude Code credentials found on disk (OAuth source available)"; SOURCE_FOUND=oauth
  fi
fi
if [ -z "$SOURCE_FOUND" ] && command -v ccusage >/dev/null 2>&1; then
  ok "ccusage found (local token estimate available)"; SOURCE_FOUND=ccusage
fi
[ -z "$SOURCE_FOUND" ] && warn "no usage source detected — the guard will fail open until one appears (see docs/data-sources.md)"

if command -v terminal-notifier >/dev/null 2>&1 || [ "$OS" = macos ]; then
  ok "desktop notifications available"
elif command -v notify-send >/dev/null 2>&1; then
  ok "desktop notifications via notify-send"
else
  warn "no desktop notification tool found (Linux: install libnotify-bin)"
fi

# --- files
# get_file <path-in-repo> <destination>
get_file() {
  local rel="$1" dest="$2"
  if [ -n "$SRC" ] && [ -f "$SRC/$rel" ]; then
    cp "$SRC/$rel" "$dest" || return 1
  else
    curl -fsL "$RAW_BASE/$rel" -o "$dest.part" 2>/dev/null || {
      rm -f "$dest.part"
      die "could not download $rel from $RAW_BASE — check the network, or clone the repo and run ./install.sh"
    }
    [ -s "$dest.part" ] || { rm -f "$dest.part"; die "$rel downloaded empty"; }
    mv "$dest.part" "$dest"
  fi
}

if [ -z "$SRC" ] || [ ! -f "$SRC/bin/claude-reserve" ]; then
  say "running from curl — fetching files from $REPO@$REF"
fi

run "mkdir -p '$DEST' '$BIN_DIR'"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would install bin/claude-reserve to $DEST/claude-reserve"
else
  get_file "bin/claude-reserve" "$DEST/claude-reserve"
  head -1 "$DEST/claude-reserve" | grep -q '^#!' || die "the downloaded script does not look like a shell script"
  chmod +x "$DEST/claude-reserve"
fi
ok "script installed in $DEST"

CONF_IS_NEW=0
if [ -f "$DEST/reserve.conf" ]; then
  warn "reserve.conf already exists: leaving your settings alone"
  # Upgrades keep whatever was configured before, which is right — but a setting
  # that acts unattended should never be inherited silently.
  if grep -q '^AUTO_RESUME=true' "$DEST/reserve.conf" 2>/dev/null; then
    say ""
    warn "auto-resume is ON in your existing config"
    say "  When your window resets, blocked sessions relaunch on their own."
    say "  Keeping it is fine — this is only so you know. To turn it off:"
    say "    set AUTO_RESUME=false in $DEST/reserve.conf"
    say ""
  fi
else
  if [ "$DRY" = 1 ]; then say "[dry-run] would create $DEST/reserve.conf"
  else get_file "config/reserve.conf.example" "$DEST/reserve.conf"; CONF_IS_NEW=1; fi
  ok "config created at $DEST/reserve.conf"
fi

# The watcher runs from launchd/systemd, which do not load your shell profile.
# Recording the absolute path here is what stops auto-resume failing silently
# for anyone whose claude lives under nvm, npm or a version manager.
if [ "$DRY" != 1 ] && [ -n "$CLAUDE_PATH" ]; then
  set_conf CLAUDE_BIN "$CLAUDE_PATH"
  ok "CLAUDE_BIN set to $CLAUDE_PATH"
fi

# Auto-resume is the one setting that acts while nobody is watching, so it is a
# question when there is someone to answer it — and off when there is not.
# Piping through curl leaves no terminal, and silence is not consent.
if [ "$DRY" != 1 ] && [ "$CONF_IS_NEW" = 1 ]; then
  echo ""
  say "Auto-resume: when your usage window resets, claude-reserve can relaunch the"
  say "sessions it blocked — on its own, while you are away. It spends quota and,"
  say "depending on your permission settings, may edit files. Capped at 3 sessions"
  say "and 12 hours. Details: docs/auto-resume.md"
  if [ -t 0 ]; then
    printf '  Enable auto-resume? [Y/n] '
    read -r ans
    case "$ans" in
      [nN]*) set_conf AUTO_RESUME false; ok "auto-resume off — turn it on in reserve.conf whenever you like" ;;
      *)     set_conf AUTO_RESUME true;  ok "auto-resume on" ;;
    esac
  else
    set_conf AUTO_RESUME false
    warn "no terminal to ask, so auto-resume is OFF"
    say "  Read docs/auto-resume.md, then set AUTO_RESUME=true in reserve.conf to enable it."
  fi
fi

run "ln -sf '$DEST/claude-reserve' '$BIN_DIR/claude-reserve'"
ok "claude-reserve command in $BIN_DIR"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on your PATH. Add to your shell rc:"
     say "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- hooks
if [ "$DRY" = 1 ]; then
  say "[dry-run] would add PreToolUse / UserPromptSubmit / Stop hooks to $SETTINGS"
else
  res="$(patch_settings add "$DEST/claude-reserve")"
  [ "$res" = OK ] || die "$res"
  ok "hooks registered in $SETTINGS (backup .bak-* created)"
fi

# --- status line: the cheapest and most accurate usage source
if [ "$DRY" = 1 ]; then
  say "[dry-run] would register the status line if the slot is free"
else
  SL_RES="$(setup_statusline set)"
  case "$SL_RES" in
    SET|UPDATED)
      ok "status line registered — usage comes straight from Claude Code, no API call" ;;
    EXISTS:*)
      warn "you already have a status line: leaving it alone"
      say "  To capture usage as well, make your statusLine command:"
      say "    $DEST/claude-reserve statusline --exec '${SL_RES#EXISTS:}'" ;;
    *)
      warn "could not configure the status line (the other sources still work)" ;;
  esac
fi

# --- watcher
run remove_timer
if [ "$DRY" = 1 ]; then
  say "[dry-run] would install and start the watcher"
else
  if [ "$OS" = macos ]; then install_timer_macos; else install_timer_linux; fi
  ok "watcher scheduled every 90 seconds"
fi

# --- verify
if [ "$DRY" != 1 ]; then
  echo ""; echo "Verification"; echo ""
  "$DEST/claude-reserve" selftest | sed 's/^/  /'
  echo ""
  "$DEST/claude-reserve" refresh >/dev/null 2>&1
  "$DEST/claude-reserve" status | sed 's/^/  /'
fi

AR_NOW="$(grep -m1 '^AUTO_RESUME=' "$DEST/reserve.conf" 2>/dev/null | cut -d= -f2)"
case "$AR_NOW" in
  true)  AR_LINE="Auto-resume is ON: when the window resets, blocked sessions relaunch
on their own. Set AUTO_RESUME=false in reserve.conf to stop that." ;;
  false) AR_LINE="Auto-resume is OFF: you will be notified when the window resets, and
resume with 'claude-reserve resume --run'. See docs/auto-resume.md to enable it." ;;
  *)     AR_LINE="Auto-resume: check AUTO_RESUME in reserve.conf, and read docs/auto-resume.md." ;;
esac

cat <<EOF

────────────────────────────────────────────────────────────────────
Done. Restart any open Claude Code session — hooks are read at startup.

  claude-reserve status        usage, limits and the current decision
  claude-reserve bypass 60     disable blocking for 60 minutes
  claude-reserve pending       sessions waiting to be resumed
  claude-reserve resume        resume them now

$AR_LINE

Config: $DEST/reserve.conf
Logs:   $DEST/reserve.log
────────────────────────────────────────────────────────────────────

EOF
