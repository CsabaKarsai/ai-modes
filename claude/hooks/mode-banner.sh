#!/usr/bin/env bash
# UserPromptSubmit hook: applies mode and phase switches and re-states the active state every turn.
# Stdout is injected into Claude's context, which is what stops mode drift
# in long sessions and covers sessions where no mode command was ever typed.
#
# This is the only place a switch happens: the hook fires on what the user
# submits, never on the agent's own tool calls, so a switch here is user-made.
#
# State is phase:mode. An absent file is plan:pair; a legacy mode-only file or events row is plan:<mode>.
set -uo pipefail

ROOT="$HOME/.claude/ai-mode"
IN=$(cat)
SID=$(jq -r '.session_id // ""' <<<"$IN" 2>/dev/null || echo "")
PROMPT=$(jq -r '.prompt // ""' <<<"$IN" 2>/dev/null || echo "")
CWD=$(jq -r '.cwd // ""' <<<"$IN" 2>/dev/null || echo "")
NOTICE=""
note() { NOTICE="${NOTICE:+$NOTICE
}$1"; }
normalize() { case "$1" in *:*) printf '%s' "$1" ;; *) printf 'plan:%s' "$1" ;; esac; }
valid() { case "$1" in plan:solve|plan:pair|plan:study|implement:solve|implement:pair|implement:study) return 0 ;; esac; return 1; }

STATE=plan:pair RAWSTATE=""
if [ -n "$SID" ] && [ -s "$ROOT/sessions/$SID" ]; then RAWSTATE=$(cat "$ROOT/sessions/$SID"); STATE=$(normalize "$RAWSTATE"); fi

# Tamper check: the session file must match the last user-made switch (legacy 4-column rows count as user).
# An absent file is plan:pair, the safe direction, so only a present file that disagrees or is invalid is restored.
# Runs before applying a typed switch, so a switch never builds on a tampered state.
if [ -n "$RAWSTATE" ]; then
  EXPECTED=$(awk -F'\t' -v s="$SID" '$2==s && (NF==4 || $5=="user") {m=$4} END {print m}' "$ROOT/events.tsv" 2>/dev/null)
  EXPECTED=$(normalize "${EXPECTED:-pair}")
  if [ "$STATE" != "$EXPECTED" ] || ! valid "$STATE"; then
    printf '%s' "$EXPECTED" > "$ROOT/sessions/$SID"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SID" "$RAWSTATE" "$EXPECTED" revert >> "$ROOT/events.tsv"
    note "[AI-MODE ALERT] State was set to $RAWSTATE without the user typing it. Restored $EXPECTED and logged it for /debt."
    STATE="$EXPECTED"
  fi
fi

# Apply /solve, /pair, /study or /phase typed by the user (raw form, or the expanded command-name tag).
RAW_RE='^[[:space:]]*/(solve|pair|study)([[:space:]]|$)'
TAG_RE='<command-name>/(solve|pair|study)</command-name>'
PHASE_RAW_RE='^[[:space:]]*/phase([[:space:]]+([^[:space:]]+))?([[:space:]]|$)'
PHASE_TAG_RE='<command-name>/phase</command-name>'
ARGS_RE='<command-args>[[:space:]]*([^[:space:]<]+)'
NEW=""
if [[ "$PROMPT" =~ $RAW_RE ]] || [[ "$PROMPT" =~ $TAG_RE ]]; then
  NEW="${STATE%%:*}:${BASH_REMATCH[1]}"
elif [[ "$PROMPT" =~ $PHASE_RAW_RE ]] || [[ "$PROMPT" =~ $PHASE_TAG_RE ]]; then
  REQ="${BASH_REMATCH[2]:-}"
  [[ "$PROMPT" =~ $PHASE_TAG_RE ]] && { REQ=""; [[ "$PROMPT" =~ $ARGS_RE ]] && REQ="${BASH_REMATCH[1]}"; }
  case "$REQ" in
    plan|implement) NEW="$REQ:${STATE#*:}" ;;
    *) note "[AI-PHASE REJECTED] /phase needs plan or implement (got: ${REQ:-nothing}). State unchanged: $STATE." ;;
  esac
fi
if [ -n "$SID" ] && [ -n "$NEW" ]; then
  note "$(CLAUDE_CODE_SESSION_ID="$SID" AI_MODE_SOURCE=user "$HOME/.claude/hooks/mode-set.sh" "$NEW" 2>&1)"
  STATE="$NEW"
