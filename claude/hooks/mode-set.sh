#!/usr/bin/env bash
# Set the AI-usage mode for the current Claude Code session.
# Usage: mode-set.sh <solve|pair|study>
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
SESSIONS="$ROOT/sessions"
mkdir -p "$SESSIONS"

NEW="${1:-}"
case "$NEW" in
  solve|pair|study) ;;
  *) echo "usage: mode-set.sh <solve|pair|study>" >&2; exit 1 ;;
esac

SID="${CLAUDE_CODE_SESSION_ID:-nosession}"
F="$SESSIONS/$SID"

# pair is the default: absence of a state file means pair.
PREV="pair"
[ -s "$F" ] && PREV="$(cat "$F")"

printf '%s' "$NEW" > "$F"
printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SID" "$PREV" "$NEW" >> "$ROOT/events.tsv"

# Keep the session directory from growing forever.
find "$SESSIONS" -type f -mtime +7 -delete 2>/dev/null

# An override you cannot see is the same as no friction: surface the running count.
if [ "$PREV" = "pair" ] && [ "$NEW" = "solve" ]; then
  N=$(awk -F'\t' '$3=="pair" && $4=="solve"' "$ROOT/events.tsv" 2>/dev/null | wc -l | tr -d ' ')
  echo "mode: pair -> solve   (override #$N)  — solve now governs; earlier mode instructions in this session no longer apply."
else
  echo "mode: $PREV -> $NEW  — $NEW now governs; earlier mode instructions in this session no longer apply."
fi
