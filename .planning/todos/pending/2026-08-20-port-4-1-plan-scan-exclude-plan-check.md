---
created: 2026-08-20T23:10:00.000Z
title: Port 4.1 — plan-scan: exclude PLAN-CHECK.md from the plan count
area: tooling
severity: minor
files:
  - src/plan-scan.cts:119-134 (isRootPlanFile — the loose /PLAN/i fallback and the existing anchored exclusion list)
  - tests/plan-count-single-owner.test.cjs:173-184 (row11, -PLAN-REVIEW.md — the row to mirror)
  - .planning/runbooks/porting-local-patches-assets/4.1-plan-scan-RED.test.cjs (RED test, already written and confirmed failing)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.1 — full analysis)
---

## Problem

`{phase}-PLAN-CHECK.md` falls through the deliberately-loose `/PLAN/i` fallback in
`isRootPlanFile` and counts as an executable plan. A phase with N real plans and N summaries
then reads **N+1 plans / N summaries** → `implementation_complete: false`. **A phase that can
never register as done.**

Three anchored exclusions already exist for exactly this class (`OUTLINE`, `PRE_BOUNCE`,
`REVIEW`). This is an incomplete application of an established pattern, not a new mechanism.

## Validation verdict — 2026-08-20, by enumeration

**Port as-is. Frame it honestly: it fixes the one observed instance, NOT a class.**

- ⚠ **Not a class fix.** It excludes exactly one anchored literal (`-PLAN-CHECK.md$`,
  case-insensitive). These all still leak and reproduce the identical N+1 failure:
  `-PLAN-NOTES.md`, `-PLAN-DRAFT.md`, `-REPLAN.md`, `PLANNING.md`, `05-planning.md`,
  `-PLAN-CHECKLIST.md`, and bare `PLAN-CHECK.md` (no dash). The underlying defect is the
  unanchored `/PLAN/i` fallback itself.
- ⚠ **Provenance unverified.** A repo-wide grep across the 1.11.0 fork, the pristine 1.10.0
  install and all of `~/.claude` finds **zero producers** of that filename. `gsd-plan-checker`
  returns an inline YAML block (`gsd-core/workflows/plan-phase.md:1085`), and its frontmatter
  carries `disallowedTools: Write, Edit, MultiEdit` — so that agent *cannot* have written it.
  **But the artifact is real**, found at
  `~/gsd-workspaces/plane-audit-logs/plane/.planning/workstreams/rbac-backport/phases/05-*/05-PLAN-CHECK.md`,
  beside exactly 6 PLAN/SUMMARY pairs, matching the documented incident
  (`~/.claude/runbooks/gsd-update-runbook.md:259-272`). Say "reapply if this recurs", not
  "this happens today". Do not claim a producer upstream without locating one.
- **Do NOT tighten the fallback.** `src/plan-scan.cts:119-134` documents that it is
  *intentionally* permissive so an off-pattern real plan (lowercase `plan.md`) still counts;
  `plan-count-single-owner.test.cjs` row12+ pins that. Named anchored exclusions have zero
  false-negative risk — verified `-PLAN-CHECKLIST.md` still counts, so the anchor does not
  over-match.
- **Measured** on a real 3-pair fixture against this repo's built `plan-scan.cjs`:
  `BEFORE → planCount 4, summaryCount 3, completed false` · `AFTER → 3, 3, true`.

## Solution

Pilot for the whole port campaign — smallest surface, easiest RED test, establishes the
pattern (branch → translate `.cjs`→`.cts` → TDD → build → verify) at minimum scale.

1. Branch off `next`, restore the Makefile (it does not exist on `next` — see runbook §6).
2. **RED:** add the row from `porting-local-patches-assets/4.1-plan-scan-RED.test.cjs` to
   `tests/plan-count-single-owner.test.cjs`, mirroring `row11` at `:173-184`. Own commit.
   Confirmed failing mechanically (`2 !== 1`).
3. **GREEN:** add the anchored `PLAN_CHECK_RE` exclusion in `src/plan-scan.cts`. Never edit
   `gsd-core/bin/lib/plan-scan.cjs` — gitignored build output.
4. `npm run build && env -u GSD_AGENTS_DIR npm test && npm run lint:ci`

**Upstream viability: strongest of the set.** Pure bug fix, trivially testable, no preference
component. Add a changeset only if promoted to a contribution branch off `next`.

## Cross-references

- Analysis: `.planning/runbooks/porting-local-patches-to-the-fork.md` §4.1
- Sequence: runbook §5 item 1 (⭐ start here) · per-branch checklist: §6
