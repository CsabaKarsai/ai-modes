# AI playbook

The half that cannot be automated. The modes enforce the mechanics; this is the judgment.

## The principle

AI does not erase skill. It removes the conditions under which skill forms — retrieval,
prediction that turns out wrong, productive struggle. So the goal is not *less AI*. It is:

> Protect three or four struggle moments per task. Delegate everything else, fast, guilt-free.

Corollary, and the cheapest win available: **retrieval beats explanation at identical cost.**
Being walked through a change produces recognition — it feels like understanding and decays
within days. Predicting before being told, re-deriving with the file closed, and being
quizzed produce knowledge that survives. If you are going to spend an hour understanding
something, that hour spent on retrieval is worth several spent on explanation.

## The bounded target

Not "learn everything I am currently weak at". That is unbounded and there is no time for it.
The target is:

> **For every system I own, I can debug it at 03:00 without AI.**

That is achievable inside delivery work, it is measurable, and it is the thing that converts
into being depended on — which is the actual senior threshold, not shipping volume.

## Which mode

| Situation | Mode |
|---|---|
| Work you want to come out of understanding | `/pair` — the default, so nothing to type on a fresh session; type it to switch back after `/solve` |
| Hard deadline, delivery is the only goal | `/solve` |
| Incident, on-call, production impact now | `/solve` |
| Work you already do fluently, where learning ROI is low | `/solve` — you decide this, no config does |
| No delivery pressure, closing a known gap | `/study` |
| Weekly, or after a rollout | `/debt` |

`pair` is the default: a fresh session with no command typed is already in it (as `plan:pair`). All three modes
are also explicit commands, switchable in any direction, any number of times, mid-task — the
last one typed wins, and it overrides the protocol text of whichever mode came before it in the
session. Overriding to `solve` is one word and is counted, not judged. A high override count
during a crunch is information, not failure.

## Which phase

Every session is also in a phase. The mode says who types; the phase says what is frozen.
`/phase` keeps the mode, and the mode commands keep the phase.

| Situation | Phase |
|---|---|
| Starting a change: investigating, asking, writing `REQUIREMENTS.md` and `PLAN.md` | `plan` — the default, nothing to type |
| The acceptance checks are agreed and the first test is next | `/phase implement` |
| Implementation shows the spec is wrong (a threshold, a missed case) | `/phase plan`, fix the spec, `/phase implement` again |
| A one-line fix or a typo, no spec needed | stay in `plan` — it freezes nothing |
| Incident under `/solve` | either — there is no spec to freeze |

In `implement` the spec (`.requirements/**` except `PLAN.md`) and design docs are frozen in
every mode, `solve` included: the point is that an implementing agent cannot change the
contract to make its own tests pass. When it hits a wrong spec it stops and says why; going
back is your call, never mine. `PLAN.md` stays writable so progress can be ticked.

What each mode means inside a phase:

| Phase | `pair` | `solve` | `study` |
|---|---|---|---|
| `plan` | One question at a time; you write the THEN of each acceptance check; I write the rest of the spec and plan as agreed scaffolding | I draft the spec and plan from your answers; you accept or refine | I quiz you on the problem; nothing is written |
| `implement` | You type the load-bearing lines, including test assertions; I write scaffolding | I write everything | No code |

Typing `/phase implement` is the moment to reread the THENs and the Verification commands:
after it, changing them costs a deliberate step back.

Spec conventions the tooling reads:

- `PLAN.md` steps are checkboxes (`- [ ]` / `- [x]`), ticked as each step is verified.
- Each Verification line names its checks and either a command run from the repo root
  (`` - AC-1, AC-2: `terraform test` ``, exit 0 = pass) or `- AC-3: manual — what to check`.

Before pushing, `~/.claude/hooks/spec-check.sh` shows which checks pass, which are manual and
which have no verification. Run `spec-check.sh install` once in a repo to make that a local
`pre-push` hook, plus a `commit-msg` hook that keeps `AC-n` IDs and `.requirements/` paths out
of shared history.

## How `pair` gates writes

In `pair`, **every** write is locked. No file type is special and nothing about your current
skills is stored anywhere. The sequence:

