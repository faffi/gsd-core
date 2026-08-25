---
gsd_state_version: 1.0
milestone: v1.12
milestone_name: Fix the blockers, finish the port campaign
status: planning
last_updated: "2026-08-24"
last_activity: 2026-08-24
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-24)

**Core value:** Every local divergence from upstream is either deliberately carried (recorded, with a
reason) or on its way upstream (as a fix with a test) — never silently accumulating as drift that the
next `make install` destroys.
**Current focus:** Phase 1 — Instruments before repairs

## Current Position

Phase: 1 of 6 (Instruments before repairs)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-08-24 — Roadmap created; 32 requirements mapped across 6 phases

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Adjudications binding on this milestone
(from `.planning/research/SUMMARY.md`, do not re-open):

- **ADJ-3 / build-before-measure**: `gsd-core/bin/lib/` carries an `advance-plan` guard `src/` does
  not. `npm run build:lib` is the first task of Phase 1; any measurement before it is a phantom.
- **ADJ-1 / workstream predicate**: `listAvailableWorkstreams(cwd).length > 0 ||
  diagnoseUnresolvedActiveWorkstream(cwd).present`. Not `fs.existsSync('.planning/workstreams')` —
  that reads false in exactly the case that produces the bug. Both T1 and T2 triggers in scope.
- **ADJ-2 / shell-lint substrate**: `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1`.
  `sh-syntax` rejected for its positional-only JSON AST, **not** for lacking zsh (it has zsh).
- **A phase is not a PR.** PR splits are carried in each phase's `**PR shape**` line in ROADMAP.md.
- **INST-03**: the cross-shell harness must land RED before any site fix (Phase 1) and reach upstream
  green carrying harness + fixes in one PR (Phase 4). A skip list does not satisfy it.

### Pending Todos

22 captured todos in `.planning/todos/pending/` — the source material for this milestone's
32 requirements. See `/gsd-capture --list`.

### Blockers/Concerns

- **Environment baseline must accompany every failure count**: Node 24 required (nvm default is
  lower and npm treats `engines` as advisory); a stray `.DS_Store` under `gsd-core/` fails 20 tests;
  `GSD_AGENTS_DIR` in the ambient environment fails 12. Clean baseline: 3 environment-caused failures
  out of 30,612.
- **Open question for the maintainers, not a technical one**: will a knowingly-RED harness PR be
  accepted? Decides whether Phase 1's harness and Phase 4's site fixes are one PR or two. Ask before
  Phase 1's harness ships.
- **Working tree**: branch `local/state-advance-plan-fallback-fix` carries the superseded WIP
  `f72f1534` diff in `src/state.cts` and `tests/state.test.cjs`. Phase 2's PR-A supersedes it.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Workstream | WS-F01 Class A tail adopts the shared predicate | Deferred to v1.12.x | 2026-08-24 |
| Workstream | WS-F02 Class B gate verbs move from field to refusal | Deferred to v1.13+ | 2026-08-24 |
| Tooling | TOOL-F01 `mutation` metadata made load-bearing with a CI lint | Deferred to v1.13+ | 2026-08-24 |
| Tooling | TOOL-F02 handoff skill that merges rather than regenerates | Deferred to v1.13+ | 2026-08-24 |

## Session Continuity

Last session: 2026-08-24
Stopped at: ROADMAP.md written, REQUIREMENTS.md traceability filled (32/32 mapped)
Resume file: None
