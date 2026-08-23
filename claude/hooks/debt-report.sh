#!/usr/bin/env bash
# Compact summary of learning debt and mode usage, for /debt and /study.
# debt.md columns: date, session, kind(decision|gap|file), tag, text, why
set -uo pipefail
ROOT="$HOME/.claude/ai-mode"
D="$ROOT/debt.md"

echo "### Decisions delegated  (highest value: these transfer across systems)"
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
echo "### Files delegated  (weak signal: shows the area, not the reasoning)"
if [ -s "$D" ] && awk -F'\t' '$3=="file"' "$D" | grep -q .; then
  awk -F'\t' '$3=="file" {c[$4]++} END {for (t in c) printf "%-8s %d\n", t, c[t]}' "$D" | sort -k2 -rn
  echo "recent:"
  awk -F'\t' '$3=="file" {print "  " $5}' "$D" | tail -8
else
  echo "(none)"
fi

echo
echo "### Coverage"
if [ -s "$D" ]; then
  DEC=$(awk -F'\t' '$3=="decision"' "$D" | wc -l | tr -d ' ')
  FIL=$(awk -F'\t' '$3=="file"'     "$D" | wc -l | tr -d ' ')
  echo "decisions recorded: $DEC   files touched: $FIL"
  [ "$FIL" -gt 0 ] && [ "$DEC" -eq 0 ] && echo "NOTE: files were delegated but no decisions were recorded — the reasoning behind that work was not captured."
else
  echo "(debt log empty)"
fi

echo
echo "### Mode usage"
if [ -s "$ROOT/events.tsv" ]; then
  awk -F'\t' '{c[$4]++} END {for (m in c) printf "switched to %-6s %d times\n", m, c[m]}' "$ROOT/events.tsv"
  OV=$(awk -F'\t' '$3=="pair" && $4=="solve"' "$ROOT/events.tsv" | wc -l | tr -d ' ')
  PS=$(awk -F'\t' '$4=="pair"'  "$ROOT/events.tsv" | wc -l | tr -d ' ')
  SS=$(awk -F'\t' '$4=="solve"' "$ROOT/events.tsv" | wc -l | tr -d ' ')
  echo "pair -> solve overrides: $OV"
  echo "explicit pair:solve ratio: $PS:$SS"
else
  echo "(no mode switches recorded — every session has run on the pair default)"
fi
