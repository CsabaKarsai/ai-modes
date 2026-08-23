#!/usr/bin/env bash
# Record an entry in the learning-debt log.
#
#   debt-add.sh decision <tag> "<chose X over Y>" "<the constraint that decided it>"
#   debt-add.sh gap      <tag> "<what could not be explained>"
#
# Columns: date, session, kind, tag, text, why
set -uo pipefail
ROOT="$HOME/.claude/ai-mode"; mkdir -p "$ROOT"

KIND="${1:-}"; shift || true
case "$KIND" in
  decision|gap) ;;
  *) echo "usage: debt-add.sh <decision|gap> <tag> \"<text>\" [\"<why>\"]" >&2; exit 1 ;;
esac

TAG="${1:-other}"; shift || true
TEXT="${1:-}"; shift || true
WHY="${1:-}"

[ -z "$TEXT" ] && { echo "debt-add.sh: text is required" >&2; exit 1; }

# Tabs are the field separator; strip any that appear in free text.
clean() { printf '%s' "$1" | tr '\t\n' '  '; }

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%FT%TZ)" "${CLAUDE_CODE_SESSION_ID:-nosession}" \
  "$KIND" "$TAG" "$(clean "$TEXT")" "$(clean "$WHY")" >> "$ROOT/debt.md"

echo "logged [$KIND/$TAG] $TEXT"
