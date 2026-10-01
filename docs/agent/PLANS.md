# Planning complex work

Use a living task plan for complex features, substantial refactors, or work likely to span sessions. Do not create a plan for a small fix or formatting change. Follow `AGENTS.md`; a plan does not authorize tests, commits, device access, or publication.

Store a task plan in `docs/agent/plans/<task-name>.md`. Keep it useful to someone resuming with only the repository and this plan. Include:

1. **Purpose and acceptance:** what the user gains and the observable behavior that defines completion.
2. **Scope and context:** relevant files, current behavior, constraints, and unresolved assumptions.
3. **Milestones:** concrete edits and dependencies, with the expected outcome of each step.
4. **Progress:** completed, remaining, and partially completed work; record what actually happened.
5. **Decisions and discoveries:** important choices, their rationale, and evidence that changed the approach.
6. **Validation and recovery:** requested checks, expected observations, data safeguards, and a safe retry or rollback path. Distinguish planned checks from checks actually performed.
7. **Outcome and remaining work:** what was delivered, what was verified, and any unresolved limitation.

Update the plan when progress, evidence, or decisions change. State user-visible outcomes before implementation details. Keep evidence short, link to relevant files, and omit private device or browsing data. Do not invent results or mark acceptance complete merely because the code compiles.

Planned product directions belong in `ROADMAP.md`. Completed chronological development belongs in `DEVELOPMENT_HISTORY.md`; release changes belong in `CHANGELOG.md`. A task plan should link to these documents when needed rather than duplicate them.
