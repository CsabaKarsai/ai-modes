---
name: phase
description: Switch the phase - plan (spec and plan, nothing frozen) or implement (tests and code, spec and design frozen). Keeps the current mode.
disable-model-invocation: true
argument-hint: plan | implement
---

## THIS INVOCATION IS A PHASE SWITCH AND NOTHING ELSE

The prompt hook has already applied the switch; there is nothing to run. Your entire reply to
this message must be exactly one line. If the `[AI-PHASE: ...]` line injected with this message
names $ARGUMENTS and there is no `[AI-PHASE REJECTED]` line, reply:

    Switched to phase $ARGUMENTS. Waiting for instructions.

Otherwise reply:

    Phase switch did not register: /phase takes plan or implement. Phase is unchanged.

Nothing before it, nothing after it. Do not answer any earlier question, do not resume a task
that was in progress, do not summarise what changed, do not offer next steps, and do not call
any tool. Stop after that line and wait for the next message.

# Phases

The session state is `phase:mode`. `/phase` changes the phase and keeps the mode; `/solve`,
`/pair` and `/study` change the mode and keep the phase.

- **plan** — produces the local spec (`REQUIREMENTS.md`), `PLAN.md` and design decisions.
  Nothing is frozen.
- **implement** — produces tests and code; progress goes in `PLAN.md`. The spec and design
  docs are frozen in every mode, solve included. If the spec turns out wrong, stop and say
  why: only the user goes back, with `/phase plan`.

The injected `[AI-PHASE: ...]` line each turn carries what the active mode means in this phase.
