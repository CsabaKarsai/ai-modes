#!/usr/bin/env bash
# UserPromptSubmit hook: applies mode switches and re-states the active mode every turn.
# Stdout is injected into Claude's context, which is what stops mode drift
# in long sessions and covers sessions where no mode command was ever typed.
#
# This is the only place a mode switch happens: the hook fires on what the user
# submits, never on the agent's own tool calls, so a switch here is user-made.
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
IN=$(cat)
SID=$(jq -r '.session_id // ""' <<<"$IN" 2>/dev/null || echo "")
PROMPT=$(jq -r '.prompt // ""' <<<"$IN" 2>/dev/null || echo "")
NOTICE=""

# Apply /solve, /pair or /study typed by the user (raw form, or the expanded command-name tag).
RAW_RE='^[[:space:]]*/(solve|pair|study)([[:space:]]|$)'
TAG_RE='<command-name>/(solve|pair|study)</command-name>'
REQ=""
if [[ "$PROMPT" =~ $RAW_RE ]] || [[ "$PROMPT" =~ $TAG_RE ]]; then REQ="${BASH_REMATCH[1]}"; fi
if [ -n "$SID" ] && [ -n "$REQ" ]; then
  NOTICE=$(CLAUDE_CODE_SESSION_ID="$SID" AI_MODE_SOURCE=user "$HOME/.claude/hooks/mode-set.sh" "$REQ" 2>&1)
fi

MODE=pair
[ -n "$SID" ] && [ -s "$ROOT/sessions/$SID" ] && MODE=$(cat "$ROOT/sessions/$SID")

# Tamper check: the session file must match the last user-made switch (legacy 4-column rows count as user).
# An absent file is pair, the safe direction, so only a present file that disagrees is restored.
if [ -n "$SID" ] && [ -s "$ROOT/sessions/$SID" ]; then
  EXPECTED=$(awk -F'\t' -v s="$SID" '$2==s && (NF==4 || $5=="user") {m=$4} END {print m}' "$ROOT/events.tsv" 2>/dev/null)
  [ -z "$EXPECTED" ] && EXPECTED=pair
  if [ "$MODE" != "$EXPECTED" ]; then
    printf '%s' "$EXPECTED" > "$ROOT/sessions/$SID"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SID" "$MODE" "$EXPECTED" revert >> "$ROOT/events.tsv"
    NOTICE="${NOTICE:+$NOTICE
}[AI-MODE ALERT] Mode was set to $MODE without the user typing /$MODE. Restored $EXPECTED and logged it for /debt."
    MODE="$EXPECTED"
  fi
fi
[ -n "$NOTICE" ] && printf '%s\n' "$NOTICE"

# Refresh existing state on every prompt so pruning counts from last activity, not last switch.
# Never create a file here: an absent session file is what makes pair the default.
if [ -n "$SID" ]; then
  for f in "$ROOT/sessions/$SID" "$ROOT/unlocked/$SID"; do
    [ -e "$f" ] && touch "$f"
  done
fi

case "$MODE" in
  solve)
    cat <<'TXT'
[AI-MODE: solve] Speed first. Full delegation, no teaching, no friction, no learning tax.
Answer first: outcome in the opening sentence, evidence under it, anything unverified marked in
one clause. If it runs long, the first three lines must be enough to act on. Cut preamble,
restating the question, narrating what you are about to do, recaps, and closing summaries.
Log each real decision fork as you make it, silently and without comment:
  ~/.claude/hooks/debt.sh add decision TAG "chose X over Y" "the constraint that decided it"
Only forks a competent engineer would actually weigh; max ~5 per task; never invent options to
fill the format. When the work is finished, offer a recall pass once (quiz-first) and accept a no.
TXT
    ;;
  study)
    cat <<'TXT'
[AI-MODE: study] Learning only, no delivery. Never write or edit code — the user types every line.
Ask before you tell: quiz first, let them attempt, then correct. Explain the why, then wait.
They should be producing most of the text. If you have written more than they have across the
last few exchanges, say so and hand back. Cut preamble, recaps, and closing summaries.
TXT
    ;;
  *)
    cat <<'TXT'
[AI-MODE: pair — default] This mode was chosen to learn this task, whatever it happens to involve.
All writes are locked. Before anything is written: state the constraints, name the real
alternatives (names only, no verdict), ask which one wins and why, then WAIT for the answer.
Mark the delta, agree the split, then unlock only agreed scaffolding and write it:
  ~/.claude/hooks/pair-unlock.sh PATH
Never unlock the load-bearing lines — describe them and wait for the user to type them.
Never narrate your own reasoning as if it were a proof; give constraints and alternatives that
can be independently checked.
Answer first and stay short: long output invites skimming, and skimming feels like understanding.
Delta max 6 lines, one line per rejected option. Make questions cheap to answer — offer a choice
plus one line of why, never an open essay. Cut preamble, recaps, and closing summaries.
Full protocol: /pair. Speed instead: /solve. Learning only: /study.
TXT
    ;;
esac
