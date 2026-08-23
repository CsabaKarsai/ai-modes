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

**Decision half**

1. **Constraints** — what the solution must satisfy, max six lines, no code. These are facts
   about your system that you can verify independently.
2. **Options — names only.** Two to four real alternatives, no verdict, no hints. An explicit
   anti-confabulation rule applies: if only one sane approach exists, say so rather than padding
   the list. A fabricated option set is worse than none, because it is persuasive and wrong.
3. **You predict** — which option wins and which constraint kills each of the others. Claude
   stops and waits.
4. **Delta** — the actual choice, the deciding constraint, one line per rejected option, and
   where your model was wrong. The gap is the lesson.

**Implementation half**

5. **Split** — Claude names the load-bearing lines: the smallest set that, if deleted, breaks
   the mechanism. Typically 10–20% of the change. Not imports, boilerplate, test tables or
   plumbing.
6. **You type those lines.** Claude unlocks and writes only the files you agreed are scaffolding.
7. **Failure interrogation** — Claude asks *you*: how does this fail in production, how would
   you see it fail, what would you check first.
8. **The 03:00 check** — three questions you would need to answer on-call with this change
   broken. Anything you cannot answer is logged as a gap. This is the acceptance test, embedded
   in the mode rather than bolted on as a separate review gate.

### solve — speed first

A deliberate trade of learning for speed, which under a deadline or an incident is usually the
correct call. No lessons, no quizzes, no commentary about the trade. Answers are shaped so the
first three lines are enough to act on.

Two things still happen in the background: every file written is logged automatically, and
Claude records each real decision fork as it is made — "chose X over Y" plus the constraint that
decided it. When the work finishes, it offers a recall pass once and accepts a no.

### study — learning only

No delivery goal. Claude cannot write code in this mode at all; only documents. One target per
session, taken from the debt log. Shape: why the mechanism exists, predict how it works, mark
the delta, build the smallest thing that runs by hand, **break it deliberately and diagnose from
the symptom**, then explain it back without looking.

The break-and-diagnose step is the closest daylight rehearsal of on-call debugging, with nothing
at stake.

### debt — the mirror

Groups the log into themes, ranks the top targets by how central each is to a system you
actually own, and states the numbers flat: decisions recorded versus files touched, and the
pair-to-solve ratio. It warns explicitly when files were delegated but no decisions were
recorded, since that means the reasoning went uncaptured.

## How to use it

- **Do nothing and you are in `pair`.** The absence of session state *is* the default.
- **Switch freely**, any direction, any number of times, mid-task. The last command typed wins
  and explicitly supersedes the protocol text of whichever mode preceded it in the session.
- **Overriding is one word.** Going `pair` → `solve` is counted and shown at the moment it
  happens. Switching back is not counted — reverting to the default is not a failure.
- A high override count during a crunch is information, not a verdict.

A typical task in `pair`: constraints and options arrive, you predict, you get the delta, you
agree the split, you type the mechanism while scaffolding is written around you, then you answer
the failure and 03:00 questions. When the clock wins instead, type `/solve` and stop thinking
about learning; take the recall pass afterwards if you have ten minutes.

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

Symlinks the skills, hooks and playbook into `~/.claude`, copies `ai-mode/guard.conf` if absent,
and merges the hooks block into `settings.json` without touching your other settings. Anything
replaced is backed up under `~/.claude/backups/`. Set `CLAUDE_DIR` to install elsewhere.

One manual step remains: append `claude/CLAUDE-snippet.md` to your `~/.claude/CLAUDE.md`, so the
rules apply in sessions where no mode command was typed.

`./uninstall.sh` removes the symlinks and the hooks block, leaving your data alone.

Everything is `$HOME`-relative — no path in this repo assumes a particular username.

## Implementation

Everything installs under `~/.claude/`. No project files are touched, so the setup travels with
you across repositories.

### Files

| Path | Purpose |
| --- | --- |
| `skills/{pair,solve,study,debt}/SKILL.md` | The four commands. Each is a skill with `disable-model-invocation: true`, so only you can trigger it. |
| `hooks/safe-run.sh` | Fail-open wrapper that launches the other two hooks. See below. |
| `hooks/mode-set.sh` | Writes the per-session mode, records the switch, prints the running override count. |
| `hooks/mode-guard.sh` | `PreToolUse` enforcement and file logging. |
| `hooks/mode-banner.sh` | `UserPromptSubmit` injection of the active mode. |
| `hooks/pair-unlock.sh` | Marks one path as agreed scaffolding, writable in `pair`. |
| `hooks/debt-add.sh` | Records a decision or a gap. |
| `hooks/debt-report.sh` | Compact summary consumed by `/debt` and `/study`. |
| `ai-mode/guard.conf` | Only the never-guarded paths and what counts as a document. Deliberately contains no technology list. |
| `ai-mode/sessions/<session-id>` | Active mode. Absent file means `pair`. |
| `ai-mode/unlocked/<session-id>` | Paths unlocked as scaffolding in this session. |
| `ai-mode/debt.md` | TSV: date, session, kind (`decision` / `gap` / `file`), tag, text, why. |
| `ai-mode/events.tsv` | Mode-switch history. |
| `AI-PLAYBOOK.md` | The judgment half: which mode when, and paste-able equivalents for the claude.ai chat UI, where slash commands do not exist. |
| `CLAUDE.md` | A short section naming the modes, so the rules apply even in a session where no command was typed. |

Runtime state under `ai-mode/` — `sessions/`, `unlocked/`, `debt.md`, `events.tsv` — is
gitignored. It is personal data and may reference internal systems.

### How the three mechanisms fit together

1. **State** — each mode skill runs `mode-set.sh` through an injected shell command in its body,
   writing one word to a file keyed by `CLAUDE_CODE_SESSION_ID`. That variable matches the
   `session_id` hooks receive, so state is per session and concurrent sessions can hold
   different modes.
2. **Enforcement** — a `PreToolUse` hook on `Write|Edit|NotebookEdit|Bash` returns a `deny`
   decision with a reason the model reads. It also inspects Bash commands for actual write
   targets, so redirects and in-place edits cannot route around the lock.
3. **Anti-drift** — a `UserPromptSubmit` hook prints the active mode and its rules on *every*
   turn, and that output is injected into context. This is what stops a long session from
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
- **Unlocking is self-declared.** Claude decides what counts as scaffolding. The check is
  visibility: every unlock is a line in the transcript, so unlocking broadly to move faster is
  plainly visible.
- **Editing `mode-guard.sh` while in `pair` is self-blocking**, because guard source necessarily
  contains redirect syntax and trips its own detector. Use `/solve`.
- **Two open defects:** relative write targets are resolved against the session working
  directory rather than the directory after a `cd` inside the same command (produces a false
  deny, and a wrong path in the log); and a YAML folded block scalar (`>-`) is misread as a
  redirect.

## Licence

MIT. See `LICENSE`.
