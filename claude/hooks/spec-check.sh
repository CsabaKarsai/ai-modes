#!/usr/bin/env bash
# Check that a local spec's acceptance checks are verified, and guard commit messages.
#
#   spec-check.sh [SPEC_DIR]    check a spec (default: the newest .requirements/*/ of this repo)
#   spec-check.sh install       link pre-push and commit-msg hooks into this repo (never committed)
#   spec-check.sh uninstall     remove those links, leaving any other hook alone
#   spec-check.sh leaks [all|noids]  print stdin lines that must not leave the machine; exit 1 on a hit
#
# Linked as a git hook it dispatches on its name: pre-push runs the check when the repo has a
# spec; commit-msg rejects what the leak scanner finds.
#
# Verification lines in REQUIREMENTS.md, one per check (several IDs may share a line):
#   - AC-1, AC-2: `command`        run from the repo root; exit 0 = pass
#   - AC-3: manual — what to look at   listed, not run
set -uo pipefail

# Hooks link to the path this was called by (normally ~/.claude/hooks/spec-check.sh), so they
# survive the repo checkout moving; ownership is decided on the resolved file.
SELF=$(realpath -s "${BASH_SOURCE[0]}")
REAL=$(realpath "${BASH_SOURCE[0]}")
ours() { [ -L "$1" ] && [ "$(realpath "$1" 2>/dev/null)" = "$REAL" ]; }

# What never goes into shared text: the local spec's check IDs and paths, and AI attribution.
# Jira and Confluence use "noids", because teams number their own acceptance criteria there.
LEAK_ID_RE='(^|[^[:alnum:]_])AC-[0-9]+([^[:alnum:]_]|$)'
LEAK_PATH_RE='\.requirements/'
AI_TOOLS='claude|anthropic|copilot|codex|cursor|gemini|chatgpt|openai'
LEAK_AI_RE="co-authored-by:.*($AI_TOOLS)|generated (with|by) .{0,40}($AI_TOOLS)|🤖"
# One command proving more checks than this is reported, not failed.
MAX_PER_COMMAND=3

leaks() {
  local text hits
  text=$(cat)
  hits=$( { grep -nE "$LEAK_PATH_RE" <<<"$text"
            [ "${1:-all}" = noids ] || grep -nE "$LEAK_ID_RE" <<<"$text"
            grep -niE "$LEAK_AI_RE" <<<"$text"; } | sort -t: -k1,1n -u )
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"
  return 1
}

repo_root() { git rev-parse --show-toplevel 2>/dev/null; }

# Newest spec folder: folder names start with a UTC timestamp, so they sort by time.
newest_spec() {
  local root; root=$(repo_root) || return 0
  find "$root/.requirements" -mindepth 2 -maxdepth 2 -name REQUIREMENTS.md 2>/dev/null \
    | sort | tail -1 | xargs -r dirname
}

# Print the body of one "## <title>" section.
section() { awk -v t="$2" '/^## /{on = ($0 ~ "^## " t)} on && !/^## /' "$1"; }

