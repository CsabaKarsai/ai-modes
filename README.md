# ai-modes

Switchable modes for Claude Code that decide **who does the work**, enforced by hooks rather
than by good intentions.

## Goal

A coding agent will happily produce work you cannot maintain. The failure is quiet: the change
is correct, it passes review, it ships — and the person whose name is on it could not reproduce
or debug it unaided. Delivery velocity and skill growth decouple, and only one of the two is
visible to anyone.

**The premise.** AI does not erase skill. It removes the conditions under which skill forms —
retrieval, prediction that turns out wrong, productive struggle. So the goal is not "use AI
less". It is to protect a few specific moments per task and delegate everything else at full
speed.

This setup makes that trade **explicit and per-session**, and enforces it mechanically rather
than by good intentions — because under deadline pressure, intentions lose.

Two design decisions are worth stating up front, because they are what keep the system from
rotting:

- **No stored skill profile.** The system holds no list of languages, frameworks or "weak
  areas". Such a list encodes a snapshot of a person that goes stale the moment they improve,
  and it lets the tool decide what is worth learning. Which work deserves the learning tax is
  decided by *which mode you pick*.
- **Constraints and alternatives, never a reasoning narrative.** An LLM's account of "how I
  arrived at this" is a post-hoc reconstruction, not a log, and nobody can verify it. The modes
  ask for the parts that *are* checkable: the constraints the solution must satisfy, the
  alternatives that genuinely existed, and which constraint eliminated which option.

## The modes

| Mode | Command | Use when | What happens |
| --- | --- | --- | --- |
| **pair** *(default)* | `/pair` | Work you want to come out of actually understanding | All writes locked. Decision half runs first, then you type the load-bearing lines while Claude writes agreed scaffolding. |
| **solve** | `/solve` | Hard deadline, or a live incident | Full delegation, zero friction, no teaching. Decisions are logged silently. One recall offer at the end. |
| **study** | `/study` | No delivery goal; closing a known gap | Claude writes no code at all — only notes. Quiz-first, hands-on, deliberately break it and diagnose. |
| **debt** | `/debt` | Periodically, or after a rollout | Reports accumulated decisions and gaps, ranked, plus mode-usage numbers. |

### pair — the default

A fresh session with no command typed is already in `pair`. Every write is locked; no file type
is special. The protocol has two halves:

**Stage 1 — decide together**

- **Constraints** — what the solution must satisfy, max six lines, no code. Facts about your
  system that you can verify independently.
- **Options, names only** — two to four real alternatives, no verdict, no hints. An explicit
  anti-confabulation rule applies: if only one sane approach exists, say so rather than padding
  the list. A fabricated option set is worse than none, because it is persuasive and wrong.
- **Your prediction** — which option wins and which constraint kills each of the others. Claude
  stops and waits.
- **Delta** — the actual choice, the deciding constraint, one line per rejected option, and
  where your model was wrong. The gap is the lesson.

**Stage 2 — build and interrogate**

- **Split** — Claude names the load-bearing lines: the smallest set that, if deleted, breaks the
  mechanism. Typically 10–20% of the change. Not imports, boilerplate, test tables or plumbing.
- **You type the mechanism; Claude writes the scaffolding**, unlocking only the files you agreed
  are its to write.
- **Failure interrogation** — Claude asks *you*: how does this fail in production, how would you
  see it fail, what would you check first.
- **The 03:00 check** — three questions you would need to answer on-call with this change
  broken. Anything you cannot answer is logged as a gap. This is the acceptance test, embedded
  in the mode rather than bolted on as a separate review gate.

### solve — speed first

A deliberate trade of learning for speed, which under a deadline or an incident is usually the
correct call. No lessons, no quizzes, no commentary about the trade. Answers are shaped so the
first three lines are enough to act on.

One thing still happens in the background: Claude records each real decision fork as it is made
— "chose X over Y" plus the constraint that decided it. When the work finishes, it offers a
recall pass once and accepts a no.

### study — learning only

