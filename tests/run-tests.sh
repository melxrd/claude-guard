#!/usr/bin/env bash
#
# claude-guard test suite.
#
# Runs the policy selftest plus integration tests against fake servers, so
# nothing here touches the network or your real Claude Code state.
#
#   ./tests/run-tests.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/claude-guard"
TMP="$(mktemp -d)"
export CLAUDE_GUARD_STATE_DIR="$TMP/state"
mkdir -p "$CLAUDE_GUARD_STATE_DIR"

PASS=0; FAIL=0
OU_PID=""; NTFY_PID=""

cleanup() {
  [ -n "$OU_PID" ]   && kill "$OU_PID"   2>/dev/null
  [ -n "$NTFY_PID" ] && kill "$NTFY_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
check()   { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
contains() { # contains <name> <needle> <haystack>
  case "$3" in
    *"$2"*) printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS+1)) ;;
    *) printf '  \033[31mFAIL\033[0m %s\n       expected to contain: %s\n       actual: %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)) ;;
  esac
}

PY=python3
command -v "$PY" >/dev/null 2>&1 || { echo "python3 required"; exit 1; }
PORT_OU=${PORT_OU:-16736}
PORT_NTFY=${PORT_NTFY:-18899}

# ---------------------------------------------------------------- servers ---
cat >"$TMP/fake_openusage.py" <<'PY'
import http.server, json, os, sys, time
PCT   = float(os.environ.get('FAKE_PCT', '42'))
MIN   = int(os.environ.get('FAKE_RESET_MIN', '120'))
WPCT  = float(os.environ.get('FAKE_WEEKLY_PCT', '30'))
PORT  = int(os.environ.get('PORT_OU', '16736'))
reset = int(time.time()) + MIN * 60
body = json.dumps([
    {"providerId": "codex", "displayName": "Codex", "lines": []},
    {"providerId": "claude", "displayName": "Claude", "plan": "Max", "lines": [
        {"label": "Session", "used": PCT, "limit": 100.0,
         "format": {"kind": "percent"}, "periodDurationMs": 18000000,
         "resetsAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(reset))},
        {"label": "Weekly", "used": WPCT, "limit": 100.0,
         "format": {"kind": "percent"}, "periodDurationMs": 604800000,
         "resetsAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(reset + 500000))}]}]).encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        s.send_response(200); s.send_header('Content-Type', 'application/json')
        s.send_header('Content-Length', str(len(body))); s.end_headers(); s.wfile.write(body)
    def log_message(s, *a): pass
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PY

cat >"$TMP/fake_ntfy.py" <<'PY'
import http.server, os
LOG = os.environ['NTFY_LOG']
PORT = int(os.environ.get('PORT_NTFY', '18899'))
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):          # readiness probe
        s.send_response(200); s.send_header('Content-Length', '2'); s.end_headers(); s.wfile.write(b'ok')
    def do_POST(s):
        n = int(s.headers.get('Content-Length', 0))
        body = s.rfile.read(n).decode()
        with open(LOG, 'a') as f:
            f.write("%s|%s|%s|%s\n" % (s.path.lstrip('/'), s.headers.get('Priority'),
                                       s.headers.get('Title'), body))
        s.send_response(200); s.send_header('Content-Length', '2'); s.end_headers(); s.wfile.write(b'ok')
    def log_message(s, *a): pass
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PY

# Wait until a server actually answers. A fixed sleep is not enough on cold
# CI runners, where a python interpreter can take over a second to start.
wait_for() { # wait_for <url> <label>
  local n=0
  while [ "$n" -lt 150 ]; do
    curl -fsS --max-time 1 "$1" >/dev/null 2>&1 && return 0
    n=$((n + 1))
    sleep 0.1
  done
  printf '  \033[31mFATAL\033[0m %s never came up at %s\n' "$2" "$1" >&2
  exit 1
}

now_ms() { "$PY" -c 'import time;print(int(time.time()*1000))'; }

start_openusage() { # start_openusage <pct> <reset_min> [weekly_pct]
  [ -n "$OU_PID" ] && { kill "$OU_PID" 2>/dev/null; wait "$OU_PID" 2>/dev/null; OU_PID=""; sleep 0.2; }
  FAKE_PCT="$1" FAKE_RESET_MIN="$2" FAKE_WEEKLY_PCT="${3:-30}" PORT_OU="$PORT_OU" \
    "$PY" "$TMP/fake_openusage.py" & OU_PID=$!
  wait_for "http://127.0.0.1:$PORT_OU/v1/usage" "fake OpenUsage"
}

NTFY_LOG="$TMP/ntfy.log"
NTFY_LOG="$NTFY_LOG" PORT_NTFY="$PORT_NTFY" "$PY" "$TMP/fake_ntfy.py" & NTFY_PID=$!
wait_for "http://127.0.0.1:$PORT_NTFY/ready" "fake ntfy"
: >"$NTFY_LOG"

# fake `claude` binary: records that a resume happened
cat >"$TMP/fake-claude" <<EOF
#!/usr/bin/env bash
echo "RESUMED cwd=\$PWD args=\$*" >> "$TMP/resumed.log"
EOF
chmod +x "$TMP/fake-claude"

cat >"$CLAUDE_GUARD_STATE_DIR/guard.conf" <<EOF
GUARD_ENABLED=true
SESSION_THRESHOLD=90
SESSION_GRACE_MIN=30
WEEKLY_THRESHOLD=95
WEEKLY_GRACE_MIN=120
FAIL_MODE=open
NOTIFY_ON_STOP=true
NOTIFY_MIN_TURN_SEC=60
NOTIFY_SOUND=""
NOTIFY_DEDUPE_SEC=0
ALERT_LEVELS="75 90 95"
NTFY_TOPIC="testtopic"
NTFY_SERVER=http://127.0.0.1:$PORT_NTFY
AUTO_RESUME=true
AUTO_RESUME_MAX=3
AUTO_RESUME_MAX_AGE_H=12
CLAUDE_BIN="$TMP/fake-claude"
OPENUSAGE_BASE=http://127.0.0.1:$PORT_OU
USE_OAUTH_FALLBACK=false
USE_CCUSAGE=false
CACHE_TTL=0
FAIL_BACKOFF=0
EOF

g() { "$GUARD" "$@"; }

# ================================================================== tests ====
section "1. policy selftest"
if out="$(g selftest)"; then
  printf '%s\n' "$out" | sed 's/^/  /'
  PASS=$((PASS+1))
else
  printf '%s\n' "$out" | sed 's/^/  /'; FAIL=$((FAIL+1))
fi

section "2. shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$GUARD" "$ROOT/install.sh" "$0"; then
    check "no warnings" 0 0
  else
    check "no warnings" 0 1
  fi
else
  echo "  (shellcheck not installed, skipped)"
fi

section "3. reading usage from a source"
start_openusage 42 120
g refresh >/dev/null 2>&1
out="$(g status)"
contains "percentage parsed"        "5h window      : 42.0%" "$out"
contains "plan parsed"              "Max"                 "$out"
contains "weekly parsed"            "weekly         : 30.0%" "$out"
contains "decision is allow"        "decision now   : ALLOW" "$out"

section "4. blocking behaviour"
start_openusage 94 120
g refresh >/dev/null 2>&1
out="$(echo '{"session_id":"s1"}' | g hook-pretool)"
contains "PreToolUse denies"        '"permissionDecision":"deny"' "$out"
contains "PreToolUse halts turn"    '"continue":false'            "$out"
contains "reason is explained"      '5h window at 94.0%'          "$out"

out="$(echo '{"session_id":"s1","prompt":"hi"}' | g hook-prompt)"
contains "UserPromptSubmit halts"   '"continue":false'            "$out"
if [ -s "$CLAUDE_GUARD_STATE_DIR/blocked-prompts.log" ]; then saved=yes; else saved=no; fi
check    "prompt was saved"         "yes" "$saved"

section "5. grace window"
start_openusage 94 20
g refresh >/dev/null 2>&1
out="$(echo '{"session_id":"s2"}' | g hook-pretool)"
check "no block when reset is near" "" "$out"

section "6. bypass"
start_openusage 94 120
g refresh >/dev/null 2>&1
g bypass 10 >/dev/null
out="$(echo '{"session_id":"s3"}' | g hook-pretool)"
check "bypass lets tools through" "" "$out"
g unbypass >/dev/null
out="$(echo '{"session_id":"s3"}' | g hook-pretool)"
contains "unbypass restores the block" '"continue":false' "$out"

section "7. pending sessions"
out="$(g pending)"
contains "blocked session recorded" "session(s) blocked and resumable" "$out"

section "8. ntfy push"
: >"$NTFY_LOG"
g ntfy-test >/dev/null 2>&1
contains "test push sent" "testtopic|" "$(cat "$NTFY_LOG")"
: >"$NTFY_LOG"
echo '{"session_id":"s4"}' | g hook-pretool >/dev/null
contains "block push is high priority" "|high|Claude Code stopped" "$(cat "$NTFY_LOG")"

section "9. turn-finished notification"
: >"$NTFY_LOG"
start_openusage 42 120
g refresh >/dev/null 2>&1
mkdir -p "$CLAUDE_GUARD_STATE_DIR/turns"
echo "$(( $(date +%s) - 300 ))" > "$CLAUDE_GUARD_STATE_DIR/turns/s5"
echo '{"session_id":"s5"}' | g hook-stop >/dev/null
contains "long turn notifies" "Claude Code finished" "$(cat "$NTFY_LOG")"
: >"$NTFY_LOG"
date +%s > "$CLAUDE_GUARD_STATE_DIR/turns/s6"
echo '{"session_id":"s6"}' | g hook-stop >/dev/null
check "short turn stays quiet" "" "$(cat "$NTFY_LOG")"

section "10. window reset triggers auto-resume"
: >"$TMP/resumed.log"; : >"$NTFY_LOG"
rm -f "$CLAUDE_GUARD_STATE_DIR"/pending/* "$CLAUDE_GUARD_STATE_DIR/alert-state"
# get blocked, which records a pending session
start_openusage 94 120
g refresh >/dev/null 2>&1
( cd "$TMP" && echo '{"session_id":"s7"}' | "$GUARD" hook-pretool >/dev/null )
check "pending recorded" 1 "$(ls "$CLAUDE_GUARD_STATE_DIR/pending" | wc -l | tr -d ' ')"
g watch                      # first tick: learn the current window
# the window rolls over: usage drops, reset time changes
start_openusage 3 300
g watch                      # second tick: detect rollover and resume
sleep 1
contains "session was resumed" "RESUMED cwd=$TMP" "$(cat "$TMP/resumed.log" 2>/dev/null)"
check "pending queue drained" 0 "$(ls "$CLAUDE_GUARD_STATE_DIR/pending" | wc -l | tr -d ' ')"

section "11. degrading gracefully"
[ -n "$OU_PID" ] && { kill "$OU_PID" 2>/dev/null; OU_PID=""; }
sleep 0.3
rm -f "$CLAUDE_GUARD_STATE_DIR/usage.env" "$CLAUDE_GUARD_STATE_DIR/.refresh-failed"
start=$(now_ms)
out="$(echo '{"session_id":"s8"}' | g hook-pretool)"
elapsed=$(( $(now_ms) - start ))
check "no data means no block" "" "$out"
if [ "$elapsed" -lt 4000 ]; then
  printf '  \033[32mok\033[0m   hook stays fast without a source (%sms)\n' "$elapsed"; PASS=$((PASS+1))
else
  printf '  \033[31mFAIL\033[0m hook too slow without a source (%sms)\n' "$elapsed"; FAIL=$((FAIL+1))
fi
if [ -d "$CLAUDE_GUARD_STATE_DIR/refresh.lock" ]; then lock=present; else lock=absent; fi
check "no stale lock left behind" "absent" "$lock"

# ================================================================ summary ====
printf '\n\033[1m%s passed, %s failed\033[0m\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
