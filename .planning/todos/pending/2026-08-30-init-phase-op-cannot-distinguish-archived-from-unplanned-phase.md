---
created: 2026-08-30T00:00:00.000Z
title: "init.phase-op: phase_found:true + phase_dir:null is emitted for two unrelated phase states, with no field to tell them apart"
area: tooling
severity: minor
scope: Small
scope_note: Add one boolean field (`phase_archived`) to the existing result object at src/init.cts:2011-2050 and thread it through; no schema migration, no caller behavior change required
files:
  - src/init.cts:1941-1963 (archived-phase branch — sets found:true, directory:null)
  - src/init.cts:1965-1987 (never-planned-phase branch — sets found:true, directory:null; same shape as archived)
  - src/init.cts:1989 (phaseDir derivation — collapses both branches to null)
  - src/init.cts:2026,2028 (result.phase_found / result.phase_dir — the two fields callers actually see)
  - src/init.cts:1993-2003 (expected_phase_dir — computed for BOTH branches, so it's non-null even for an archived phase pointing at a directory that no longer exists there)
---

## Problem

Raised by a peer session ("cnc", a coordination hub relaying findings across ~26
sessions) as a claimed data-loss bug: "after `milestone complete` archives a phase,
`init.phase-op` returns `phase_found: True` with `phase_dir: null`... `extract-learnings`'s
only guard is 'if phase not found, exit with error' — which never fires... proceeds
against an empty dir and writes LEARNINGS.md from nothing."

Verified in this repo before accepting the claim (dispatched a fork to check source,
not training-data assumption — this fork's own `~/.claude/rules/review-agents-verify-tech-claims-with-context7.md`
discipline applied to a peer's technical claim too):

**The `phase_found:true` + `phase_dir:null` co-occurrence is real** — `src/init.cts:1941-1963`,
when `phaseInfo.archived` is true, rebuilds `phaseInfo` with `directory: null` but
`found: true`. That flows straight through to the result object: `phase_found: !!phaseInfo`
(`:2026`) and `phase_dir: phaseDir ? ... : null` (`:2028`), where `phaseDir` (`:1989`) is
`phaseInfo.directory || null`.

**But the claimed consequence is overstated.** `extract-learnings.md:36`
("If PLAN.md or SUMMARY.md files are not found or missing, exit with error") is a second,
independent guard that fires when `PHASE_DIR` is null — the glob against it finds nothing,
and the workflow exits cleanly rather than writing a hallucinated LEARNINGS.md.
`secure-phase.md:46-53` and `validate-phase.md:44-45` have the equivalent
empty-artifacts guard. No `verify-phase.md` file exists to check (closest is
`verify-work.md`, not checked in detail). So this is not a silent data-loss bug in the
three workflows actually inspected.

**What IS a real, narrower defect:** `src/init.cts:1965-1987` — the *never-planned*
branch (phase exists in ROADMAP.md but has no directory because it hasn't been planned
yet) produces the **exact same shape** as the archived branch: `found: true,
directory: null`. Nothing in the result object distinguishes "this phase was completed
and archived" from "this phase hasn't started yet" — both collapse to
`phase_found: true, phase_dir: null`. A caller that only checks those two fields (as
`extract-learnings.md:26`'s initialize-step guard does) cannot tell "too early" from
"too late" apart. They currently happen to fail safely downstream via each workflow's
own artifact-existence guard, but that safety is incidental (each workflow re-deriving
the same distinction from a different signal) rather than something `init.phase-op`
itself communicates.

A secondary wrinkle: `expected_phase_dir` (`:1993-2003`) is computed whenever
`!phaseDir && phaseNumber && phaseName` — true for BOTH branches — so for an archived
phase it still emits a path under `.planning/phases/`, which is misleading: that
directory doesn't exist there anymore (it's been moved into the milestone archive), not
"not yet created."

## Fix

Add one field to the result object, e.g. `phase_archived: boolean` (or fold into a
tri-state `phase_status: 'active' | 'archived' | 'unplanned'`), sourced from the
`phaseInfo?.['archived']` check already computed at `:1941`. Callers that want to
distinguish the two null-dir cases (rather than relying on each workflow's own
downstream artifact check) then have a field to check instead of inferring from absence.

No behavior change required for existing callers — this is purely an additive,
disambiguating field.

## Addendum 2026-08-30 — verify-work.md checked; cnc's follow-up partially corrected back

cnc later re-audited by ref-counting `phase_found` vs `phase_dir` per workflow and
reported `secure-phase.md`/`validate-phase.md` as "real exposure" (zero `phase_found`
refs) and `verify-work.md` as parsing `phase_dir` 18× with no branch on it.

**secure-phase.md / validate-phase.md are not newly exposed** — this todo already
verified (see Problem section above) that both fail closed via the same
SUMMARY.md-presence check family as `extract-learnings.md:36`, just gated on artifact
presence rather than on `phase_found` directly. Zero `phase_found` refs does not imply
unguarded; it means the guard is expressed differently. Corrected back to cnc.

**verify-work.md is a real, but different, gap than claimed** — checked directly:
`find_summaries` step (`:165-172`) reads
```bash
ls "$phase_dir"/*-SUMMARY.md 2>/dev/null || true
```
but `$phase_dir` (lowercase) is **never assigned anywhere in this file** — every actual
assignment in the file (`:71`, `:616`) is `PHASE_DIR` (uppercase), matching every other
reference in the file (`:88-92`, `:204`, `:221`, `:269`). So this isn't "no guard for the
null-`phase_dir`-after-archive case" as cnc framed it — it's a plain variable-name typo
that makes `find_summaries` glob against `/*-SUMMARY.md` (root) **unconditionally**,
independent of whether the phase is archived, unplanned, or normal. No downstream guard
was found that checks for an empty summaries list after this step (unlike
`extract-learnings.md:36`'s explicit empty-artifacts exit). Not yet traced far enough to
confirm the full blast radius (e.g. whether `extract_tests` or later steps silently
no-op on zero summaries, or error) — flagging as a distinct defect worth its own
follow-up rather than folding it into this API-shape fix, since the root cause and file
are unrelated to `init.phase-op`'s archived/unplanned collapse.

## Cross-references

- Reported by peer session `cnc` (cross-session message, 2026-08-29), as part of a
  broader "verification that passes for a reason unrelated to what it protects" pattern
  observed across unrelated repos same day.
- Related memory pattern (peer's framing, not independently confirmed here):
  `project_gate_correct_but_aimed_at_fixture`, `feedback_verify_the_artifact_not_the_exit_code`,
  `feedback_checks_that_read_where_truth_was_not_written`.