No delivery goal. Claude cannot write code in this mode at all; only documents. One target per
session, taken from the debt log. Shape: why the mechanism exists, predict how it works, mark
the delta, build the smallest thing that runs by hand, **break it deliberately and diagnose from
the symptom**, then explain it back without looking.

The break-and-diagnose step is the closest daylight rehearsal of on-call debugging, with nothing
at stake.

### debt — the mirror

Groups the log into themes, ranks the top targets by how central each is to a system you
actually own, and states the numbers flat: the pair-to-solve ratio and the override count.
Nothing is logged automatically, so an empty log means nothing was captured — not that nothing
was delegated.

## How to use it

- **Do nothing and you are in `plan:pair`.** The absence of session state *is* the default.
- **Switch freely**, any direction, any number of times, mid-task. The last command typed wins
  and explicitly supersedes the protocol text of whichever mode preceded it in the session.
- **A switch does nothing but switch.** Claude answers with one line — `Switched to ai-mode
  <mode>. Waiting for instructions.` — and stops. It will not resume the previous task, answer
  an earlier question, or start work off the back of the mode command. `/debt` is the exception,
  because it is a report rather than a mode: it prints the report when you type it.
- **Overriding is one word.** Going `pair` → `solve` is counted and shown at the moment it
  happens. Switching back is not counted — reverting to the default is not a failure.
- A high override count during a crunch is information, not a verdict.

A typical task in `pair`: constraints and options arrive, you predict, you get the delta, you
agree the split, you type the mechanism while scaffolding is written around you, then you answer
the failure and 03:00 questions. When the clock wins instead, type `/solve` and stop thinking
about learning; take the recall pass afterwards if you have ten minutes.

### Phases: plan and implement

A session is always in a `phase:mode`; a fresh one is `plan:pair`. `/phase plan` or
`/phase implement` changes the phase and keeps the mode; `/solve`, `/pair` and `/study` change
the mode and keep the phase.

| Phase | Produces | Frozen |
| --- | --- | --- |
| `plan` | The local spec (`REQUIREMENTS.md`), `PLAN.md`, design decisions | nothing |
| `implement` | Tests and code; progress in `PLAN.md` | spec and design docs, in every mode |

The guard sees paths, not authorship, so what each mode means inside a phase is carried by the
per-turn banner:

| Phase | `pair` | `solve` | `study` |
| --- | --- | --- | --- |
| `plan` | One question at a time; you write the THEN of each acceptance check; Claude writes the rest of the spec and plan as agreed scaffolding | Claude drafts spec and plan from your answers; you accept or refine | Claude quizzes on the problem; writes nothing |
| `implement` | You type the load-bearing lines, including test assertions; Claude writes scaffolding | Claude writes everything | No code |

The freeze stops an implementing agent changing the contract to make its own tests pass. If
the spec turns out wrong, Claude stops and says why; only you go back, with `/phase plan`.

Paths are matched relative to the root of the git repo containing the file, so a checkout, a
worktree and another repository behave the same; outside a repo nothing is frozen. A path takes
the first class that matches:

| Class | Default patterns (`guard.conf`) | Frozen in |
| --- | --- | --- |
| plan | `.requirements/*/PLAN.md` | never |
| spec | `.requirements/**` | `implement` |
| design | `.system_design/SYSTEM_DESIGN.md docs/adr/**` | `implement` |

Override per repo without committing anything: `git config --local ai-modes.spec "specs/**"`
(also `ai-modes.plan`, `ai-modes.design`). Add `.requirements/` to your global git ignore.

### Orthogonal to Claude Code permission modes

These are two independent axes and neither reads the other:

- **Permission mode** answers *"must Claude ask before acting?"*
- **AI mode** answers *"who does the work?"*

`PreToolUse` hooks run *before* the permission check, so a mode denial wins over any permission
setting — a locked write is still blocked in `auto`.