check() {
  local dir="${1:-}" req root acs fail=0 line ids rest id cmd
  [ -n "$dir" ] || dir=$(newest_spec)
  if [ -z "$dir" ]; then echo "spec-check: no spec in this repository (.requirements/*/REQUIREMENTS.md)"; return 0; fi
  req="$dir/REQUIREMENTS.md"
  [ -f "$req" ] || { echo "spec-check: $req not found" >&2; return 1; }
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$dir")")
  echo "spec-check: $req"

  acs=$(section "$req" 'Acceptance checks' | grep -oE '\bAC-[0-9]+\b' | sort -u -V)
  declare -A seen=() cover=()
  while IFS= read -r line; do
    [[ "$line" =~ ^[-*][[:space:]]+(AC-[0-9]+([[:space:]]*,[[:space:]]*AC-[0-9]+)*):[[:space:]]*(.*)$ ]] || continue
    ids=$(grep -oE 'AC-[0-9]+' <<<"${BASH_REMATCH[1]}"); rest="${BASH_REMATCH[3]}"
    for id in $ids; do seen[$id]=1; done
    if [[ "$rest" =~ ^\`([^\`]+)\`[[:space:]]*$ ]]; then
      cmd="${BASH_REMATCH[1]}"
      cover[$cmd]=$(( ${cover[$cmd]:-0} + $(wc -w <<<"$ids") ))
      if (cd "$root" && bash -c "$cmd") </dev/null >/dev/null 2>&1; then
        for id in $ids; do printf 'PASS     %-6s %s\n' "$id" "$cmd"; done
      else
        for id in $ids; do printf 'FAIL     %-6s %s\n' "$id" "$cmd"; done; fail=1
      fi
    elif [[ "$rest" =~ ^manual ]]; then
      for id in $ids; do printf 'MANUAL   %-6s %s\n' "$id" "$rest"; done
    else
      for id in $ids; do printf 'BAD      %-6s needs `command` or "manual — ...": %s\n' "$id" "$rest"; done; fail=1
    fi
  done < <(section "$req" 'Verification')

  for id in $acs; do
    [ -n "${seen[$id]:-}" ] || { printf 'MISSING  %-6s no Verification line\n' "$id"; fail=1; }
  done
  # A single broad command proves little per check; say so without failing.
  for cmd in "${!cover[@]}"; do
    [ "${cover[$cmd]}" -gt "$MAX_PER_COMMAND" ] &&
      printf 'WARN     %s checks share one command; a narrower command per check proves more: %s\n' "${cover[$cmd]}" "$cmd"
  done
  return $fail
}

commit_msg() {
  local hits
  hits=$(grep -v '^#' "$1" | leaks all) && return 0
  echo "commit-msg: the message names the local spec (AC-n IDs, .requirements/ paths) or credits an AI tool:" >&2
  printf '%s\n' "$hits" >&2
  echo "State the behaviour, the reason and how it was verified in plain words instead." >&2
  return 1
}

hooks_dir() {
  local d; d=$(git rev-parse --git-path hooks 2>/dev/null) || { echo "not in a git repository" >&2; return 1; }
  # --git-path is relative to the cwd; in a worktree it already points at the common hooks dir.
  realpath -m "$d"
}

install_hooks() {
  local d h rc=0 custom
  # A custom hooks dir is the team's (often committed, e.g. .githooks/): never write into it.
  if custom=$(git config --get core.hooksPath 2>/dev/null); then
    echo "not installed: this repository runs its hooks from core.hooksPath=$custom, which its owners manage." >&2
    echo "To add the check, call it from that pre-push hook yourself: $SELF pre-push" >&2
    return 1
  fi
  d=$(hooks_dir) || return 1
  mkdir -p "$d"
  for h in pre-push commit-msg; do
    if ours "$d/$h"; then echo "already linked: $d/$h"
    elif [ -e "$d/$h" ] || [ -L "$d/$h" ]; then echo "left alone: $d/$h is not ours; chain it by hand" >&2; rc=1
    else ln -s "$SELF" "$d/$h" && echo "linked: $d/$h"
    fi
  done
  return $rc
}

uninstall_hooks() {
  local d h; d=$(hooks_dir) || return 1
  for h in pre-push commit-msg; do
    ours "$d/$h" && rm -f "$d/$h" && echo "removed: $d/$h"
  done
  return 0
}

case "$(basename "$0")" in
  pre-push)   check; exit $? ;;
  commit-msg) commit_msg "$1"; exit $? ;;
esac

case "${1:-}" in
  install)    install_hooks ;;
  uninstall)  uninstall_hooks ;;
  pre-push)   check ;;
  commit-msg) shift; commit_msg "${1:-}" ;;
  leaks)      shift; leaks "${1:-all}" ;;
  -h|--help)  sed -n '2,14p' "$REAL" ;;
  *)          check "${1:-}" ;;
esac
