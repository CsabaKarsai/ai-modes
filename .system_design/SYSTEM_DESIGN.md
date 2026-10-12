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
`implement:pair`. A session without a phase behaves exactly as today (no freezes).

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

Path classes (defaults, overridable in `guard.conf`):

| Class | Default patterns, relative to the repo root | Owned by |
|---|---|---|
| spec | `openspec/**` | `spec` |
| design | `**/*.c4`, `**/*.likec4`, `docs/adr/**`, `.system_design/**` | `design` |
| tasks | `openspec/changes/*/tasks.md` (overrides the spec class) | `tasks` |

Proposed freeze matrix — a phase freezes the classes owned by the phases before it:

| Phase | Frozen |
|---|---|
| `grill`, `spec` | — |
| `design` | spec |
| `tasks` | spec, design |
| `implement` | spec, design (tasks stays writable for ticking items off) |
| `verify` | spec, design |

Known gap: CLI tools that write files themselves (`openspec archive`) are not seen by the
guard, which inspects only Write/Edit and Bash redirects. Archiving in `verify` therefore
still works; it is also an unguarded route around the spec freeze.

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
| Phase lives in the session, not per change | Per-change state, change ID in `/phase` | Keeps the model light; interrupting and resuming sessions needs nothing beyond `--resume`. Cost: freezes cover the whole repo within a session. |
| Freezes apply in every mode | Freezes only in pair | Drift protection is about the contract, not about learning; solve is where drift is most likely. |
| Phase switched by the prompt hook | Agent-run script, user-only skill | Same user-only guarantee as modes (see section 3). |
| Patterns relative to the repo root | Absolute paths, session working directory | Works in single checkouts and worktrees alike (section 4.4). |
| ai-modes ignores git branches and worktrees | Built-in worktree management | Worktrees are a git habit before a session starts; measured need was about 5 days in 4.5 months, all in one repo. |

## 5. Open questions

1. **Fresh-session default:** plain `pair` without a phase (freezes off) or `spec:pair`?
2. **Freeze matrix and patterns:** confirm the proposed defaults in 4.3, especially the ADR
   location and whether `grill` or `spec` should freeze code.
