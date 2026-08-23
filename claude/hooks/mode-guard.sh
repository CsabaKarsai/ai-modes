#!/usr/bin/env bash
# PreToolUse guard: enforces the active AI-usage mode on file-writing tools.
#
#   pair  (default) -> every write denied until the path is explicitly unlocked
#                      as agreed scaffolding (see pair-unlock.sh)
#   study           -> only notes writable; the user types every line of code
#   solve           -> nothing denied
#
# Knows nothing about languages, frameworks or skill areas. Which work deserves
# the learning tax is decided by which mode was chosen, not by this script.
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
# shellcheck source=/dev/null
[ -f "$ROOT/guard.conf" ] && . "$ROOT/guard.conf"
: "${EXEMPT:=^$HOME/\.claude/}"
: "${NOTES_OK:=\.(md|txt)$}"

IN=$(cat)
SID=$(jq -r  '.session_id // ""'           <<<"$IN")
TOOL=$(jq -r '.tool_name // ""'            <<<"$IN")
FP=$(jq -r   '.tool_input.file_path // ""' <<<"$IN")
CMD=$(jq -r  '.tool_input.command // ""'   <<<"$IN")
CWD=$(jq -r  '.cwd // ""'                  <<<"$IN")

MODE=pair
[ -n "$SID" ] && [ -s "$ROOT/sessions/$SID" ] && MODE=$(cat "$ROOT/sessions/$SID")
UNLOCKED="$ROOT/unlocked/$SID"

# Resolve a possibly-relative target against the session's working directory.
abspath() {
  local p="$1"
  case "$p" in
    /*) ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    *) [ -n "$CWD" ] && p="$CWD/$p" ;;
  esac
  realpath -m "$p" 2>/dev/null || printf '%s' "$p"
}

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

PAIR_MSG='pair mode. Writes are locked here. This mode was chosen to learn this task, so the load-bearing lines belong to the user.

Decide together first: state the constraints, name the real alternatives (names only, no verdict,
and never invent options to fill the format), ask which one wins and why, then WAIT for the answer.
Mark the delta, then agree the split - which lines carry the mechanism (theirs), which are scaffolding (yours).

Then, for each file that is agreed scaffolding, unlock it and write it:
  ~/.claude/hooks/pair-unlock.sh PATH

Never unlock the load-bearing part. Describe it in words, name the file and the location, then wait.
Do not route around this with a Bash redirect, heredoc or an in-place edit.
For speed instead of learning right now, the user types /solve.'

STUDY_MSG='study mode. Only notes and documents are writable - the user types every line of code.
Explain what to write and why, then wait for them to produce it, then review what they wrote.
Do not route around this with a Bash redirect, heredoc or an in-place edit.'

# Decide for one write target.
check() {
  local raw="$1" p; p=$(abspath "$raw")
  printf '%s' "$p"   | grep -Eq "$EXEMPT" && return 0
  printf '%s' "$raw" | grep -Eq "$EXEMPT" && return 0
  case "$MODE" in
    pair)  grep -qxF "$p" "$UNLOCKED" 2>/dev/null || deny "$PAIR_MSG" ;;
    study) printf '%s' "$p" | grep -Eq "$NOTES_OK" || deny "$STUDY_MSG" ;;
    *)     ;;   # solve: nothing is denied and nothing is logged
  esac
  return 0
}

case "$TOOL" in
  Write|Edit|NotebookEdit)
    [ -n "$FP" ] && check "$FP"
    ;;
  Bash)
    [ -z "$CMD" ] && exit 0
    # A redirect not preceded by '-', so an arrow in ordinary text is not a write.
    TARGETS=$(
      { printf '%s' "$CMD" | grep -Eo '(^|[^-])>>?[[:space:]]*[^[:space:];|&()<]+' \
            | sed -E 's/^[^>]*>>?[[:space:]]*//'
        printf '%s' "$CMD" | grep -Eo '(^|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^[:space:];|&()<]+' \
            | sed -E 's/^[[:space:]]*tee[[:space:]]+(-a[[:space:]]+)?//'
        printf '%s' "$CMD" | grep -Eo 'sed[[:space:]]+-i[^;|&]*' | grep -Eo '[^[:space:]]+$'
      } 2>/dev/null | sort -u
    )
    [ -z "$TARGETS" ] && exit 0
    while IFS= read -r T; do
      [ -z "$T" ] && continue
      case "$T" in /dev/*) continue ;; esac
      # Ignore anything not shaped like a path: format specifiers, fds, operators.
      case "$T" in *[!A-Za-z0-9_./~-]*) continue ;; esac
      check "$T"
    done <<< "$TARGETS"
    ;;
esac
exit 0
