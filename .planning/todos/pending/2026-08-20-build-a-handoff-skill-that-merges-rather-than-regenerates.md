---
created: 2026-08-20T21:10:00.000Z
title: Build a handoff skill that merges rather than regenerates
area: tooling
severity: major
build_with: skill-creator (Anthropic skill)
files:
  - .planning/seeds/SEED-001-handoff-skill.md (the full spec — build from this)
  - .planning/research/2026-08-20-pause-work-missing-directives-and-template-defects.md (problem statement, 6 defects)
  - skills/gsd-handoff/SKILL.md (DOES NOT EXIST YET — the artifact to create, in this repo on a local/* branch)
---

## Problem

`/gsd-pause-work` **regenerates** the handoff from current artifacts. The standard this
needs is a **merge**: read the prior `HANDOFF.json` + `.continue-here.md` first, carry
forward every open item, and require a stated reason for any dropped id. Regeneration
loses unresolved items silently — the file looks complete while an open item vanished.

Per the spec, that difference "cannot be expressed as a section addition", which is why
this is a new skill rather than another patch to `pause-work.md`.

Full rationale, process, schemas and anti-patterns: **`.planning/seeds/SEED-001-handoff-skill.md`**.
Empirical problem statement (6 defects, measured): the research doc in `files:` above.

## Name it `gsd-handoff`, and ship it from this fork

It lives at **`skills/gsd-handoff/SKILL.md` in this repo**, on a `local/*` branch, and
reaches `~/.claude` because this fork is the install source.

The `gsd-` prefix is correct here, not a hazard. `bin/install.js` reads from
`path.join(__dirname, '..')` (`:10000`) — this repo — and writes to the target. The
recursive `rmSync` over `skills/gsd-*` (`:10823-10826`) is a **wipe-then-replace-from-source**,
so a `gsd-*` skill present in the fork is replaced with itself. The prefix is also what
puts it in the same namespace as every other GSD skill, which `--surface` and the `gsd-ns-*`
routers key on.

**The real hazard is the install command, not the name:**

| Command | Source | This skill |
|---|---|---|
| `node bin/install.js --claude --global` from this repo | **this fork** | survives — it IS the source |
| `/gsd-update`, which runs `npx -y --package=@opengsd/gsd-core@TAG` (`gsd-core/workflows/update.md:383-393`) | upstream npm | **destroyed** — upstream has no `gsd-handoff` |

So: install from the fork, and treat `/gsd-update` as "fetch upstream into `next`, then
rebuild `working` and reinstall from here" rather than as a command to run directly.

Name is free — no `skills/gsd-handoff` in this repo (71 skills) and none in `~/.claude`.

## Build method

Use Anthropic's **`skill-creator`** skill (operator's call). It handles SKILL.md structure,
description tuning for trigger accuracy, progressive disclosure, and evals — so the
authoring half is mechanical and the spec is already implementation-ready.

The residual work is the decisions and the logic, not the scaffolding:

1. **Answer the four open questions** (spec §7) — they were deliberately deferred to build
   time rather than gating promotion:
   - commit/MR behaviour — gate on operator nod, or default to committing?
   - `.continue-here.md` path for milestone-scoped work — always repo root?
   - refuse when the review finds nothing, or write anyway?
   - peer-repo state — measure it, or accept as reported?
2. **The merge step** (spec §3 step 3) — the `comm -23` diff of prior vs current open ids,
   and the fail-closed rule that every dropped id needs a stated reason.
3. **The verify step** (spec §3 step 5) — JSON parses, no double-encoded escapes, then the
   stale-claim sweep. ⭐ **Read each hit, do not count them** — a surviving hit may be a
   correct historical reference or a live stale instruction, and only reading distinguishes
   the two.

## Relationship to the other pause-work todos

This skill does **not** fix `/gsd-pause-work` itself. Two genuine bugs in that file remain
separate work, and both edit it, so they want one shared branch rather than two:

- `2026-08-19-fix-pause-work-s-broken-phase-glob-and-dead-gate.md` — the phase glob never
  matches `NN-PLAN.md`, so the mandatory blocking-anti-pattern gate never fires.
- Defect 6 in the research doc — duplicate `## Critical Anti-Patterns` at `pause-work.md:139`
  (table, the one discuss-phase/execute-phase actually parse) and `:184` (bullets, dead).
  Confirmed still present at v1.11.0.

Sequencing is open: building against `pause-work.md` while those fixes are pending risks
designing around bugs about to change.

## Scope

Small — a few hours — assuming `skill-creator` carries the scaffolding. Revise upward if
`/gsd-resume-work` needs changes to read the new schema keys
(`corrections_to_artifacts`, `cross_session`, `operator_decisions_pending`,
`ready_not_started`). A handoff that nothing reads back is write-only.
