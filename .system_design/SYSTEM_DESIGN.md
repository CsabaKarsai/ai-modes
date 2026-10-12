# ai-modes — System Design

Status: **As Built**, including phases and phase freezes (section 4).

Related: `README.md` (user guide), `claude/AI-PLAYBOOK.md` (which mode when).

## 1. Purpose

ai-modes decides **who writes what** in a Claude Code session and enforces it with hooks
rather than instructions. The To-Be extension adds **phases** so the same mechanism supports a
light spec-driven flow: the user chooses, per phase, how much to write themselves, and the
spec cannot be changed by the agent once implementation has started.

Non-goals:
- No knowledge of git branches, worktrees or change IDs. ai-modes works the same in a single
  checkout and in any number of git worktrees.
- No spec verification. Proving acceptance checks is the change workflow's job (section 6).
- Nothing in shared repos. ai-modes and everything it reads or writes stay on this machine;
  colleagues use other tools.
- No protection against a determined agent. The guard is a heuristic against drift; the
  tamper check makes bypasses visible and reverts them.

## 2. Components (As Built)

| Component | Kind | Responsibility |
|---|---|---|
| `hooks/mode-banner.sh` | `UserPromptSubmit` hook | Applies `/solve`, `/pair`, `/study`, `/phase` typed by the user; tamper check; refreshes state files; injects the active mode's and phase's rules into context every turn. |
| `hooks/mode-set.sh` | script | Writes the session state file and appends to `events.tsv`. Run only by the banner. |
| `hooks/mode-guard.sh` | `PreToolUse` hook on `Write\|Edit\|NotebookEdit\|Bash` | Denies writes to paths the active phase freezes and writes the active mode does not allow; denies the agent switching modes or writing mode state, in every mode. |
| `hooks/pair-unlock.sh` | script (agent-callable) | Adds a path to the session's pair unlock list; refuses guard code and mode state. |
| `hooks/debt.sh` | script | Records decisions and gaps; reports them plus mode-switch statistics and their provenance. |
| `hooks/spec-check.sh` | script, optional git hooks | Checks that every acceptance check of the newest local spec has a verification command that passes; installed per repo as local `pre-push` and `commit-msg` hooks (section 4.7). |
| `hooks/safe-run.sh` | wrapper | Fail-open: skips a hook script that does not parse. |
| `rules/ai-modes.md` | user-level rule | Names the modes in every session and states how they relate to the change workflow in `~/.claude/CLAUDE.md` (modes decide who types; `/solve` is its explicit opt-out). |
| `skills/{pair,solve,study,phase}` | user-only skills | Confirm a switch in one line and carry the mode's or phase's standing instructions. They do not switch. |

### State (`~/.claude/ai-mode/`)

| Path | Content |
|---|---|
| `sessions/<session-id>` | Active `phase:mode`. Absent file = `plan:pair`; a mode-only file = `plan:<mode>`. |
| `unlocked/<session-id>` | Absolute paths unlocked as scaffolding in pair mode. |
| `events.tsv` | `time, session, from, to, source` with source `user`, `direct` or `revert`; 4-column legacy rows count as `user`. |
| `debt.md` | Decisions and gaps. |
| `guard.conf` | Exempt paths, document patterns and phase path classes (user-edited). |

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

## 4. Phases

### 4.1 Model

Session state becomes **`phase:mode`**, still one file per session, e.g. `implement:pair`.
A session is always in a full `phase:mode`; a mode or a phase on its own is not a valid
state.

| Phase | Produces | Frozen |
|---|---|---|
| `plan` | The local spec (`REQUIREMENTS.md`) and plan (`PLAN.md`), design decisions | nothing |
| `implement` | Tests and code; progress in `PLAN.md` | spec, design |

- **Default:** a fresh session (no state file) is `plan:pair`. `plan` freezes nothing, so a
  session that never types `/phase` behaves exactly like today's `pair`.
- **Legacy state:** a state file or `events.tsv` row holding only a mode is read as
  `plan:<mode>`, so running sessions keep their mode and gain no freezes.
- **Invalid values** (unknown phase or mode, missing half) are never written: the banner
  rejects the command and leaves the state unchanged; the tamper check treats an invalid file
  like any other mismatch and restores the last user-made state.

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
- `/phase` needs a user-only skill (`skills/phase/SKILL.md`) like the mode commands, so the
  command exists in the UI; the skill only confirms, the banner applies.