1. Constraints, then option names, then your prediction, then the delta.
2. We agree the split — which lines carry the mechanism (yours) and which are scaffolding (mine).
3. I unlock each agreed scaffolding file by name and write only those.
4. The load-bearing lines stay locked. I describe them; you type them.

Every unlock is a visible line in the transcript, and that visibility is the check: if I quietly
unlock everything to move faster, you see it happen. The lock list is per session.

The trade worth knowing: `pair` now taxes work you are already fluent at, because the system no
longer guesses which is which. That is the price of never maintaining a list — and the answer
when the tax is not worth it is one word, `/solve`.

## The three ownership questions

They need no implementation knowledge, and they run on systems thinking — the strength, not the
gap. Ask them of any change, including one AI wrote entirely:

1. **How does this fail in production?**
2. **How would I see it fail** — which signal, which dashboard, which log line?
3. **What would I check first?**

A change you can answer these for is a change you own. A change you cannot is a change you
are merely credited with. `/pair` asks them automatically; ask them yourself in `/solve`.

## Decisions, not derivations

Euclid works because every step is checkable **without trusting the author**. A reasoning
trace from an AI is not that — it is a plausible reconstruction produced alongside the answer,
not a log of how the answer was reached. Asking for "the options you considered" will reliably
produce three options whether or not three were ever weighed. The format manufactures rigor.

So take the half of Euclid that is real and refuse the half that is not:

| Ask for | Because |
|---|---|
| **The constraints** (the axioms) | Facts about your system. You can verify them yourself. |
| **The named alternatives** | They exist in the domain independently of the AI. Checkable. |
| **Which constraint eliminated which option** | The transferable part — it generalises to the next system. |
| ~~How the AI arrived at it~~ | Unverifiable by either of you. Persuasive and possibly fiction. |

And invert the direction: in `/pair` you get the constraints and the option *names*, then you
say which one wins and why, and only then the answer. Receiving an excellent rationale is
still reading an explanation — the most satisfying form of passive consumption, and the one
that already failed you once on a routing change you studied for a full day.

In `/solve` the decisions are logged instead of discussed, so the recall pass and `/debt` can
quiz you on them later without costing delivery time now.

## Output shape

Reading is a bottleneck, so each mode shapes answers differently. The rule is not a word budget -
a length limit attacks the constraints and alternatives first, which is exactly the content worth
keeping. Instead it names what to cut and what is protected.

**Cut in every mode:** preamble, restating your question, narrating what is about to happen,
hedging paragraphs, recaps of what you just read, closing summaries that repeat the body.

**Protected in every mode:** constraints, alternatives, which constraint decided it, failure
modes, anything unverified.

**Answer first, everywhere.** Conclusion in the first lines, support beneath, detail below - so
reading is self-terminating and you stop when you have what you need, rather than reading to the
end to discover whether you needed to.

Per mode:

| Mode | Shape |
|---|---|
| `/solve` | Outcome in the opening sentence. If it runs long, the first three lines must be enough to act on. Command or diff over prose about a command or diff. |
| `/pair` | Short by design - long output makes you skim, and skimming feels like understanding. Delta capped at six lines, one per rejected option. Questions offer a choice plus one line of why, never an open essay, because keystrokes are expensive for you. |
| `/study` | A diagnostic rather than a setting: you should be producing most of the text. If Claude has written more than you across the last few exchanges, it says so and hands back. |

**Known limitation:** this is the only part of the system with no mechanical enforcement. No hook
can measure output. It lives in the banner, which is re-injected every turn - the best available
defence, but not the hard stop the write lock is. If answers start bloating, say so; that is
faster than any rule.

## Using this in the Claude.ai chat UI

Slash commands do not exist there. Two options: make a Project per mode with the text below
as its custom instructions, or keep these as paste-able first lines.

**pair**
> Before you answer: this is something I want to come out of actually understanding, not just
> shipping. First state the constraints the solution must satisfy. Then name the two
> to four real alternatives — names only, no verdict — and ask me which one wins and which
> constraint kills the others. Wait for my answer. Then tell me where I was wrong, and give me
> only the load-bearing lines to write myself. Do not narrate how you reached the answer; give
> me constraints and alternatives I can check. Finish by asking me how it fails in prod, how I
> would see it, and what I would check first.

