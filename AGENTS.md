# Agent instructions

## Project TL;DR

**just-better-code version** is a local web browser for personal use on Apple TV, designed to make browsing and watching web video convenient with a TV remote. The source repository is public; the application will never be published on the App Store. Do not assume a paid Apple Developer membership or introduce App Store publication requirements into implementation decisions.

## Working agreements

- Use the Apple TV Simulator by default. Discovering, inspecting, installing, launching, or interacting with a physical Apple TV requires the user’s permission for that work.
- Git commits are authorized. Do not push this repository unless the user requests it.
- Preserve automatic signing and the effective local development-team and bundle-identifier settings. Personal values belong in the ignored `Signing.local.xcconfig`; shared configuration uses neutral defaults.
- Add or run tests only when the user asks for testing or verification. Run builds when requested. Report exactly what was checked; compilation or launch alone does not prove an interaction bug is fixed.
- Define completion in terms of the user's observable outcome. Ask for user participation when the required observation cannot be made locally; do not claim device verification without evidence.
- Record durable user instructions and confirmed, reusable project workflows here or in linked agent runbooks. Keep temporary task status, personal diagnostics, and implementation chronology in their appropriate documents.

## Tools and task-specific references

- Prefer `rg` and `rg --files` for targeted text and file discovery.
- Xcode project: `_Project/Browser.xcodeproj`; scheme: `Browser`. Use `xcodebuild` for requested builds and `xcrun devicectl` for device work only with the user’s permission.
- For authorized device builds, installation, launch, and history-container backups, read [Apple TV runbook](docs/agent/APPLE_TV_RUNBOOK.md).
- For complex features, substantial refactors, or work spanning sessions, use [planning guidance](docs/agent/PLANS.md). Small fixes and documentation edits do not need a plan file.
- Read `USER_GUIDE.md` for existing user-facing controls, `ROADMAP.md` for planned and rejected directions, and `DEVELOPMENT_HISTORY.md` when past decisions or verification matter. Read only what the task needs.
- Repository skills live under `.codex/skills/`. Load a skill's `SKILL.md` when its workflow applies; keep reusable workflow details and supporting scripts with the skill.
- `.codex/hooks.json` configures a `PreToolUse` hook for `Bash` running `graphify hook-check`; it does not establish that every execution surface runs that hook or that the graph is current.

## Knowledge graph

This project has a knowledge graph under `graphify-out/`.

- For codebase questions, run `graphify query "<question>"` first when `graphify-out/graph.json` exists.
- Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- Dirty graph files are expected after hooks or incremental updates. Skip graphify only when the task concerns stale graph output or the user asks not to use it.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation. Read `GRAPH_REPORT.md` only for broad architecture reviews or when a query does not provide enough context.
- After changing code, run `graphify update .`.

## Data protection and public documentation

- Preserve browsing history and tab state across ordinary launches. Do not introduce automatic age-based history deletion; history is cleared only through an explicit user action.
- Before changing database paths, fallback order, or retention, follow the device backup safeguards in the runbook. Without permission for physical TV work, do not bypass this requirement with assumptions about the live container; leave dependent migration work pending and explain the missing prerequisite.
- Website state should persist through the website's storage mechanisms; do not turn individual dropdown selections or episode choices into app-specific backup features.
- Keep credentials, cookies, authorization headers, signed URL query values, copied databases, and personal diagnostic logs out of tracked files. Redact sensitive runtime values before publishing diagnostic evidence.
- Use placeholders for machine paths and device identifiers in shared instructions. Keep personal setup details and scratch notes in ignored local files.
- Retain legitimate upstream copyright and attribution. File removal does not erase information already present in Git history; any history rewrite requires a separate user request.

## Agent file layout

- Root `AGENTS.md`: project context, durable rules, tool entry points, and links to task-specific procedures. Keep instructions concise and remove obsolete or conflicting rules.
- Nested `AGENTS.md`: instructions specific to that directory, only when needed. `AGENTS.override.md` replaces the instruction file at its directory level; use it only for an intentional override.
- `AGENTS.local.md`: ignored local notes, explicitly read when local context is relevant. This name is not automatically discovered by Codex by default, and a fallback filename does not make it merge alongside an existing root `AGENTS.md`.
- `docs/agent/`: referenced runbooks and planning standards, loaded for the relevant task.
- `SKILL.md`: a focused reusable workflow with a short, specific trigger description; put optional references and scripts beside it.
- `.codex/hooks.json`: executable hook configuration; keep explanatory project policy here. Do not add duplicate agent files or hooks without a concrete need.

## Documentation and versioning

- Write and maintain project documentation in English. Use the fork name **just-better-code version**.
- Follow [Common Changelog](https://common-changelog.org/) in `CHANGELOG.md`: `# Changelog`, newest versions first, `## VERSION - YYYY-MM-DD`, and only `Changed`, `Added`, `Removed`, `Fixed` groups in that order, omitting empty groups.
- Write each change as one unnumbered, single-line item starting with an imperative verb, explaining its user impact and ending with relevant Markdown references in parentheses. Order changes by importance, with breaking changes first and prefixed `**Breaking:**`. Merge related changes; omit reverted experiments with no effect on the resulting version.
- Keep release bodies limited to change groups and, when needed, one single-sentence notice before them. Put long explanations in linked documents; do not add roadmap, process, timeline or source-table sections to `CHANGELOG.md`.
- Keep detailed dialogue history, implementation reasoning, verification evidence and reversals in `DEVELOPMENT_HISTORY.md`; keep planned and rejected directions in `ROADMAP.md`; keep usage instructions in `USER_GUIDE.md`. Link these documents from the changelog when useful.
- Keep process and versioning rules in `AGENTS.md`, rather than mixing them into the changelog or user documentation.
- Use `major.minor.patch`: increment minor for each substantial feature and reset patch to zero; increment patch for each subsequent logical bug fix. The next fix after `2.15.23` is `2.15.24`; the next substantial feature is `2.16.0`, followed by `2.16.1` for its first fix.
- Documentation or formatting changes alone do not increment the application version. Keep Debug and Release `MARKETING_VERSION` consistent. Treat `CURRENT_PROJECT_VERSION` as a separate technical build number, not the user-facing fix number.
- Preserve the initial retrospective baseline: upstream `9b90e0e` is `2.0.0`; the initial snapshot is `2.15.22`, cataloguing 15 feature groups and 22 fix groups. These are reconstructed logical versions, not proof of separately published binaries. Historical fix IDs do not imply every fix occurred after feature 2.15.
- Distinguish commit/package dates from implementation dates in dialogue history. Do not invent release dates, Git tags, published releases or verification results. This personal-use project's retrospective changelog has no matching release tags; explain that status in its release notice.

## Instruction maintenance references

- [OpenAI: AGENTS.md discovery and scope](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [OpenAI: concise instructions and task-specific references](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
- [OpenAI: skill structure and progressive disclosure](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI: execution plans](https://developers.openai.com/cookbook/articles/codex_exec_plans) — an archived example, adapted to this project's working agreements rather than copied verbatim.
