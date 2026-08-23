#!/usr/bin/env bash
# Unlock one or more paths for writing in pair mode.
#
# Only for files agreed to be scaffolding, plumbing, tests or boilerplate -
# never the load-bearing lines, which the user types. Every unlock is visible in
# the transcript, which is the check on this being self-declared.
#
# Usage: pair-unlock.sh PATH [PATH ...]
set -uo pipefail
ROOT="$HOME/.claude/ai-mode"
SID="${CLAUDE_CODE_SESSION_ID:-nosession}"
mkdir -p "$ROOT/unlocked"
F="$ROOT/unlocked/$SID"

[ $# -eq 0 ] && { echo "usage: pair-unlock.sh PATH [PATH ...]" >&2; exit 1; }

for raw in "$@"; do
  case "$raw" in
    /*) p="$raw" ;;
    "~/"*) p="$HOME/${raw#\~/}" ;;
    *) p="$PWD/$raw" ;;
  esac
  p=$(realpath -m "$p" 2>/dev/null || printf '%s' "$p")
  grep -qxF "$p" "$F" 2>/dev/null || printf '%s\n' "$p" >> "$F"
  echo "unlocked as scaffolding: $p"
done

find "$ROOT/unlocked" -type f -mtime +7 -delete 2>/dev/null