| Permission mode | Combined with `pair` |
| --- | --- |
| Manual (`default`) | Works, but doubles the friction: the hook denies, then everything else prompts. |
| `auto` | **Best fit.** Free movement everywhere except the lock. |
| `plan` | Ideal for the decision half — no writes are possible at all, which is structurally what steps 1–4 need. |
| `bypassPermissions` | **Unverified.** The docs do not state whether hook denials are honoured. Do not rely on the lock here. |

Shift+Tab cycles the permission mode only; it never changes the AI mode. Two separate switches.

## Install

Requires `jq`.

```sh
git clone <this repo> ~/dev/ai-modes
cd ~/dev/ai-modes && ./install.sh
```

Symlinks the skills, hooks, playbook and `rules/*.md` into `~/.claude`, copies `ai-mode/guard.conf` if absent,
and merges the hooks block into `settings.json` without touching your other settings. Anything
replaced is backed up under `~/.claude/backups/`. Set `CLAUDE_DIR` to install elsewhere.

The modes section loads as a user-level rule (`~/.claude/rules/ai-modes.md`), so the rules apply in
sessions where no mode command was typed, and `~/.claude/CLAUDE.md` stays untouched. That matters
when another tool manages that file (at emnify: emnifai): a personal section inside it would show
up as a local edit on every sync.

`./uninstall.sh` removes the symlinks and the hooks block, leaving your data alone.

`tests/aimodes-test.sh` runs the hook tests from this checkout against a throwaway `HOME`; it
exits non-zero on any failure. Requires `jq`.

Everything is `$HOME`-relative — no path in this repo assumes a particular username.

## Implementation

Everything installs under `~/.claude/`. No project files are touched, so the setup travels with
you across repositories.

### Files

| Path | Purpose |
| --- | --- |
| `skills/{pair,solve,study,debt,phase}/SKILL.md` | The five commands. Each is a skill with `disable-model-invocation: true`, so only you can trigger it. |
| `hooks/safe-run.sh` | Fail-open wrapper that launches the other two hooks. See below. |
| `hooks/mode-set.sh` | Writes the per-session `phase:mode`, records the switch and who made it, prints the running override count. Run only by `mode-banner.sh`. |
| `hooks/mode-guard.sh` | `PreToolUse` enforcement, plus the user-only switch rule in every mode. |
| `hooks/mode-banner.sh` | `UserPromptSubmit`: applies `/solve`, `/pair`, `/study`, `/phase`, reverts switches you did not make, injects the active mode and phase. |
| `hooks/pair-unlock.sh` | Marks one path as agreed scaffolding, writable in `pair`. |
| `hooks/debt.sh` | `add` records a decision or a gap; `report` prints the summary used by `/debt` and `/study`. |
| `ai-mode/guard.conf` | The never-guarded paths, what counts as a document, and the phase path classes. Deliberately contains no technology list. |
| `ai-mode/sessions/<session-id>` | Active `phase:mode`. Absent file means `plan:pair`; a mode-only file from an older version reads as `plan:<mode>`. |
| `ai-mode/unlocked/<session-id>` | Paths unlocked as scaffolding in this session. |
| `ai-mode/debt.md` | TSV: date, session, kind (`decision` / `gap`), tag, text, why. |
| `ai-mode/events.tsv` | Mode-switch history: time, session, from, to, source (`user`, `direct` or `revert`; rows without a source predate it and count as `user`). |
| `AI-PLAYBOOK.md` | The judgment half: which mode when, and paste-able equivalents for the claude.ai chat UI, where slash commands do not exist. |
| `rules/ai-modes.md` | A short user-level rule naming the modes, so they apply even in a session where no command was typed. Loaded like `CLAUDE.md`, without editing it. |

Runtime state under `ai-mode/` — `sessions/`, `unlocked/`, `debt.md`, `events.tsv` — is
gitignored. It is personal data and may reference internal systems.

### How the three mechanisms fit together

