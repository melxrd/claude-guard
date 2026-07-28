#!/usr/bin/env bash
#
# claude-reserve in the macOS menu bar.
#
# Works with SwiftBar (https://swiftbar.app) or xbar (https://xbarapp.com) —
# they share a plugin format. Copy this file into the plugin folder, keeping the
# ".30s." in the name: that is the refresh interval.
#
#   cp claude-reserve.30s.sh ~/Library/Application\ Support/SwiftBar/
#   chmod +x ~/Library/Application\ Support/SwiftBar/claude-reserve.30s.sh
#
# Shows the 5-hour window percentage, and turns red with a slash when the guard
# is blocking. The dropdown carries both windows, the countdowns, and the two
# actions you actually want at that moment: bypass and refresh.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
BIN="$(command -v claude-reserve || echo "$HOME/.claude/claude-reserve/claude-reserve")"
STATE="${CLAUDE_RESERVE_STATE_DIR:-$HOME/.claude/claude-reserve}"

if [ ! -x "$BIN" ]; then
  echo "CR ?"
  echo "---"
  echo "claude-reserve is not installed | color=red"
  echo "Install it | href=https://github.com/melxrd/claude-reserve"
  exit 0
fi

SESSION_PCT=-1; WEEKLY_PCT=-1; SESSION_RESET_EPOCH=0; WEEKLY_RESET_EPOCH=0
FETCHED_EPOCH=0; SOURCE=none; PLAN=""
# shellcheck disable=SC1090
[ -r "$STATE/usage.env" ] && . "$STATE/usage.env"

DECISION="$("$BIN" decision 2>/dev/null)"
STATE_WORD="${DECISION%% *}"
REASON="${DECISION#* }"

mins() { # epoch -> "1h 36m" / "44m" / "-"
  [ "${1:-0}" -le 0 ] 2>/dev/null && { echo "-"; return; }
  local m=$(( ($1 - $(date +%s)) / 60 ))
  [ "$m" -lt 0 ] && m=0
  if [ "$m" -ge 60 ]; then echo "$((m / 60))h $((m % 60))m"; else echo "${m}m"; fi
}

# ------------------------------------------------------------- menu bar ----
if [ "${SESSION_PCT%.*}" -ge 0 ] 2>/dev/null; then
  # awk with LC_ALL=C, not printf: bash printf follows the locale, so on a
  # comma-decimal system "25.0" is rejected as an invalid number.
  LABEL="$(LC_ALL=C awk -v p="$SESSION_PCT" 'BEGIN{printf "%.0f%%", p}')"
else
  LABEL="?"
fi

case "$DECISION" in
  *bypass*) echo "CR $LABEL | color=gray sfimage=gauge.medium.badge.minus"; SKIP_BAR=1 ;;
esac
if [ "${SKIP_BAR:-0}" = 1 ]; then
  :
elif [ "$STATE_WORD" = BLOCK ]; then
  echo "CR $LABEL | color=red sfimage=exclamationmark.octagon.fill"
elif LC_ALL=C awk -v a="$SESSION_PCT" 'BEGIN{exit !(a+0 >= 75)}' 2>/dev/null; then
  echo "CR $LABEL | color=orange sfimage=gauge.high"
else
  echo "CR $LABEL | sfimage=gauge.medium"
fi

# ------------------------------------------------------------- dropdown ----
echo "---"

case "$DECISION" in
  BLOCK*)         echo "Blocked — reserve protected | color=red"
                  echo "$REASON | length=70 color=red" ;;
  *bypass*)       echo "Bypass active — not guarding | color=orange"
                  echo "$REASON | length=70 color=orange" ;;
  *fail-open*|*"never collected"*)
                  echo "No usage data — not guarding | color=orange"
                  echo "$REASON | length=70 color=gray" ;;
  *)              echo "Guarding | color=green" ;;
esac
echo "---"

if [ "${SESSION_PCT%.*}" -ge 0 ] 2>/dev/null; then
  echo "5-hour window: ${SESSION_PCT}% | font=Menlo"
  echo "resets in $(mins "$SESSION_RESET_EPOCH") | font=Menlo size=11 color=gray"
else
  echo "5-hour window: no data | color=gray"
fi
if [ "${WEEKLY_PCT%.*}" -ge 0 ] 2>/dev/null; then
  echo "Weekly: ${WEEKLY_PCT}% | font=Menlo"
  echo "resets in $(mins "$WEEKLY_RESET_EPOCH") | font=Menlo size=11 color=gray"
fi

PENDING=0
for f in "$STATE"/pending/*; do [ -e "$f" ] && PENDING=$((PENDING + 1)); done
[ "$PENDING" -gt 0 ] && echo "$PENDING session(s) waiting to resume | color=orange"

echo "---"
AGE="-"
[ "${FETCHED_EPOCH:-0}" -gt 0 ] 2>/dev/null && AGE="$(( $(date +%s) - FETCHED_EPOCH ))s ago"
echo "source: $SOURCE ($AGE)${PLAN:+ · $PLAN} | size=11 color=gray"

echo "---"
echo "Bypass for 30 min | bash=$BIN param1=bypass param2=30 terminal=false refresh=true"
echo "Clear bypass | bash=$BIN param1=unbypass terminal=false refresh=true"
echo "Resume pending work | bash=$BIN param1=resume param2=--run terminal=false refresh=true"
echo "Refresh now | bash=$BIN param1=refresh terminal=false refresh=true"
