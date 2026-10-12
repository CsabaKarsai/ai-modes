#!/usr/bin/env bash
# Set the AI-usage state (phase:mode) for the current Claude Code session.
# Usage: mode-set.sh <plan|implement>:<solve|pair|study>
# Called by mode-banner.sh when the user types /solve, /pair, /study or /phase; the guard denies
# the agent running it. Any other caller is logged as source "direct" and reverted.
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
SESSIONS="$ROOT/sessions"
mkdir -p "$SESSIONS"

NEW="${1:-}"
case "$NEW" in
  plan:solve|plan:pair|plan:study|implement:solve|implement:pair|implement:study) ;;
  *) echo "usage: mode-set.sh <plan|implement>:<solve|pair|study>" >&2; exit 1 ;;
esac

SID="${CLAUDE_CODE_SESSION_ID:-nosession}"
F="$SESSIONS/$SID"

# plan:pair is the default: absence of a state file means plan:pair. A legacy mode-only file is plan:<mode>.
PREV="plan:pair"
[ -s "$F" ] && PREV="$(cat "$F")"
case "$PREV" in *:*) ;; *) PREV="plan:$PREV" ;; esac

# Column 5 records who switched: "user" only when the prompt hook saw the user type the command.
SOURCE="${AI_MODE_SOURCE:-direct}"
printf '%s' "$NEW" > "$F"
printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SID" "$PREV" "$NEW" "$SOURCE" >> "$ROOT/events.tsv"

# Keep the session directory from growing forever.
find "$SESSIONS" -type f -mtime +30 -delete 2>/dev/null

# An override you cannot see is the same as no friction: surface the running count.
# Counted on the mode half; legacy rows hold the bare mode.
if [ "${PREV#*:}" = "pair" ] && [ "${NEW#*:}" = "solve" ]; then
  N=$(awk -F'\t' 'function m(s){sub(/^.*:/,"",s); return s} m($3)=="pair" && m($4)=="solve" && (NF==4 || $5=="user")' "$ROOT/events.tsv" 2>/dev/null | wc -l | tr -d ' ')
  echo "mode: $PREV -> $NEW   (override #$N)  — solve now governs; earlier mode instructions in this session no longer apply."
else
  echo "mode: $PREV -> $NEW  — $NEW now governs; earlier mode instructions in this session no longer apply."
fi
