#!/usr/bin/env bash
# Learning debt: record and report.
#
#   debt.sh add decision TAG "chose X over Y" "the constraint that decided it"
#   debt.sh add gap      TAG "what could not be explained"
#   debt.sh report
#
# debt.md columns: date, session, kind (decision|gap), tag, text, why
set -uo pipefail
ROOT="$HOME/.claude/ai-mode"; mkdir -p "$ROOT"
D="$ROOT/debt.md"

usage() { echo 'usage: debt.sh add <decision|gap> TAG "text" ["why"]  |  debt.sh report' >&2; exit 1; }

case "${1:-}" in
  add)
    shift
    KIND="${1:-}"; case "$KIND" in decision|gap) ;; *) usage ;; esac
    shift
    TAG="${1:-other}"; shift || true
    TEXT="${1:-}";     shift || true
    WHY="${1:-}"
    [ -z "$TEXT" ] && usage
    clean() { printf '%s' "$1" | tr '\t\n' '  '; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ)" "${CLAUDE_CODE_SESSION_ID:-nosession}" \
      "$KIND" "$TAG" "$(clean "$TEXT")" "$(clean "$WHY")" >> "$D"
    echo "logged [$KIND/$TAG] $TEXT"
    ;;

  report)
    echo "### Decisions delegated  (these transfer across systems)"
    if [ -s "$D" ] && awk -F'\t' '$3=="decision"' "$D" | grep -q .; then
      awk -F'\t' '$3=="decision" {printf "%s  [%s]  %s\n            because: %s\n", substr($1,1,10), $4, $5, ($6==""?"(constraint not recorded)":$6)}' "$D"
    else
      echo "(none)"
    fi

    echo
    echo "### Gaps  (asked and could not answer)"
    if [ -s "$D" ] && awk -F'\t' '$3=="gap"' "$D" | grep -q .; then
      awk -F'\t' '$3=="gap" {printf "%s  [%s]  %s\n", substr($1,1,10), $4, $5}' "$D"
    else
      echo "(none)"
    fi

    echo
    echo "### Mode usage"
    E="$ROOT/events.tsv"
    if [ -s "$E" ]; then
      awk -F'\t' '{c[$4]++} END {for (m in c) printf "switched to %-6s %d times\n", m, c[m]}' "$E"
      echo "pair -> solve overrides: $(awk -F'\t' '$3=="pair" && $4=="solve"' "$E" | wc -l | tr -d ' ')"
      echo "explicit pair:solve ratio: $(awk -F'\t' '$4=="pair"' "$E" | wc -l | tr -d ' '):$(awk -F'\t' '$4=="solve"' "$E" | wc -l | tr -d ' ')"
    else
      echo "(no mode switches recorded — every session has run on the pair default)"
    fi
    ;;

  *) usage ;;
esac
