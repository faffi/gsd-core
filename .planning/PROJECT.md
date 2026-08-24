# gsd-core (faffi fork)

## What This Is

A personal fork of [open-gsd/gsd-core](https://github.com/open-gsd/gsd-core) — the GSD
planning/execution toolchain for Claude Code — maintained across two machines via
`fork` (`faffi/gsd-core`). It carries local patches that upstream does not have, ports
selected local behaviour into current upstream releases, and is the staging ground for
defect fixes that are contributed back as upstream PRs.

It is not a product. The audience is one developer plus the Claude sessions working in it.

## Core Value

Every local divergence from upstream is either **deliberately carried** (recorded, with a
reason) or **on its way upstream** (as a fix with a test) — never silently accumulating
as drift that the next `make install` destroys.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ `.planning/` narrowed ignore on `working` + `local/*` only, so planning artifacts
  travel through `fork` while `next` and contribution branches stay byte-identical to
  upstream — a contribution branch cut off `next` cannot leak them (`local/track-planning-history`)
- ✓ Port 4.1 — `plan-scan` excludes `*-PLAN-CHECK.md`, fixing both the never-complete and
  false-complete directions of the phase-completion count (`local/plan-scan-exclude-plan-check`)
- ✓ Test-environment baseline established and reproducible: Node 24 + complete
  `node_modules` + no `.DS_Store` → 3 known environment-caused failures out of 30,612

### Active

<!-- Current scope. Building toward these. -->

- [ ] Fix the workstream-mode fail-safe precondition shared by `state advance-plan`,
      `init.progress` and `phase.complete` — silent root-STATE.md corruption on a
      dangling active-workstream pointer (blocker)
- [ ] Fix the zsh shell-fence portability defect — agent/command fences tagged ` ```bash `
      execute under the login shell, where the array-index glob guard is dead in both
      directions; 25 affected sites, 6 mechanisms (blocker)
- [ ] Complete the 1.10.0 → 1.11.0 port campaign (concerns 4.2–4.10)
- [ ] Stop `make install` destroying local-only skills and agents
- [ ] Work off the remaining captured defects in `.planning/todos/pending/`

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Filing GitHub issues upstream — defects are captured as todos here and contributed as
  PRs with tests; issue-filing is an explicit standing preference against
- Committing to `next` — it is a read-only mirror; anything committed there desynchronises
  the one reference point for "what upstream actually ships"
- Committing to `working` — it is rebuilt by `git checkout -B working next` plus a re-merge
  of every active `local/*`, so direct commits are destroyed without warning
- Refactoring upstream code beyond the fix at hand — this fork's changes must land as
  reviewable single-concern PRs, and a refactor bundled with a fix is a harder argument

## Context

- **Upstream version tracked:** 1.11.0. `next` mirrors `origin/next`.
- **Branch model:** `next` (pristine) → `local/<slug>` (one per feature, source of truth,
  promotable to `fix/NNN-slug`) → `working` (disposable aggregate, never a base).
  `local` cannot be a standing branch name — a `local` ref and the `local/*` namespace
  collide as a git directory/file conflict.
- **Two machines**, synced through `fork`. `~/.claude/gsd-core/`, `skills/` and `agents/gsd-*`
  are replaced wholesale by every GSD update, so local edits there must be recorded as
  patches or they are lost.
- **Generated, never hand-edit:** `.claude/agents/` (install-sync output),
  `gsd-core/bin/lib/*.cjs` (build output), `reference/gsd-config-schema.md`.
- **Known environment traps:** nvm defaults below Node 24 while npm treats `engines` as
  advisory; a `.DS_Store` anywhere under `gsd-core/` breaks 20 install-attribution tests
  because the installer copies with `fs`, not git; `GSD_AGENTS_DIR` in the ambient
  environment fails 12 tests.
- **Planning artifacts** live on `local/track-planning-history`. `.planning/notes/` holds
  working material scoped to exactly one open todo.

## Constraints

- **Tech stack**: TypeScript sources in `src/*.cts` compiled to `gsd-core/bin/lib/*.cjs`;
  Node.js `>=24.0.0` — Node 24 also changed the default test reporter from TAP to spec,
  so `# fail` greps silently match nothing
- **Compatibility**: shell fences must run under bash 3.2.57 (macOS system bash), zsh 5.9
  (the login shell here), and POSIX `sh` — process substitution and GNU-only flags such as
  `sort -z` / `xargs -0` are unavailable
- **Upstream portability**: any fix intended for contribution must apply to a branch cut
  fresh off `next`, with a test, one concern per PR
- **Dependencies**: `make install` overwrites the installed tree; local-only artifacts not
  recorded as patches are destroyed

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| `.planning/*` + directory negations instead of bare `.planning/` | git never descends into a pruned directory, so a negation can only re-include something whose parent survived | ✓ Good |
| Root-level `!.planning/PROJECT.md`/`ROADMAP.md`/`STATE.md` negations | directory negations do not cover files at `.planning/` root; without them `/gsd-new-milestone` commits nothing and reports success | ✓ Good |
| `working` is disposable, never a base | keeps `local/*` as the single source of truth per feature and lets the aggregate be rebuilt against a moving `next` | ✓ Good |
| Treat the six zsh fence mechanisms as ONE issue, not four todos | splitting would repeat upstream's own #2770→#2962→#3300→#3409 fragmentation of the same root cause | — Pending |
| Fix shared preconditions in all affected commands at once | `state`/`init`/`phase` carry an identical copied guard; fixing one leaves the other two to be refiled separately | — Pending |

---
*Last updated: 2026-08-24 after standing up the first milestone*
