---
gsd_state_version: 1.0
milestone: v1.12
milestone_name: Fix the blockers, finish the port campaign
status: planning
last_updated: "2026-08-25"
last_activity: 2026-08-25
progress:
  total_phases: 18
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
**Current focus:** Phase 1 — The runtime build matches committed source

## Current Position

Phase: 1 of 18 (The runtime build matches committed source)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-08-25 — Roadmap re-cut at one-phase-per-todo granularity; 34 requirements mapped
across 18 phases

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

- **One phase = one todo.** The 20 in-scope todos in `.planning/todos/pending/` are deliberately
  compartmentalized — one captured issue each — and that compartmentation *is* the phase structure.
  Exactly two merges are sanctioned, both shipping constraints: the graphify chain (Phase 11) and the
  `quick.md` pair (Phase 9). A phase whose note needs a sentence explaining why its contents belong
  together is a bucket.
- **ADJ-3 / build-before-measure**: `gsd-core/bin/lib/` carries an `advance-plan` guard `src/` does
  not. Phase 1 is `npm run build:lib` and nothing else; any measurement before it is a phantom.
  Phase 1 has **no todo by design** — do not fabricate one.
- **ADJ-1 / workstream predicate**: `listAvailableWorkstreams(cwd).length > 0 ||
  diagnoseUnresolvedActiveWorkstream(cwd).present`. Not `fs.existsSync('.planning/workstreams')` —
  that reads false in exactly the case that produces the bug. Both T1 and T2 triggers in scope.
- **ADJ-2 / shell-lint substrate**: `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1`.
  `sh-syntax` rejected for its positional-only JSON AST, **not** for lacking zsh (it has zsh).
- **A phase is not a PR.** PR splits are carried in each phase's `**PR shape**` line in ROADMAP.md.
- **INST-03**: the cross-shell harness lands RED against the unfixed sites as Phase 4's *first* plan,
  and the same phase closes with it green — harness and site fixes reach upstream in one PR. A skip
  list or expected-failure marker does not satisfy it.
- **No todo routes to `/gsd-quick`.** `quick.md:470` forbids quick tasks touching ROADMAP.md, so a
  quick-routed todo would orphan its requirements. Small todos get small phases; that is expected.

### Pending Todos

22 captured todos in `.planning/todos/pending/`. **20 are mapped** to 18 phases (see ROADMAP.md's
Coverage table). Two are deliberately unmapped and get no phase:
`build-a-handoff-skill-that-merges-rather-than-regenerates` (SEED-001, an enhancement → `TOOL-F02`)
and `port-4-5-graphify-exclude-file-types-flag` (corpus membership vs retrieval eligibility; no v1.12
requirement covers it). Each todo's `resolves_phase` frontmatter field still points at the **old**
6-phase structure and needs re-stamping against the new numbering. See `/gsd-capture --list`.

### Blockers/Concerns

- **Environment baseline must accompany every failure count**: Node 24 required (nvm default is
  lower and npm treats `engines` as advisory); a stray `.DS_Store` under `gsd-core/` fails 20 tests;
  `GSD_AGENTS_DIR` in the ambient environment fails 12. Clean baseline: 3 environment-caused failures
  out of 30,612.
- **Open question for the maintainers, not a technical one**: will a knowingly-RED harness PR be
  accepted? Phase 4 already plans harness + site fixes as one PR, which is the fallback either way —
  but ask before the harness ships.
- **Working tree**: branch `local/state-advance-plan-fallback-fix` carries the superseded WIP
  `f72f1534` diff in `src/state.cts` and `tests/state.test.cjs`. Phase 5's PR-A supersedes it.
- **Phase 4's lint baseline is not zero yet.** The M7 (`grep -oP`) rule's five shipped sites are
  `pause-work.md:18,21,24` (Phase 8) and `sync-skills.md:33,40` (**captured in no todo**). Either
  wire that rule after Phase 8 and capture the `sync-skills.md` pair, or the lint cannot start clean.
- **Phase 7 carries an unfiled code-level half.** D-2 — `state.signal-waiting` writes
  `planningDir(cwd)/WAITING.json` while `init.progress` reads `path.join(cwd, '.planning', …)` — is a
  `src/` fix present in no todo's file list. Its success criterion is in the phase; scope it at plan
  time or drop it explicitly and re-file.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Workstream | WS-F01 Class A tail adopts the shared predicate | Deferred to v1.12.x | 2026-08-24 |
| Workstream | WS-F02 Class B gate verbs move from field to refusal | Deferred to v1.13+ | 2026-08-24 |
| Tooling | TOOL-F01 `mutation` metadata made load-bearing with a CI lint | Deferred to v1.13+ | 2026-08-24 |
| Tooling | TOOL-F02 handoff skill that merges rather than regenerates | Deferred to v1.13+ | 2026-08-24 |
| Graphify | `port-4-5` `--exclude-file-types` — corpus membership vs retrieval eligibility | Unmapped, no v1.12 requirement | 2026-08-25 |

## Session Continuity

Last session: 2026-08-25
Stopped at: ROADMAP.md re-cut to one phase per todo (18 phases); REQUIREMENTS.md traceability
re-filled (34/34 mapped), `PORT-06` split and `PORT-08` added
Resume file: None