- Going back (`implement` → `plan` when the spec turns out wrong) is just `/phase plan`. Only
  the user can do it; the agent stops and says why.

### 4.3 Freezes

A freeze stops the failure mode spec-first work targets: an implementing agent changing the
contract to make its own tests pass.

Path classes, matched relative to the repo root (4.4). A path belongs to the first class that
matches, in this order:

| Class | Default patterns | Frozen in |
|---|---|---|
| plan | `.requirements/*/PLAN.md` | never |
| spec | `.requirements/**` | `implement` |
| design | `.system_design/SYSTEM_DESIGN.md`, `docs/adr/**` | `implement` |
| everything else | — | never (no code freeze) |

- **spec** is the local contract: As Is, To Be, the `AC-n` acceptance checks and their
  verification mapping.
- **plan** sits beside it and stays writable so the agent can tick steps and add notes.
- **design** covers only design docs a repo already keeps; most repos have none, and team
  decisions go to Confluence ADRs, which no local guard can freeze.
- **No code freeze in `plan`.** Requirements-before-code is a rule in the change workflow;
  freezing code would make the default `plan:pair` unable to fix a one-liner.

Known gap: CLI tools that write files themselves are not seen by the guard, which inspects
only Write/Edit and Bash redirects.

### 4.4 Repo-root rule and configuration

Patterns are matched against the target file's path **relative to the root of the git
repository containing that file** (`git -C <file's directory> rev-parse --show-toplevel`),
never against an absolute path or the session's working directory, so the rules hold in a
plain checkout, in any worktree, and when a session edits another repository. A file outside
any git repository has no freeze.

Configuration is personal and never committed:

| Where | What |
|---|---|
| `~/.claude/ai-mode/guard.conf` | Default patterns per class |
| `git config --local ai-modes.<class> "<patterns>"` | Per-repo override; lives in `.git/config`, shared by all worktrees, invisible to colleagues |
| `~/.config/git/ignore` (global) | `.requirements/`, so the local spec and plan are never committed |

### 4.5 Mode × phase guidance

The guard sees paths, not authorship, so what each mode means inside a phase is carried by
the banner text, which becomes phase-aware:

| Phase | `pair` | `solve` | `study` |
|---|---|---|---|
| plan | Agent asks one question at a time; user writes the THEN of each acceptance check; agent writes the rest of the spec and the plan as agreed scaffolding | Agent drafts spec and plan from the answers; user accepts or refines | Agent quizzes on the problem; writes nothing |
| implement | User types the load-bearing lines, including test assertions; agent writes scaffolding | Agent writes everything | No code |

### 4.6 Key decisions

| Decision | Alternatives | Why this one |
|---|---|---|
| Two phases, `plan` and `implement` | `grill`/`spec`/`design`/`tasks`/`implement`/`verify`; `spec`/`design`/`implement` | Design lives in the local spec or Confluence, so a separate design phase has little to freeze; the one freeze that matters is the spec during implementation. |
| Always a full `phase:mode`, default `plan:pair` | Mode-only sessions | User decision: one state shape. `plan` freezes nothing, so the default changes no behaviour. |
| Plan in its own `PLAN.md` | Plan inside `REQUIREMENTS.md` | The spec must be frozen while the plan must stay writable; one file cannot be both. |
| No code freeze | Freeze code in `plan` | Keeps the default session usable for small fixes; ordering is a workflow rule. |
| Freezes apply in every mode | Freezes only in pair | Drift protection is about the contract, not learning; solve is where drift is most likely. |
| Phase switched by the prompt hook | Agent-run script | Same user-only guarantee as modes (section 3). |
| Patterns relative to the repo root | Absolute paths, session working directory | Works in single checkouts and worktrees alike. |
| Personal config only (`guard.conf`, `git config --local`, global ignore) | A committed `.sdd/` folder | Colleagues use other tools; nothing personal may land in shared repos. |
| Tamper check before applying a typed switch | Switch first, as for modes before phases | A switch builds on the restored state, so a tampered phase is never carried into a user-made row. |
| Separate `[AI-PHASE: ...]` banner line | Fold the phase into `[AI-MODE: ...]` | The mode skills and `rules/ai-modes.md` key off the `[AI-MODE: ...]` line naming the mode. |
| Globs with `**` across directories, `*` within one | Bash `==` globbing | In bash `*` crosses `/`; segment-bound `*` keeps `docs/adr/*` from matching nested paths. |
| Default patterns also hardcoded in the guard | Only in `guard.conf` | The installed `guard.conf` is a copy the agent may not write; existing installs get the defaults without a manual edit. |
| ai-modes ignores git branches and worktrees | Built-in worktree management | Worktrees are a git habit before a session starts; measured need was about 5 days in 4.5 months, all in one repo. |

