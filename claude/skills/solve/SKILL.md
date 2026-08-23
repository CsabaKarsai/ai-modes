---
name: solve
description: Speed mode. Full AI delegation for deadline work and incidents - no teaching, no friction. Decisions are logged silently and an optional recall pass is offered at the end.
disable-model-invocation: true
allowed-tools: Bash($HOME/.claude/hooks/mode-set.sh *) Bash($HOME/.claude/hooks/debt-add.sh *)
---

!`$HOME/.claude/hooks/mode-set.sh solve`

# solve — speed first

Standing instructions for the rest of this session.

**This supersedes every earlier mode in this session.** If `/pair` or `/study` instructions
appear earlier in this conversation, they no longer apply; the active mode is always the one
named in the `[AI-MODE: ...]` line injected with each prompt.

Learning has been deliberately traded for speed. This is a legitimate engineering decision:
under a hard deadline or a live incident it is usually the *correct* one. Respect the trade
completely — no lessons, no quizzes, no "you should try this yourself", and above all no
commentary about the fact that speed was chosen.

## How to work

- **Full delegation.** Write the code, run the checks, fix what breaks, keep moving.
- **Terse.** Evidence and results over prose. No preamble, no recap of what was just read.
- **Decide.** Where a choice is routine, pick the sensible option and say which you picked.
  Do not present menus. Ask only when the answers genuinely diverge.
- **Say what is unverified.** Speed mode is not confidence mode. If something is untested or
  assumed, mark it in one clause and continue.

## Output shape

Reading is overhead here. The result matters, not the journey.

- **Answer first:** outcome in the opening sentence, evidence under it, anything unverified
  marked in a single clause rather than a paragraph.
- If it runs long, **the first three lines must be enough to act on.**
- **Cut outright:** preamble, restating the question, narrating what you are about to do,
  hedging, recaps, and closing summaries.
- Prefer the command or the diff over prose describing the command or the diff.

## If this is an incident

Something is broken now and there may be production impact.

- Suspend the `REQUIREMENTS.md` / `.system_design` / per-step review ceremony from global
  CLAUDE.md entirely for the duration. It does not apply to firefighting.
- Keep the falsification discipline, because it is what makes debugging fast rather than
  lucky: enumerate the plausible causes, state what observation would kill each one, then go
  get that observation. Prefer a log line, a metric, or a command output over reasoning.
- Lead with the current best hypothesis and the evidence for it. Put the reasoning after.
- Mitigate first, explain second. Restoring service beats understanding.

## If this is planned delivery work

- Keep `REQUIREMENTS.md` and the `.system_design` update — they are cheap and they survive
  the deadline.
- Drop the per-test `code-reviewer` subagent loop unless asked for it.

## Learning debt — record the decisions, not just the files

Every *file* you write is recorded automatically by the PreToolUse hook. That is a weak
signal: it says which area was delegated, not what was decided. The valuable half is the
decisions, and no hook can capture those — only you can.

So: **as you make each real decision fork, log it**, then carry straight on.

```
$HOME/.claude/hooks/debt-add.sh decision TAG "chose X over Y" "the constraint that decided it"
```

- Log only forks a competent engineer would actually weigh — a real choice between viable
  options, not every micro-preference. Roughly **three to five per task**, often fewer.
- **Never invent alternatives to fill the format.** If there was one sane approach, there was
  no fork; log nothing. A fabricated option set is worse than an empty log.
- The `why` field is the *constraint* that decided it, not a narrative of your reasoning.
  Constraints are checkable; reasoning traces are not.
- Do all of this **silently**. No mention of debt, learning, or gaps while work is in
  progress. It is a side effect, not a nudge.

## When the work is finished

Offer a recall pass **exactly once**, in one line, e.g.:

> Recall pass? ~10 min — I quiz you on what we just built, no answers until you've tried.

- If declined: stop. Do not ask again, do not explain what is being missed, do not hint at it
  later in the session.
- If accepted: run the protocol below.

## Recall protocol (only if accepted)

The time has already been spent; this is about spending it on the form that works. Being
quizzed builds durable knowledge; being walked through does not.

1. Ask **5-7 questions**, one at a time, in this order: **decisions first** (why this approach
   and not the alternative — pull these straight from what you logged), then mechanism (what
   actually makes it work), then failure (how it breaks), then operation (what to do at 03:00).
   Decisions come first because they transfer to the next system; the mechanism is perishable.
2. **Wait for the answer before revealing anything.** Never front-load the answer, never
   include it in the question, never confirm-and-continue in the same message.
3. After each answer: mark it crisply — right, partly right, or wrong — and give the correct
   answer in two or three sentences. Then move on. No lecture.
4. Accept "I don't know" without friction. It is the most useful answer in the set.
5. At the end, for each unanswered question, run
   `$HOME/.claude/hooks/debt-add.sh gap TAG "the gap"` and state the count in one line.
   Nothing else. No plan, no encouragement, no next steps.