**solve**
> Speed mode. Full delegation, terse, no teaching and no commentary about learning. Decide
> routine choices yourself and say what you picked. Mark anything unverified in one clause.

**phases** (add to whichever mode text you use; the chat UI cannot freeze anything, so
this is a request, not a guarantee)
> Plan phase: help me write the spec first — As Is, To Be, numbered GIVEN/WHEN/THEN acceptance
> checks, and how each is verified. No code yet.

> Implement phase: the spec above is fixed. Do not change it to fit the code; if it is wrong,
> stop and tell me why, and I decide whether to go back.

**study**
> Learning only, no delivery. Do not write any code — I type everything. Quiz me before you
> tell me, one question at a time, and wait for my answer. Make me build the smallest thing
> that runs, then make me break it and diagnose it from the symptom.

## What the system does not do

Know the edges, so you are not surprised by them:

- The Bash guard is a **heuristic**. It catches `>`, `>>`, `tee` and `sed -i` aimed at a
  locked path. It will not catch every exotic way to write a file, and it can occasionally
  fire on a command that only reads. Overriding costs one word.
- Mode state is **per session** and lives in `~/.claude/ai-mode/sessions/<id>` as `phase:mode`.
  Two sessions can run different modes and `claude --resume` restores a session's mode. Files untouched for
  30 days are pruned; every prompt refreshes them, so the window counts from last activity.
- Nothing is logged automatically. Decisions and gaps are recorded deliberately, so an empty log means nothing was captured — not that nothing was delegated.
- The `pair` unlock list lives in `~/.claude/ai-mode/unlocked/<session-id>` and is pruned after
  30 days without activity. Deleting it re-locks everything in that session.
- Nothing is exempt from `pair` except `~/.claude/**`, `/tmp/claude-*` and `.git/` — minus the
  guard's own hooks and mode skills, which follow the active mode.
- Freezes see only what the guard sees: Write/Edit, Bash redirects, `tee` and `sed -i`. A CLI
  tool that writes files itself is not inspected. Paths outside a git repository are never
  frozen.
- Only you switch modes and phases. The prompt hook applies `/solve`, `/pair`, `/study`, `/phase`; the guard denies
  the agent running `mode-set.sh` or writing `~/.claude/ai-mode/` in every mode. A switch that
  gets past it anyway is restored at the next prompt, flagged as `[AI-MODE ALERT]`, and counted
  under "switches not made by the user" in `/debt`.

## Tuning

- `spec-check.sh install` / `uninstall` per repo; skipping a hook once is `git push --no-verify`,
  which only you can run.

- `~/.claude/ai-mode/guard.conf` — the never-guarded paths, what counts as a document, and the
  phase path classes (`CLASS_PLAN`, `CLASS_SPEC`, `CLASS_DESIGN`). Per repo, without committing
  anything: `git config --local ai-modes.spec "specs/**"`.
  Deliberately contains no list of technologies or skill areas: which work deserves the tax is
  your call, made by choosing a mode, and a stored list would rot as you improve.
- Debt log: `~/.claude/ai-mode/debt.md` (TSV: date, session, kind, tag, text, why) where
  `kind` is `decision` (why X over Y) or `gap` (asked, could not answer). Written by
  `hooks/debt.sh add`; read by `hooks/debt.sh report`. Safe to prune.
- Mode history: `~/.claude/ai-mode/events.tsv`, with a source column (`user`, `direct`, `revert`).
- **Switch the whole thing off:** delete the `hooks` block from `~/.claude/settings.json`.
- **Fail-open safety.** Both hooks are launched through `hooks/safe-run.sh`, which syntax-checks
  the target script and exits 0 if it does not parse. Without this, one typo in a hook breaks
  every Write, Edit and Bash call in every session — and repairing it needs exactly those tools,
  so the failure is unrecoverable from inside Claude Code. The wrapper turns that into
  "enforcement silently off", which is the right direction for a guard you cannot fix while it
  is broken. Keep `safe-run.sh` tiny and leave it alone; it is the one file with no safety net.
  The slash commands keep working; only the enforcement stops.
