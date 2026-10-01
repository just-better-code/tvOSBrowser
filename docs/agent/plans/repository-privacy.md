# Depersonalize the public repository

## Purpose and acceptance

Keep reusable project instructions public while removing personal browsing examples, device metadata, account configuration, and personal Xcode state. Preserve local signing settings and legitimate upstream attribution. The user authorized commits and a local history rewrite with a private backup; pushing remains outside the authorized work.

## Scope and context

Relevant files are `AGENTS.md`, `docs/agent/`, development documentation, Xcode signing configuration, tracked `xcuserdata`, and native video diagnostics. Physical Apple TV work requires user permission; the simulator is the default. This task does not require building or running the application.

## Milestones and progress

- [x] Review official OpenAI guidance; organize persistent rules, task-specific runbooks, and planning guidance.
- [x] Generalize personal test descriptions and move signing values to an ignored local configuration.
- [x] Share the Browser scheme and remove per-user Xcode files from tracking while preserving local copies.
- [x] Omit object payloads from native video diagnostic output; retain numeric-only events.
- [x] Save a private backup outside the repository before rewriting history.
- [x] Rewrite local branch and stash history to remove the identified personal metadata and replace the user's commit identity with the project identity.
- [x] Update current documentation references using the generated commit map.
- [ ] Complete a second privacy scan and commit remaining documentation updates.

## Decisions and discoveries

Public source availability does not imply App Store distribution: this is a personal-use TV browser. Keep agent instructions factual and reusable. Do not copy personal examples or raw diagnostics into public process documentation. Codex tree snapshots are local tool artifacts rather than branch history; archive their original refs with the private Git backup and remove old snapshots retaining private values from the active repository.

## Validation and recovery

Inspect every reachable text blob and commit identity for the identified private values; confirm personal configuration is ignored and per-user Xcode files are no longer tracked. Check that documentation references resolve after the rewrite. These are repository audit checks, not application tests. No application build, simulator interaction, or physical-device verification is performed. The private backup contains original Git metadata, a bundle, a working-tree patch, and local configuration; it can restore the pre-cleanup state. Keep it outside public repository paths.

## Outcome and remaining work

Local cleanup is in progress. The public GitHub repository remains unchanged until rewritten branches are explicitly published. History rewriting changes commit IDs; existing clones and references require coordination when publishing.
