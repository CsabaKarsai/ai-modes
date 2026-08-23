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

Full protocols live in `~/.claude/skills/{pair,solve,study,debt}/SKILL.md`. The
judgment half — which mode when, how `pair` gates writes, and the chat-UI
equivalents — is in `~/.claude/AI-PLAYBOOK.md`.