### 4.7 Spec enforcement

The freeze keeps the contract fixed; these keep it honest and private.

- **Checker.** `spec-check.sh [DIR]` reads the newest `.requirements/*/REQUIREMENTS.md`
  (folder names sort by UTC time). Every `AC-n` under "Acceptance checks" needs a Verification
  line: `` - AC-1, AC-2: `command` `` (run from the repo root, exit 0 = pass) or
  `- AC-3: manual — …` (listed, not run). Missing, unparsable or failing lines fail the check.
- **Git hooks, per repo, opt-in.** `spec-check.sh install` symlinks itself as `pre-push` (runs
  the checker when a spec exists) and `commit-msg` (rejects `AC-<digits>` and `.requirements/`)
  in the repo's common hooks dir, so all worktrees share them. It never replaces a hook that is
  not its own and nothing lands in the repo.
- **No bypass by the agent.** The guard denies `--no-verify`, `git commit -n` and
  `core.hooksPath` in every mode.
- **Phase hints.** The banner reads the prompt's working directory: in `plan`, a newest
  `PLAN.md` with ticked and unticked steps suggests `/phase implement` (phase is per session,
  so a new session on a running change starts in `plan`); in `implement`, a repo without a spec
  containing acceptance checks gets a warning, because nothing meaningful is frozen.
- **Tests.** In `implement:solve` the banner forbids weakening or deleting an assertion to get
  green without naming it first.

Limits: weakening an assertion inside a test that still passes is not detectable; in `solve`
the agent can still remove the hook links, since guard code is editable there by design.

| Decision | Alternatives | Why this one |
|---|---|---|
| Run the commands the spec names | Parse test reports per tool | Tool-agnostic (`terraform test`, `promtool`, `pytest`); the command set is the one agreed in `plan` and frozen in `implement`. |
| Per-repo opt-in hooks | Global `core.hooksPath` | A global path silently disables repos' own hooks (husky, pre-commit). |
| Hooks are symlinks to the installed script | Copies in each repo | Updates are live; nothing to resync. |
| Newest spec folder is the active one | Change IDs, branch names | ai-modes ignores branches; UTC folder names already order changes. |
| Checkboxes as the in-progress signal | Free-text progress notes | Deterministic to read. |

## 5. Open questions

None.

## 6. Relationship to the change workflow and emnifai

`~/.claude/CLAUDE.md` holds the change workflow: investigate, confirm, write the local spec
(`.requirements/<UTC>_<name>/REQUIREMENTS.md` with `AC-n` checks and their verification) and
`PLAN.md`, test first, self-review. Shared artifacts (commits, PRs, Jira, Confluence) never
mention the AI setup, the local spec or `AC-n` IDs.

emnifai (emnify's installer) stays installed for what it syncs: the GitHub, Atlassian and
incident.io MCPs, the navigation maps, the `emnify-skills` plugin and settings. Its baseline
process text was replaced in `CLAUDE.md`, which emnifai merges only on install and does not
sync. Its two reviewer agents (and the plugin's copies) are disabled with `permissions.deny`
`Agent(...)` rules, which leave the synced files untouched.

| Layer | Owns | Where |
|---|---|---|
| Change workflow | What happens per change, the local spec | `~/.claude/CLAUDE.md` |
| ai-modes | Who types; what is frozen in which phase | hooks, skills, `rules/ai-modes.md` |
| emnifai | Tool access (MCPs, skills), settings | synced by emnifai |

**Acceptance checks ↔ tests.** Test names in shared repos never carry `AC-n` IDs, so the
mapping lives only in the spec's Verification section. A deterministic checker, if added
later, reads that mapping and confirms each named test exists and passed; it would be a local
`.git/hooks/pre-push`, never committed, and outside ai-modes.

**Personal rules only add.** User-level rules load with the same priority as `CLAUDE.md`;
when they conflict, Claude may follow either. So `rules/ai-modes.md` never contradicts the
workflow: the modes decide who types, and `/solve` is the workflow's explicit opt-out (no
local spec during incidents).
