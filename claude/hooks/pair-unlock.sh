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
SELF_DIR=$(dirname "$(dirname "$(realpath "$0")")")

[ $# -eq 0 ] && { echo "usage: pair-unlock.sh PATH [PATH ...]" >&2; exit 1; }

for raw in "$@"; do
  case "$raw" in
    /*) p="$raw" ;;
    "~/"*) p="$HOME/${raw#\~/}" ;;
    *) p="$PWD/$raw" ;;
  esac
  p=$(realpath -m "$p" 2>/dev/null || printf '%s' "$p")
  # The guard's own code and the mode state are never scaffolding.
  case "$p" in
    "$HOME/.claude/ai-mode/"*|"$SELF_DIR/hooks/"*|"$SELF_DIR/skills/"*)
      echo "refused: $p is ai-modes guard code or mode state" >&2; continue ;;
  esac
  grep -qxF "$p" "$F" 2>/dev/null || printf '%s\n' "$p" >> "$F"
  echo "unlocked as scaffolding: $p"
done

find "$ROOT/unlocked" -type f -mtime +30 -delete 2>/dev/null
