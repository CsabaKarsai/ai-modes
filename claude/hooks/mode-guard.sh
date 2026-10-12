#!/usr/bin/env bash
# PreToolUse guard: enforces the active AI-usage mode on file-writing tools.
#
#   pair  (default) -> every write denied until the path is explicitly unlocked
#                      as agreed scaffolding (see pair-unlock.sh)
#   study           -> only notes writable; the user types every line of code
#   solve           -> nothing denied
#
# Before the mode, the phase: in implement, spec and design paths are frozen in every mode.
# Paths are classified relative to the root of the git repo containing them (see path_class).
#
# In every mode the agent may not switch modes or write ~/.claude/ai-mode/, and the
# guard's own hooks and mode skills follow the active mode instead of being exempt.
#
# Knows nothing about languages, frameworks or skill areas. Which work deserves
# the learning tax is decided by which mode was chosen, not by this script.
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
# shellcheck source=/dev/null
[ -f "$ROOT/guard.conf" ] && . "$ROOT/guard.conf"
: "${EXEMPT:=^$HOME/\.claude/}"
: "${NOTES_OK:=\.(md|txt)$}"
# Space-separated globs relative to the repo root; ** crosses directories, * and ? do not.
# Kept here as well because the installed guard.conf is a copy that predates these keys.
: "${CLASS_PLAN:=.requirements/*/PLAN.md}"
: "${CLASS_SPEC:=.requirements/**}"
: "${CLASS_DESIGN:=.system_design/SYSTEM_DESIGN.md docs/adr/**}"

IN=$(cat)
SID=$(jq -r  '.session_id // ""'           <<<"$IN")
TOOL=$(jq -r '.tool_name // ""'            <<<"$IN")
FP=$(jq -r   '.tool_input.file_path // ""' <<<"$IN")
CMD=$(jq -r  '.tool_input.command // ""'   <<<"$IN")
CWD=$(jq -r  '.cwd // ""'                  <<<"$IN")

# State is phase:mode; absent = plan:pair, a legacy mode-only file = plan:<mode>.
STATE=plan:pair
[ -n "$SID" ] && [ -s "$ROOT/sessions/$SID" ] && STATE=$(cat "$ROOT/sessions/$SID")
case "$STATE" in *:*) ;; *) STATE="plan:$STATE" ;; esac
PHASE="${STATE%%:*}" MODE="${STATE#*:}"
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

freeze_msg() {
  printf '%s' "implement phase: $1 is $2 and frozen in every mode, so the contract cannot change to fit the code.
If it is wrong, stop and tell the user why; only they can go back with /phase plan.
Do not route around this with a Bash redirect, heredoc or an in-place edit."
}

SWITCH_MSG='Mode and phase switches are user-only: the user types /solve, /pair, /study or /phase and the prompt hook applies it.
Do not run mode-set.sh or write ~/.claude/ai-mode/ yourself, in any mode.'

# Hardcoded rather than in guard.conf, because guard.conf is itself state the agent must not rewrite.
STATE_RE='^('"$HOME"'|~|\$HOME)/\.claude/ai-mode/'
SELF_RE='^('"$HOME"'|~|\$HOME)/\.claude/(hooks|skills/(pair|solve|study|debt))/'
# mode-set.sh in command position (line start or after ; & | ( ` $( ), past env assignments and wrappers.
RUN_SWITCH_RE='(^|[;&|(`]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((bash|sh|zsh|exec|env|command|source|\.)[[:space:]]+)*[^[:space:];&|]*mode-set\.sh'

# Glob to anchored ERE: ** matches across directories, * and ? stay within one segment.
glob_re() {
  local g="$1" out="" c i
  for ((i = 0; i < ${#g}; i++)); do
    c="${g:i:1}"
    case "$c" in
      '*') if [ "${g:i+1:1}" = '*' ]; then out+='.*'; i=$((i + 1)); else out+='[^/]*'; fi ;;
      '?') out+='[^/]' ;;
      [.+^\$\(\)\[\]\{\}\|\\]) out+="\\$c" ;;
      *) out+="$c" ;;
    esac
  done
  printf '^%s$' "$out"
}

# Print "<class> <path relative to repo root>" for a frozen-class path, nothing otherwise.
# The root is that of the git repo containing the file (not the session cwd), so a checkout,
# a worktree and another repository all behave the same. Outside any repo: no class.
path_class() {
  local p="$1" d root rel cls pats pat
  d=$(dirname "$p")
  while [ ! -d "$d" ]; do d=$(dirname "$d"); done
  root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  rel="${p#"$root"/}"
  [ "$rel" = "$p" ] && return 0
  for cls in plan spec design; do
    case "$cls" in plan) pats=$CLASS_PLAN ;; spec) pats=$CLASS_SPEC ;; design) pats=$CLASS_DESIGN ;; esac
    # Per-repo override in .git/config, shared by all worktrees and never committed.
    pats=$(git -C "$root" config --local --get "ai-modes.$cls" 2>/dev/null || printf '%s' "$pats")
    read -ra pats <<<"$pats"
    for pat in "${pats[@]}"; do
      [[ "$rel" =~ $(glob_re "$pat") ]] && { printf '%s %s' "$cls" "$rel"; return 0; }
    done
  done
}

# Decide for one write target.
check() {
  local raw="$1" p hit; p=$(abspath "$raw")
  # Mode state is written only by the hooks, never by the agent, whatever the mode.
  if printf '%s\n%s' "$p" "$raw" | grep -Eq "$STATE_RE"; then deny "$SWITCH_MSG"; fi
  # Freeze layer: anything but plan freezes spec and design, independent of the mode.
  if [ "$PHASE" != plan ]; then
    hit=$(path_class "$p")
    case "$hit" in spec\ *|design\ *) deny "$(freeze_msg "${hit#* }" "${hit%% *}")" ;; esac
  fi
  # The guard's own code is not exempt tooling: it follows the active mode like any project file.
  if ! printf '%s\n%s' "$p" "$raw" | grep -Eq "$SELF_RE"; then
    printf '%s' "$p"   | grep -Eq "$EXEMPT" && return 0
    printf '%s' "$raw" | grep -Eq "$EXEMPT" && return 0
  fi
  case "$MODE" in
    solve) ;;   # nothing is denied and nothing is logged
    study) printf '%s' "$p" | grep -Eq "$NOTES_OK" || deny "$STUDY_MSG" ;;
    *)     grep -qxF "$p" "$UNLOCKED" 2>/dev/null || deny "$PAIR_MSG" ;;   # pair, and any unreadable state
  esac
  return 0
}

case "$TOOL" in
  Write|Edit|NotebookEdit)
    [ -n "$FP" ] && check "$FP"
    ;;
  Bash)
    [ -z "$CMD" ] && exit 0
    # Switching is the user's alone: only the prompt hook runs mode-set.sh; reading it stays allowed.
    if printf '%s' "$CMD" | grep -Eq "$RUN_SWITCH_RE"; then deny "$SWITCH_MSG"; fi
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
