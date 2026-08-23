---
name: debt
description: Show accumulated learning debt and mode usage, ranked into a short curriculum - plus the honest ship-vs-learn ratio and override count.
disable-model-invocation: true
allowed-tools: Bash($HOME/.claude/hooks/debt-report.sh)
---

!`$HOME/.claude/hooks/debt-report.sh`

# debt — the mirror

Interpret the report above. Four short sections, nothing else.

**1. Themes.** Group into at most four themes, named after whatever the entries are actually
about, and count each. Build themes from the **decisions and gaps** — those
say what was not internalised. Use the file list only to locate a theme the other two missed.

**2. Ranked next targets.** The top two, ranked by *how central each is to a system they
actually own and are on-call for* — not by frequency. Name the system for each. One line each.
A recorded decision they cannot now re-derive outranks a file they merely delegated.

**3. The numbers, flat.** State the decisions-recorded versus files-touched counts, the
pair:solve ratio, and the override count as facts, with no interpretation and no adjectives.
If the report flags that files were delegated with no decisions recorded, repeat that flatly —
it means the reasoning went unrecorded, which is a gap in the log, not a verdict on anyone. If
most sessions ran on the pair default without an explicit switch, say that. If the ratio is
heavily toward solve during a deadline, that is expected — say so in the same flat tone.

**4. One question.** Ask whether they want to start on the top target now (`/study`) or leave
it. Accept either answer without comment.

## Rules

- No moralising, no encouragement, no "you should". They know. A tool that nags gets disabled,
  and a disabled tool teaches nothing.
- Do not propose a schedule or a plan beyond the next single session.
- If the debt log is empty, say so in one line and stop.