1. **State** — the `UserPromptSubmit` hook sees `/solve`, `/pair`, `/study` or `/phase` in what
   you typed and runs `mode-set.sh`, writing `phase:mode` to a file keyed by the hook's
   `session_id`, so state is per session and concurrent sessions can hold different states. The switch lives in the
   hook, not in the skill, because that hook only fires on prompts you submit: a switch there
   is yours by construction. The skill body only confirms the switch in one line.
   - **User-only.** The guard denies the agent running `mode-set.sh` and writing anything under
     `~/.claude/ai-mode/`, in every mode, and the hooks and mode skills under `~/.claude/` follow
     the active mode instead of being exempt. `pair-unlock.sh` refuses them as scaffolding.
   - **Tamper check.** Every prompt compares the session file with the last switch you made,
     before applying a new one. A mismatch or an invalid value (an agent switch that got past
     the guard) is restored, alerted in the banner,
     logged as `revert` and counted by `/debt`.
2. **Enforcement** — a `PreToolUse` hook on `Write|Edit|NotebookEdit|Bash` returns a `deny`
   decision with a reason the model reads. It checks the phase freeze first, then the mode. It also inspects Bash commands for actual write
   targets, so redirects and in-place edits cannot route around the lock.
3. **Anti-drift** — a `UserPromptSubmit` hook prints the active mode and phase and their rules
   on *every* turn (`[AI-MODE: ...]` and `[AI-PHASE: ...]`), and that output is injected into
   Claude's context. It is an instruction to the model, not something shown in the chat. This is what stops a long session from
   sliding back into old behaviour, and it is why the default works in sessions where no skill
   was ever invoked.

Both hooks are registered in the `hooks` block of `~/.claude/settings.json`. Deleting that block
disables all enforcement; the slash commands keep working.

### Fail-open

Both hooks are launched through `safe-run.sh`, which syntax-checks the target script and exits 0
if it does not parse.

Without it, one typo in a hook breaks every Write, Edit and Bash call in every session — and
repairing it needs exactly those tools, so the failure is unrecoverable from inside Claude Code.
This is not hypothetical; it happened during development. The wrapper turns that into
"enforcement silently off", which is the right direction for a guard you cannot fix while it is
broken.

Keep `safe-run.sh` tiny and leave it alone. It is the one file with no safety net.

## Known limitations

- **Bash write detection is a heuristic.** It catches redirects, `tee` and in-place edits aimed
  at a locked path, but not every exotic way to write a file, and it can occasionally fire on a
  command that only reads. Overriding costs one word.
- **Output shape has no mechanical enforcement.** No hook can measure output length, so the
  answer-shaping rules live in the banner and will drift more than the write lock does.
- **Switch-only behaviour is prompt-level.** No hook can stop a model from talking, so the
  one-line switch reply is a strong instruction rather than a guarantee. The `mode: X -> Y`
  line from `mode-set.sh` is printed by the prompt hook; that is script output, and it is what
  keeps the override count visible.
- **Switch protection is a heuristic too.** The guard catches `mode-set.sh` in command position
  and writes to `~/.claude/ai-mode/` it can see. An exotic route (say, Python writing the state
  file) gets past it; the tamper check then restores your mode at the next prompt and logs it.
  Deleting the session file is not reverted, because it falls back to `plan:pair`, the safe
  direction.
- **Unlocking is self-declared.** Claude decides what counts as scaffolding. The check is
  visibility: every unlock is a line in the transcript, so unlocking broadly to move faster is
  plainly visible.
- **Editing `mode-guard.sh` while in `pair` is self-blocking**, because guard source necessarily
  contains redirect syntax and trips its own detector. Use `/solve`.
- **Freezes see only what the guard sees.** A CLI tool that writes files itself is not
  inspected, only Write/Edit and Bash redirects, `tee` and `sed -i`.
- **Two open defects:** relative write targets are resolved against the session working
  directory rather than the directory after a `cd` inside the same command (produces a false
  deny, and a wrong path in the log); and a YAML folded block scalar (`>-`) is misread as a
  redirect.

## Licence

MIT. See `LICENSE`.
