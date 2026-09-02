---
created: 2026-08-21T22:34:56.330Z
title: state advance-plan silently falls back to root STATE.md on a dangling active-workstream pointer
area: tooling
resolves_phase: 2
severity: blocker
scope: Small
scope_note: Two narrow, localized fixes (surface the fallback in the response, assert statePath matches what was requested) plus a quick scope-check on workstream complete — no sweep required
files:
  - src/state.cts:657 (cmdStateAdvancePlan — `planningPaths(cwd).state`, no `ws` passed explicitly)
  - src/planning-workspace.cts:124-141 (planningDir — resolves `ws` from `process.env['GSD_WORKSTREAM']` only, once entered)
  - gsd-core/bin/gsd-tools.cjs:4131-4152 (CLI-entry `resolveActiveWorkstream` + `applyResolvedWorkstreamEnv` — the actual pointer-chain resolution, correctly wired for the *normal* case)
  - src/active-workstream-store.cts:23-26 (#3579 comment — "self-healed (cleared) a present-but-unresolvable pointer... silently falling through to a fallback marker")
  - src/state.cts:712 (`reconcileReportedFields` — reconciles against whatever `statePath` resolved to; cannot detect a wrong-file resolution, only a wrong-field one)
---

## Problem

Reported by a peer session (`bootstrap-terraform-75`, cross-session message, 2026-08-21) working
a workstream (`tenant-vpc-reach`, v1.12, `.planning/workstreams/tenant-vpc-reach/STATE.md`,
`current_plan: 5`) alongside an unrelated root `.planning/STATE.md` (v1.11, `current_phase: 76`).
`gsd-tools state advance-plan` returned `current_plan: 2` in its JSON twice in a row while leaving
the workstream's real STATE.md untouched — no error, no warning, exit 0. The executor caught it
only by re-reading the artifact after the call; every subsequent plan in that phase then bypassed
the verb entirely and hand-edited STATE.md.

**Empirically reproduced in this repo** (not just source-read) — minimal repro:

```bash
# fixture: root .planning/STATE.md (Current Plan 1/3) +
#          .planning/workstreams/tenant-vpc-reach/STATE.md (Current Plan 5/8)
node gsd-core/bin/gsd-tools.cjs query workstream.set tenant-vpc-reach --raw --cwd "$REPRO"
# ... normal advances correctly target the workstream file (5→6→7...) ...

# Now simulate the workstream directory becoming unavailable while the pointer
# still names it — e.g. renamed, or archived via `workstream complete` without
# clearing the pointer first:
mv "$REPRO/.planning/workstreams/tenant-vpc-reach" "$REPRO/.planning/workstreams/tenant-vpc-reach.bak"

node gsd-core/bin/gsd-tools.cjs state advance-plan --cwd "$REPRO" --raw
# stdout: true   stderr: (empty)   exit: 0
# root .planning/STATE.md's `current_plan` silently advances (2→3).
# The (still-pointed-at, now-missing) workstream file is obviously never touched.
```

**Root cause, corrected from an initial (wrong) hypothesis:** it is NOT that `planningPaths`/
`planningDir` bypass the pointer-file resolution system — `bin/gsd-tools.cjs`'s CLI entry
(`:4131-4152`) *does* correctly call `resolveActiveWorkstream` (the full `--ws` > env >
session-pointer > shared-marker chain from `active-workstream-store.cts`) and injects the result
into `process.env.GSD_WORKSTREAM` before dispatch — verified empirically: a valid pointer routes
`advance-plan` to the correct workstream file every time.

The actual defect is narrower and matches the failure mode `active-workstream-store.cts:23-26`'s
own `#3579` comment already names: when the pointer is **present but unresolvable** (the workstream
directory it names no longer exists — renamed, moved, or archived via `workstream complete` without
clearing the pointer), resolution self-heals by silently falling through to "no workstream" (i.e.
root), and nothing in `state.cts` surfaces that fallback to the caller. `reconcileReportedFields`
(`:712`) only reconciles which *fields* got persisted in whatever file `statePath` ended up being —
it has no way to detect that `statePath` itself resolved to the wrong file.

## Solution

Two independent fixes, smallest-safe first:

1. **Surface the fallback.** When `resolveActiveWorkstream` self-heals a present-but-unresolvable
   pointer, the JSON response from any subsequently-dispatched state-mutating command should carry
   a field (e.g. `workstream_pointer_cleared: "<name>"`) or emit a stderr warning — silent recovery
   is fine, silent recovery with zero signal to a caller who expected a specific workstream is not.
2. **`cmdStateAdvancePlan` (and siblings) should assert `statePath` exists and is the file the
   caller expected**, not just "some STATE.md was found." At minimum, when a `--ws`/env/pointer
   name was supplied but resolution fell back to root, that is distinguishable from "no workstream
   requested at all" and should not look identical in the output.

Scope check before implementing: confirm whether `workstream complete` (`workstream.cts`) clears
the active pointer when it archives the workstream it points at — if not, that is the most direct
real-world trigger for this exact symptom, independent of the peer's session's specific cause.

## Cross-references

- Cross-session bug report: `bootstrap-terraform-75` (Phase 82, tenant-vpc-reach workstream, v1.12),
  2026-08-21.
- `SEED-065-state-md-custom-format-vs-gsd-scraper.md` (peer's repo, `main`) — adjacent problem
  (custom STATE.md prose defeating the scraper); peer flagged as possibly same root-cause family,
  unconfirmed here.
- `#3579` (referenced in `active-workstream-store.cts:23-26`) — prior fix for a related
  bootstrap-vs-consuming-read race in the same resolution chain; this todo's symptom is the
  silent-fallback side of the same self-heal behavior, not a regression of #3579 itself.
