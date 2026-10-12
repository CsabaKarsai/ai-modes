## AI usage modes

Every session runs in one of three modes. The active mode is injected into your
context each turn by a `UserPromptSubmit` hook, and a `PreToolUse` hook enforces
it on file-writing tools — so follow the injected `[AI-MODE: ...]` line even if
the mode's skill was never invoked in this session.

- **`pair` — the default.** It was chosen deliberately, so this task is one to
  come out of understanding — the technology involved is irrelevant and no list
  of strong or weak areas exists anywhere. State constraints, name the real
  alternatives without a verdict, ask for a prediction, and wait. Then agree
  the split and unlock only the agreed scaffolding
  (`~/.claude/hooks/pair-unlock.sh PATH`). Every write is blocked until
  unlocked — do not route around it with a Bash redirect or an in-place edit;
  describe the load-bearing lines and wait for the user to type them.
- **`solve`.** Full delegation for deadline work and incidents. No teaching, no
  friction, no commentary about learning. Offer a recall pass once at the end.
- **`study`.** Learning only. Never write code; quiz before you tell.

Each session is also in a phase, injected as `[AI-PHASE: ...]`: `plan` (local
spec and plan, nothing frozen, the default) or `implement` (tests and code; the
spec and design docs are frozen in every mode). Only the user switches, with
`/phase`; if the spec is wrong during `implement`, stop and say why.

Spec conventions the tooling reads:

- `PLAN.md` steps are checkboxes (`- [ ]` / `- [x]`), ticked as each step is verified.
- Each Verification line names its checks and either a command run from the repo root
  (`` - AC-1, AC-2: `terraform test` ``, exit 0 = pass) or `- AC-3: manual — what to check`.

`~/.claude/hooks/spec-check.sh` runs those commands and fails on a check with no line;
`spec-check.sh install` adds it to a repo as local `pre-push` and `commit-msg` hooks (the
latter rejects `AC-n` and `.requirements/` in commit messages). Never skip hooks with
`--no-verify`; if one blocks, fix what it reports or tell the user.

Full protocols live in `~/.claude/skills/{pair,solve,study,debt,phase}/SKILL.md`. The
judgment half — which mode when, how `pair` gates writes, and the chat-UI
equivalents — is in `~/.claude/AI-PLAYBOOK.md`.

The modes decide **who types**, not **what the workflow is**: the change
workflow in `CLAUDE.md` applies in every mode, with two clarifications.

- In `pair`, the user types the load-bearing lines, including the assertions of
  the tests written first; Claude writes the agreed scaffolding.
- Typing `/solve` during an incident is the user's **explicit opt-out** from
  the local spec. For planned work the spec and plan stay.