fi
[ -n "$NOTICE" ] && printf '%s\n' "$NOTICE"

# Refresh existing state on every prompt so pruning counts from last activity, not last switch.
# Never create a file here: an absent session file is what makes plan:pair the default.
if [ -n "$SID" ]; then
  for f in "$ROOT/sessions/$SID" "$ROOT/unlocked/$SID" "$ROOT/hints/$SID"; do
    [ -e "$f" ] && touch "$f"
  done
fi

PHASE="${STATE%%:*}" MODE="${STATE#*:}"

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
During an incident, /solve is the user's explicit opt-out from the local spec in the
CLAUDE.md change workflow; planned work keeps the spec and plan.
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

# The guard sees paths, not authorship: what each mode means inside a phase is carried here.
case "$PHASE" in
  implement)
    echo "[AI-PHASE: implement] The spec and design docs are frozen in every mode (by default"
    echo ".requirements/** except PLAN.md, .system_design/SYSTEM_DESIGN.md, docs/adr/**). If the spec"
    echo "is wrong, stop and say why: only the user can go back with /phase plan. PLAN.md stays writable."
    case "$MODE" in
      solve) echo "Write the tests and code; record progress in PLAN.md. Never weaken or delete an assertion to get
green: if one must change, name it and why before changing it." ;;
      study) echo "No code: quiz on the implementation, the user writes it." ;;
      *)     echo "The user types the load-bearing lines, including test assertions; you write agreed scaffolding." ;;
    esac
    ;;
  *)
    echo "[AI-PHASE: plan] Nothing is frozen. Output: the local spec (REQUIREMENTS.md), PLAN.md, design decisions."
    case "$MODE" in
      solve) echo "Draft the spec and plan from the user's answers; the user accepts or refines them." ;;
      study) echo "Quiz on the problem; write nothing." ;;
      *)     echo "Ask one question at a time. The user writes the THEN of each acceptance check; the rest of the
spec and the plan are agreed scaffolding you write." ;;
    esac
    echo "Once the spec is agreed, the user types /phase implement to freeze it."
    ;;
esac

# Phase is per session, not per change: point out a mismatch with the spec in the prompt's repo.
REPO=$([ -n "$CWD" ] && [ -d "$CWD" ] && git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO" ]; then
  SPECS=$(find "$REPO/.requirements" -mindepth 2 -maxdepth 2 -name REQUIREMENTS.md 2>/dev/null | sort)
  if [ "$PHASE" = plan ]; then
    PLAN="$(dirname "$(tail -1 <<<"$SPECS")" 2>/dev/null)/PLAN.md"
    if [ -n "$SPECS" ] && grep -q '^[[:space:]]*- \[[xX]\]' "$PLAN" 2>/dev/null && grep -q '^[[:space:]]*- \[ \]' "$PLAN" 2>/dev/null; then
      echo "[AI-PHASE HINT] ${PLAN#"$REPO"/} has steps in progress. If implementation is under way, the user"
      echo "types /phase implement to freeze the spec; mention it once."
    fi
  elif ! grep -qE '\bAC-[0-9]+\b' $SPECS /dev/null 2>/dev/null; then
    echo "[AI-PHASE WARNING] implement phase, but $REPO has no .requirements/*/REQUIREMENTS.md with acceptance"
    echo "checks, so nothing meaningful is frozen. Say so once; the user decides whether to /phase plan."
  fi
  # A spec without the checker hooks is checked by nobody: remind once per session and repo.
  if [ -n "$SPECS" ] && [ -n "$SID" ] && [ "$(git -C "$REPO" config --get ai-modes.hooks 2>/dev/null)" != off ]; then
    HOOK="$(cd "$REPO" && realpath -m "$(git rev-parse --git-path hooks)")/pre-push"
    if [ "$(realpath "$HOOK" 2>/dev/null)" != "$(realpath "$HOME/.claude/hooks/spec-check.sh" 2>/dev/null)" ] &&
       ! grep -qxF "$REPO" "$ROOT/hints/$SID" 2>/dev/null; then
      mkdir -p "$ROOT/hints" && printf '%s\n' "$REPO" >> "$ROOT/hints/$SID"
      find "$ROOT/hints" -type f -mtime +30 -delete 2>/dev/null
      echo "[AI-HOOKS HINT] $REPO has a local spec but no spec hooks. Mention once: the user can run"
      echo "~/.claude/hooks/spec-check.sh install there, or silence this with git config --local ai-modes.hooks off."
    fi
  fi
fi
