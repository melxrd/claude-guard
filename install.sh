#!/usr/bin/env bash
#
# claude-guard installer.
#
#   ./install.sh              install
#   ./install.sh --dry-run    show what would happen, change nothing
#   ./install.sh --uninstall  remove hooks, timer and binary (config and logs stay)
#
# Installs to ~/.claude/usage-guard, registers three Claude Code hooks in
# ~/.claude/settings.json (non-destructively, with a backup), and schedules a
# watcher every 90 seconds via launchd (macOS) or a systemd user timer (Linux).

set -uo pipefail

# Works two ways: from a clone, or piped straight from curl. When the sibling
# files are missing we fetch them from the repo instead.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SRC=""
REPO="${CLAUDE_GUARD_REPO:-melxrd/claude-guard}"
REF="${CLAUDE_GUARD_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$REF"
DEST="$HOME/.claude/usage-guard"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
BIN_DIR="$HOME/.local/bin"
LABEL="com.claudeguard.watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SYSTEMD_DIR="$HOME/.config/systemd/user"
DRY=0
MODE=install

for a in "$@"; do
  case "$a" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY=1 ;;
    -h|--help)   cat <<'USAGE'
claude-guard installer

  install.sh              install
  install.sh --dry-run    show what would happen, change nothing
  install.sh --uninstall  remove hooks, timer and binary (config and logs stay)

Environment:
  CLAUDE_GUARD_REPO   owner/name to fetch from when run via curl (default melxrd/claude-guard)
  CLAUDE_GUARD_REF    branch or tag to fetch (default main)
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
# Removes any previous claude-guard entries and re-adds the current three,
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
    return any('claude-guard' in str(h.get('command', ''))
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

# set_conf <key> <value> — rewrite the key in guard.conf, or append it.
set_conf() {
  "$PY" - "$DEST/guard.conf" "$1" "$2" <<'PYSET'
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
    <string>$DEST/claude-guard</string>
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
  cat >"$SYSTEMD_DIR/claude-guard.service" <<EOF
[Unit]
Description=claude-guard usage watcher

[Service]
Type=oneshot
# Without this, systemd kills the whole cgroup when watch exits — including any
# session auto-resume just started in the background.
KillMode=process
ExecStart=/bin/bash $DEST/claude-guard watch
EOF
  cat >"$SYSTEMD_DIR/claude-guard.timer" <<EOF
[Unit]
Description=Run claude-guard watcher every 90 seconds

[Timer]
OnBootSec=1min
OnUnitActiveSec=90s
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload 2>/dev/null
  systemctl --user enable --now claude-guard.timer 2>/dev/null
}

remove_timer() {
  if [ "$OS" = macos ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
    launchctl unload "$PLIST" >/dev/null 2>&1
    rm -f "$PLIST"
  else
    systemctl --user disable --now claude-guard.timer >/dev/null 2>&1
    rm -f "$SYSTEMD_DIR/claude-guard.timer" "$SYSTEMD_DIR/claude-guard.service"
    systemctl --user daemon-reload >/dev/null 2>&1
  fi
  return 0
}

# ============================================================== uninstall ====
if [ "$MODE" = uninstall ]; then
  echo ""; echo "Uninstalling claude-guard"; echo ""
  run remove_timer && ok "watcher removed"
  if [ "$DRY" = 1 ]; then say "[dry-run] would remove hooks from $SETTINGS"
  else patch_settings remove "" >/dev/null && ok "hooks removed from settings.json (backup created)"; fi
  run "rm -f '$BIN_DIR/claude-guard'" && ok "claude-guard command removed"
  run "rm -f '$DEST/claude-guard'"    && ok "script removed"
  echo ""
  say "Config, logs and cache remain in $DEST — delete them yourself if you want:"
  say "  rm -rf $DEST"
  echo ""
  exit 0
fi

# ================================================================ install ====
echo ""; echo "Installing claude-guard on $OS"; echo ""

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

if [ -z "$SRC" ] || [ ! -f "$SRC/bin/claude-guard" ]; then
  say "running from curl — fetching files from $REPO@$REF"
fi

run "mkdir -p '$DEST' '$BIN_DIR'"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would install bin/claude-guard to $DEST/claude-guard"
else
  get_file "bin/claude-guard" "$DEST/claude-guard"
  head -1 "$DEST/claude-guard" | grep -q '^#!' || die "the downloaded script does not look like a shell script"
  chmod +x "$DEST/claude-guard"
fi
ok "script installed in $DEST"

CONF_IS_NEW=0
if [ -f "$DEST/guard.conf" ]; then
  warn "guard.conf already exists: leaving your settings alone"
else
  if [ "$DRY" = 1 ]; then say "[dry-run] would create $DEST/guard.conf"
  else get_file "config/guard.conf.example" "$DEST/guard.conf"; CONF_IS_NEW=1; fi
  ok "config created at $DEST/guard.conf"
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
  say "Auto-resume: when your usage window resets, claude-guard can relaunch the"
  say "sessions it blocked — on its own, while you are away. It spends quota and,"
  say "depending on your permission settings, may edit files. Capped at 3 sessions"
  say "and 12 hours. Details: docs/auto-resume.md"
  if [ -t 0 ]; then
    printf '  Enable auto-resume? [Y/n] '
    read -r ans
    case "$ans" in
      [nN]*) set_conf AUTO_RESUME false; ok "auto-resume off — turn it on in guard.conf whenever you like" ;;
      *)     set_conf AUTO_RESUME true;  ok "auto-resume on" ;;
    esac
  else
    set_conf AUTO_RESUME false
    warn "no terminal to ask, so auto-resume is OFF"
    say "  Read docs/auto-resume.md, then set AUTO_RESUME=true in guard.conf to enable it."
  fi
fi

run "ln -sf '$DEST/claude-guard' '$BIN_DIR/claude-guard'"
ok "claude-guard command in $BIN_DIR"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on your PATH. Add to your shell rc:"
     say "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- hooks
if [ "$DRY" = 1 ]; then
  say "[dry-run] would add PreToolUse / UserPromptSubmit / Stop hooks to $SETTINGS"
else
  res="$(patch_settings add "$DEST/claude-guard")"
  [ "$res" = OK ] || die "$res"
  ok "hooks registered in $SETTINGS (backup .bak-* created)"
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
  "$DEST/claude-guard" selftest | sed 's/^/  /'
  echo ""
  "$DEST/claude-guard" refresh >/dev/null 2>&1
  "$DEST/claude-guard" status | sed 's/^/  /'
fi

cat <<'EOF'

────────────────────────────────────────────────────────────────────
Done. Restart any open Claude Code session — hooks are read at startup.

  claude-guard status        usage, limits and the current decision
  claude-guard bypass 60     disable blocking for 60 minutes
  claude-guard pending       sessions waiting to be resumed
  claude-guard resume        resume them now

AUTO_RESUME is ON by default: when the window resets, claude-guard
relaunches the sessions it blocked, unattended. Read docs/auto-resume.md
before leaving it on, and set AUTO_RESUME=false in guard.conf to disable.

Config: ~/.claude/usage-guard/guard.conf
Logs:   ~/.claude/usage-guard/guard.log
────────────────────────────────────────────────────────────────────

EOF
