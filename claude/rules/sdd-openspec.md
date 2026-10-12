## Spec-driven repos (OpenSpec)

Applies only when the repo root contains `openspec/`. It adds to the global
`CLAUDE.md` workflow and replaces none of it: `REQUIREMENTS.md`,
`.system_design/SYSTEM_DESIGN.md` and `.system_design/steps/` stay required.
OpenSpec contributes only what they lack — behaviour scenarios with stable IDs
and a living spec — and nothing is written twice.

- **Scenarios.** The change's delta specs (`openspec/changes/<id>/specs/`) hold
  the GIVEN/WHEN/THEN scenarios, each with `<!-- id: x.y -->`. Tests reference
  them with `@pytest.mark.scenario("x.y")`.
- **`REQUIREMENTS.md`.** Keeps every section the workflow requires. Its
  Acceptance Criteria list the scenario IDs and link to the delta spec instead
  of restating the scenarios.
- **Plan.** `.system_design/steps/` is the plan, as the workflow requires. The
  change's `tasks.md` holds only a pointer to those step files.
- **Design.** `SYSTEM_DESIGN.md`, the LikeC4 model and `docs/adr/`.
- **Phase freezes.** The active ai-modes phase freezes upstream artifacts. If
  the spec or design turns out wrong or incomplete, stop and say so; only the
  user moves back with `/phase spec` or `/phase design`.
- **Archive.** In `verify`, run `openspec archive <id> --yes` (never
  `--no-validate`) in the same PR as the code.
