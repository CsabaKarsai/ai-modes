# ai-modes — System Design

Status: **As Built** for modes, switching and tamper detection (commit `c424978`);
**To Be** for phases and phase freezes (section 4 onward, not implemented yet).

Related: `README.md` (user guide), `claude/AI-PLAYBOOK.md` (which mode when).

## 1. Purpose

ai-modes decides **who writes what** in a Claude Code session and enforces it with hooks
rather than instructions. The To-Be extension adds **phases** so the same mechanism supports a
spec-driven development (SDD) flow: the user can choose, per phase, how much to write
themselves, and upstream artifacts (spec, architecture) cannot be changed by the agent once
work has moved past them.

Non-goals:
- No knowledge of git branches, worktrees or OpenSpec change IDs. ai-modes works the same in
  a single checkout and in any number of git worktrees.
- No deterministic spec or architecture verification. Scenario-ID checks and LikeC4
  validation belong to each project repo (git hooks, CI), not to ai-modes.
- No protection against a determined agent. The guard is a heuristic against drift; the
  tamper check makes bypasses visible and reverts them.

## 2. Components (As Built)

| Component | Kind | Responsibility |
|---|---|---|
| `hooks/mode-banner.sh` | `UserPromptSubmit` hook | Applies `/solve`, `/pair`, `/study` typed by the user; tamper check; refreshes state files; injects the active mode's rules into context every turn. |
| `hooks/mode-set.sh` | script | Writes the session state file and appends to `events.tsv`. Run only by the banner. |
| `hooks/mode-guard.sh` | `PreToolUse` hook on `Write\|Edit\|NotebookEdit\|Bash` | Denies writes the active mode does not allow; denies the agent switching modes or writing mode state, in every mode. |
| `hooks/pair-unlock.sh` | script (agent-callable) | Adds a path to the session's pair unlock list; refuses guard code and mode state. |
| `hooks/debt.sh` | script | Records decisions and gaps; reports them plus mode-switch statistics and their provenance. |
| `hooks/safe-run.sh` | wrapper | Fail-open: skips a hook script that does not parse. |
| `rules/ai-modes.md` | user-level rule | Names the modes in every session and states how they relate to the global `CLAUDE.md` workflow (modes decide who types; `/solve` is the workflow's explicit opt-out). |
| `rules/sdd-openspec.md` | user-level rule | How OpenSpec adds to the global workflow in repos with `openspec/` (section 6). |
| `skills/{pair,solve,study}` | user-only skills | Confirm a switch in one line and carry the mode's standing instructions. They do not switch. |

### State (`~/.claude/ai-mode/`)

| Path | Content |
|---|---|
| `sessions/<session-id>` | Active mode. Absent file = `pair`. |
| `unlocked/<session-id>` | Absolute paths unlocked as scaffolding in pair mode. |
| `events.tsv` | `time, session, from, to, source` with source `user`, `direct` or `revert`; 4-column legacy rows count as `user`. |
| `debt.md` | Decisions and gaps. |
| `guard.conf` | Exempt paths and document patterns (user-edited). |

## 3. Behaviour (As Built)

1. **Switching is user-only.** The banner hook fires only on prompts the user submits, so a
   switch it applies is user-made by construction. The guard denies the agent running the
   switch script (command position only; reading it stays allowed) and writing anything under
   `~/.claude/ai-mode/`, in every mode.
2. **Tamper check.** Every prompt compares the session file with the last user-made switch.
   A mismatch is restored, shown as `[AI-MODE ALERT]`, logged as `revert` and counted by
   `/debt`. A deleted session file is not restored: it falls back to `pair`, the safe
   direction.
3. **Session-scoped, resumable.** State is keyed by session ID. `claude --resume` keeps the
   ID, so a resumed session continues in its mode. `--fork-session` starts on the default
   (accepted). State files untouched for 30 days are pruned; every prompt refreshes them.
   Why 30 days: the longest observed session spanned 17.7 days (73 sessions measured).
4. **Guard code is not exempt.** `~/.claude/` is exempt tooling except the hooks and mode
   skills, which follow the active mode (locked in pair, editable in solve) so the agent cannot
   quietly rewrite its own guard.

## 4. Phases (To Be)

### 4.1 Model

Session state becomes the pair **`phase:mode`**, still one file per session, e.g.
`implement:pair`. A session is always in a full `phase:mode`; a mode without a phase or a phase
without a mode is not a valid state.

- **Default:** a fresh session (no state file) is `spec:pair`. `spec` freezes nothing, so a
  session that never types `/phase` behaves exactly like today's `pair`.
- **Legacy state:** a state file or `events.tsv` row holding only a mode (written before
  phases) is read as `spec:<mode>`, so running sessions keep their mode and gain no freezes.
- **Invalid values** (unknown phase or mode, missing half) are never written: the banner
  rejects the command and leaves the state unchanged; the tamper check treats an invalid file
  like any other mismatch and restores the last user-made state.

Phases, in SDD order:

| Phase | Produces |
|---|---|
| `grill` | Clarified intent (grill-with-docs); glossary or ADR updates |
| `spec` | OpenSpec change: proposal and delta scenarios with scenario IDs |
| `design` | LikeC4 model changes and ADRs |
| `tasks` | `tasks.md` |
| `implement` | Tests and code (red → green) |
| `verify` | Checker run, live checks, review fixes, archive |

**Two independent layers decide every write:**

| Layer | Question | Source | Applies in |
|---|---|---|---|
| Freeze | May this path be touched at all in this phase? | The phase | Every mode, including solve |
| Mode | Who writes the paths that are not frozen? | The mode (unchanged rules) | As today |

### 4.2 Switching

- `/phase <name>` changes the phase and keeps the mode; `/solve`, `/pair`, `/study` change the
  mode and keep the phase. Any combination, in any direction, any number of times.
- Applied by the banner hook from the typed prompt, exactly like modes, so phase changes are
  user-only and covered by the guard rule and the tamper check. Logged in `events.tsv`.
- Going back (e.g. `implement` → `spec` when the spec turns out wrong) is just `/phase spec`.
  Only the user can do it; the agent may suggest it.

### 4.3 Freezes

A freeze protects an upstream artifact from being changed by the agent once work has moved
past the phase that owns it. That is the SDD failure mode it targets: an implementing agent
rewriting the contract to make its own tests pass.

Path classes (defaults, overridable in `guard.conf`), matched relative to the repo root
(section 4.4). A path belongs to the first class that matches, in the order tasks, spec,
design, code:

| Class | Default patterns | Owned by |
|---|---|---|
| tasks | `openspec/changes/*/tasks.md`, `.system_design/steps/**` | `tasks` |
| spec | `openspec/**`, `.requirements/**` | `spec` |
| design | `**/*.c4`, `**/*.likec4`, `docs/adr/**`, `.system_design/SYSTEM_DESIGN.md` | `design` |
| code | every other path, except `docs/**` and `**/*.md` | `implement` |

Freeze matrix:

| Phase | Frozen | Writable |
|---|---|---|
| `grill` | code\* | spec, design, tasks, docs |
| `spec` | code\* | spec, design, tasks, docs |
| `design` | spec, code\* | design, tasks, docs |
| `tasks` | spec, design | tasks, code, docs |
| `implement` | spec, design | tasks, code, docs |
| `verify` | spec, design | tasks, code, docs; `openspec archive` (below) |

\* The code freeze applies only in an **SDD repo**: one whose root contains `openspec/`. In any
other repo the early phases freeze no code, so the default `spec:pair` behaves like today's
`pair` there.

What is frozen and why:
- **spec, design** are the contract the implementation is measured against. Freezing them
  after their phase stops the failure mode SDD targets: an implementing agent changing the
  contract to make its own tests pass. When review shows the contract is wrong, the user goes
  back with `/phase spec` or `/phase design`; the move is logged like any switch.
- **tasks** (`.system_design/steps/`, and `tasks.md`, which only points to them) is the plan
  and progress log, not contract. It stays writable in every phase so the agent can append
  implementation notes.
  CLAUDE.md's "only add step files, never edit another" stays a text rule; the guard cannot
  tell an append from an edit.
- **code** in the early phases of an SDD repo keeps implementation from starting before the
  spec and design exist. Code is defined by exclusion (everything not listed above, `docs/**`
  and `**/*.md`) so it works in any repo layout without per-repo configuration.
- `.system_design/SYSTEM_DESIGN.md` is frozen from `tasks` on. CLAUDE.md's "update the design
  before implementing" therefore turns into a visible stop: the agent reports the design gap
  and the user decides on `/phase design`.

**`openspec archive` in `verify`.** Archive validates the change, merges the already-accepted
delta into `openspec/specs/` and moves the change to `openspec/changes/archive/<date>-<id>/`.
Its output is fully determined by the frozen delta, so it cannot be used to rewrite the
contract, and it is the intended last step of a change. It is therefore allowed in `verify`
(the guard does not inspect it anyway; this makes that deliberate). The guard denies it with
`--no-validate`, which would skip OpenSpec's own validation. Archive runs in the same PR as
the code, so the living-spec diff is reviewed with the change and CI's `openspec validate
--strict` and scenario-ID checker run on the result. Hand edits to the spec in `verify` stay
blocked.

Remaining gap: other CLI tools that write files themselves are not seen by the guard, which
inspects only Write/Edit and Bash redirects.

### 4.4 Repo-root rule

Freeze patterns are matched against the target file's path **relative to the root of the git
repository containing that file** (`git -C <file's directory> rev-parse --show-toplevel`),
never against an absolute repository path and never against the session's working directory.

Why: the same rules must hold in a plain checkout, in any git worktree (each has its own root
folder) and when a session edits a file in another repository. A file outside any git
repository has no freeze.

### 4.5 Mode × phase guidance

The guard cannot tell "agent drafts, user accepts" from "user types it": it sees paths, not
authorship. So what each mode means inside a phase is carried by the banner text, which
becomes phase-aware:

| Phase | `pair` | `solve` | `study` |
|---|---|---|---|
| grill | One question at a time, depth first | Fewer, batched questions | Quiz on consequences |
| spec | User writes the scenarios; agent validates | Agent drafts from the grill answers; user accepts or refines | Agent explains the spec, writes nothing |
| design | User decides and edits the model and ADRs | Agent drafts; user accepts | Quiz on the model |
| tasks | Agent writes (scaffolding) | Agent writes | — |
| implement | User types the THEN assertions and core code | Agent writes everything; PR says "assertions not human-written" | No code |
| verify | Agent runs, user reads results | Agent runs and summarises | — |

### 4.6 Key decisions

| Decision | Alternatives | Why this one |
|---|---|---|
| Always a full `phase:mode`, default `spec:pair` | Mode-only sessions with freezes off; no default phase | User decision: one state shape, nothing half-set. `spec` freezes nothing, so the default changes no existing behaviour. |
| Phase lives in the session, not per change | Per-change state, change ID in `/phase` | Keeps the model light; interrupting and resuming sessions needs nothing beyond `--resume`. Cost: freezes cover the whole repo within a session. |
| `tasks.md` and step files never frozen | Freeze with the design | They are a progress log, not contract; CLAUDE.md requires appending notes after each step. |
| `openspec archive` allowed in `verify` (not `--no-validate`) | Unfreeze spec in verify; block archive | Archive only applies the frozen, accepted delta; it runs in the PR so the spec diff is reviewed and CI validates it. |
| Code freeze in early phases, SDD repos only | No code freeze; code freeze everywhere | Stops implementation before spec and design exist, without blocking the default `spec:pair` in repos that do not use OpenSpec. |
| Code defined by exclusion | Per-repo code patterns | Works in any layout with no per-repo config to maintain. |
| Freezes apply in every mode | Freezes only in pair | Drift protection is about the contract, not about learning; solve is where drift is most likely. |
| Phase switched by the prompt hook | Agent-run script, user-only skill | Same user-only guarantee as modes (see section 3). |
| Patterns relative to the repo root | Absolute paths, session working directory | Works in single checkouts and worktrees alike (section 4.4). |
| ai-modes ignores git branches and worktrees | Built-in worktree management | Worktrees are a git habit before a session starts; measured need was about 5 days in 4.5 months, all in one repo. |

## 5. Open questions

None. Confirmed with the user: always `phase:mode`, default `spec:pair`, the path classes and
freeze matrix in 4.3, ADRs in `docs/adr/`.

## 6. Relationship to the global `CLAUDE.md`

The global `~/.claude/CLAUDE.md` is the emnify baseline, installed and synced by emnifai, and
the `code-reviewer` and `system-design-reviewer` agents come with it. Neither can be changed
here. Three layers therefore apply, each owning one concern:

| Layer | Owns | Where |
|---|---|---|
| emnify baseline | The process: `REQUIREMENTS.md`, `SYSTEM_DESIGN.md`, steps, TDD, reviews | `~/.claude/CLAUDE.md`, agents (emnifai) |
| ai-modes | Who types; which artifacts are frozen in which phase | hooks, skills, `rules/ai-modes.md` |
| SDD (OpenSpec) | Behaviour scenarios with IDs and the living spec, in repos with `openspec/` | `rules/sdd-openspec.md` |

**Additive only.** User-level rules load with the same priority as `CLAUDE.md`; when they
conflict, Claude may follow either. So the personal rules never contradict the baseline: they
add to it, or use the opt-out it grants itself ("unless the user explicitly opts out").

How each overlap is settled:

| Overlap | Resolution |
|---|---|
| Baseline's per-test and per-change review loop, incident ceremony vs `solve` | `/solve` is the user's explicit opt-out the baseline allows. Stated in the rule, the solve skill and the per-turn banner. |
| Baseline "implement tests first" vs `pair` | Not a conflict: the baseline says what, the mode says who. In `pair` the user types the test assertions. |
| Baseline "update `SYSTEM_DESIGN.md` first" vs the `implement` freeze | Not a conflict: the freeze enforces the baseline's design-first order. |
| `REQUIREMENTS.md` and steps vs OpenSpec delta and `tasks.md` | Baseline artifacts stay; `code-reviewer` stops without `REQUIREMENTS.md`. OpenSpec adds only scenarios with IDs and the living spec. `REQUIREMENTS.md` acceptance criteria list scenario IDs and link the delta; `tasks.md` points to the steps. |
| Personal sections inside the managed `CLAUDE.md` | Moved to user-level rules symlinked from this repo, so `CLAUDE.md` equals the baseline and emnifai sync sees no local edits. |

Decisions:

| Decision | Alternatives | Why this one |
|---|---|---|
| Baseline plus thin OpenSpec | Drop OpenSpec (IDs on `REQUIREMENTS.md` criteria); both in full | Keeps the reviewer and emnifai steps working, keeps a living spec, writes nothing twice. |
| `/solve` as the baseline's explicit opt-out | Full baseline ceremony in solve | Uses the baseline's own exception, so the rule adds rather than contradicts. |
| User-level rules, not an `@import` in `CLAUDE.md` | Import line, section in `CLAUDE.md` | Any edit to the managed file shows up on every emnifai sync. |
