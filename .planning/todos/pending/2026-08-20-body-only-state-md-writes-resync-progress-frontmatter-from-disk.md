---
created: 2026-08-20T22:20:00.000Z
title: Body-only STATE.md writes resync progress frontmatter from disk
area: tooling
resolves_phase: 3
severity: blocker
scope: Large
scope_note: 17 call sites audited, 3 fix options (point/class/invert-default) with the robust one being a default inversion across the whole write path
files:
  - src/state.cts:3407 (readModifyWriteStateMd — `const resync = !options || options.resync !== false`)
  - src/state.cts:3396-3402 (the docstring naming this exact hazard, citing #3242 Bug A)
  - gsd-core/bin/gsd-tools.cjs:1172 (quick-tasks-append — closes `}, cwd);`, no options)
  - gsd-core/bin/gsd-tools.cjs:1166-1167 (comment showing the pattern was copied from two defective exemplars)
  - src/state.cts:868 (cmdStateRecordMetric — option-less)
  - src/state.cts:1086 (cmdStateAddDecision — option-less)
  - src/state.cts:1154 (cmdStateAddBlocker — option-less)
  - src/state.cts:1259 (cmdStateAddRoadmapEvolution — option-less)
  - src/state.cts:1344 (cmdStateResolveBlocker — option-less)
  - src/state.cts:679 (cmdStateAdvancePlan — `{ divergedFields }`, resync still ON)
  - src/state.cts:1599 (cmdStateRecordSession — `{ divergedFields }`, resync still ON)
  - src/state.cts:4962 (cmdStateCompletePhase — `{ divergedFields }`, resync still ON)
  - src/state.cts:4044-4048 (cmdStatePlannedPhase — the CORRECT precedent, `resync: false`)
  - gsd-core/workflows/fast.md (log_to_state — calls the helper unconditionally)
---

## Problem

`readModifyWriteStateMd` defaults `resync` **ON**, which rebuilds STATE.md's entire
`progress` frontmatter block from a filesystem scan after the transform. Callers that
only append a row or an entry to a body section inherit that default and silently
overwrite hand-curated progress counters.

```ts
src/state.cts:3407   const resync = !options || options.resync !== false;
```

**The function's own docstring already names this as the hazard** (`:3396-3402`):

> `resync: when true (default) rebuilds the entire frontmatter from disk after the
> transform. Pass { resync: false } for body-only updates (e.g. state.update on a single
> field) that **must not trample manually-curated cross-milestone progress.\* counters**
> in the frontmatter (**#3242 Bug A**).`

So there is a prior filed bug of exactly this class and a documented remedy. The defect
is call sites not honouring their own callee's contract.

## Observed corruption

Reported by a downstream `bootstrap-terraform` session running `/gsd-fast`, reproduced
there deterministically against a `cp` backup (not recalled), and confirmed by me against
1.11.0 source. `gsd-tools quick-tasks-append --task "…"` appended one table row and also
rewrote:

```
total_phases      7  -> 8
completed_phases  2  -> 3
percent          29  -> 38
```

`completed_phases` is the severe one: that repo's Phase 76 is operator-ratified NOT
CLOSED — `76-11-SUMMARY.md`'s final line reads `PHASE 76: NOT CLOSED` — but 11 `*-PLAN.md`
and 11 `*-SUMMARY.md` exist on disk, so the scan reads it complete. `total_phases` moved
because a `99-*` directory exists from `/gsd-discuss-phase 99` — discussed, never planned.

Both disagreements point the same way: **the disk looks further along than the project is,
so a default-on resync silently promotes the optimistic reading.** stdout was
`{"ok":true,"row":…,"variant":"with-status"}` — nothing about progress.

`appendQuickTaskRow` is a pure, correct text transform. The corruption is entirely in the
write path.

## Sweep — 17 call sites, and `{ divergedFields }` is a false friend

| Call site | 4th arg | resync |
|---|---|---|
| `gsd-tools.cjs:1172` quick-tasks-append | *(none)* | **ON** ← reported |
| `state.cts:868` cmdStateRecordMetric | *(none)* | **ON** |
| `state.cts:1013` cmdStateUpdateProgress | *(none)* | ON — plausibly correct |
| `state.cts:1086` cmdStateAddDecision | *(none)* | **ON** |
| `state.cts:1154` cmdStateAddBlocker | *(none)* | **ON** |
| `state.cts:1259` cmdStateAddRoadmapEvolution | *(none)* | **ON** |
| `state.cts:1344` cmdStateResolveBlocker | *(none)* | **ON** |
| `state.cts:4645` cmdStatePrune | *(none)* | ON |
| `state.cts:4817` cmdStateRebuild | *(none)* | ON — correct by definition |
| `state.cts:679` cmdStateAdvancePlan | `{ divergedFields }` | **ON** |
| `state.cts:1599` cmdStateRecordSession | `{ divergedFields }` | **ON** |
| `state.cts:4962` cmdStateCompletePhase | `{ divergedFields }` | **ON** |
| `state.cts:543` cmdStatePatch | `{ resync: shouldResync, … }` | conditional |
| `state.cts:600` cmdStateUpdate | `{ resync: shouldResync, … }` | conditional |
| `state.cts:3755` cmdStateBeginPhase | `rmwOptions` | **false** |
| `state.cts:4053` cmdStatePlannedPhase | `rmwOptions` | **false** |

Three findings:

1. **`{ divergedFields }` without `resync` still resyncs.** Three sites pass an options
   object and would read as "handled" in a grep for a 4th argument. They are not.
2. **`cmdStateRecordSession` resyncs.** The reporting operator had a prior unexplained
   incident with `state.record-session` — same mechanism, not a coincidence.
3. **Only 2 of 17 pass `resync: false`** — the two phase-transition paths that carry
   curated progress. Everything else inherits the default.

Five body-only appenders share the reported shape: record-metric, add-decision,
add-blocker, add-roadmap-evolution, resolve-blocker.

## It propagated by imitation

`gsd-core/bin/gsd-tools.cjs:1166-1167`, in the comment directly above the defective call:

> *"This mirrors the pattern every other STATE.md-mutating case in state.cts uses
> (e.g. `cmdStateAddBlocker`, `cmdStateAddDecision`)"*

Both cited exemplars are themselves option-less. The author copied a pattern that already
carried the defect — which is why a point fix is insufficient.

## Fix options

1. **Point fix** — `{ resync: false }` at `gsd-tools.cjs:1172`. Minimal, matches the
   precedent at `state.cts:4044-4048`. Leaves five siblings.
2. **Class fix** — same on the five body-only appenders, plus a decision on the three
   `{ divergedFields }` sites.
3. **Invert the default** — make resync opt-**in**. Larger blast radius, but the current
   default is wrong for 5-8 of 17 callers, right for ~3, and inverting removes the
   `{ divergedFields }` trap entirely. Robust answer.

## Observability — arguably worth more than the fix

A silent derived write that can raise `completed_phases` from file existence is a claim
about project state that no output mentions. Emitting `progress: completed_phases 2 -> 3
(derived)` would turn a silent corruption into an obvious event, **even when resync is
legitimately on**. In the reporting repo this was caught only because the operator had a
prior incident and backed the file up first. It would also have surfaced the earlier
record-session incident.

## Downstream exposure

`gsd-core/workflows/fast.md`'s `log_to_state` step calls this helper unconditionally
whenever a *Quick Tasks Completed* table exists. So following `/gsd-fast` as written
corrupts any STATE.md whose curated progress disagrees with a disk scan — a workflow that
reads as append-only.

## Second defect in the same write path — ALREADY FIXED UPSTREAM in 1.11.0

**Resolved; recorded so the investigation is not repeated.** A downstream 1.10.0 session
measured `\\uXXXX` escapes in STATE.md's `stopped_at` doubling their backslash run on
every write — 1, 2, 4, 8 across three appends, exponential and unbounded. Their earlier
"em-dash double-encoding" framing was withdrawn on measurement (mojibake 0 before and
after); no em-dash is transformed.

**Fixed by `507db384` (2026-08-14), first tagged v1.11.0~63:**

> `fix(#3497): unescape double-quoted scalars on parse so round-trips stop doubling backslashes (#3521)`

| | v1.10.0 | v1.11.0 |
|---|---|---|
| `escapeDoubleQuoted` (write) | present | present |
| `unescapeDoubleQuoted` (read) | **absent** | present |
| `parseQuotedScalar` (read) | **absent** | present |

1.10.0 had a write side and **no read side at all** — which is why every backslash
doubled, including `\n` and `\t`. Not a branch failing to run; the function did not
exist. Verified on 1.11.0: `"\\\\u2014"` → `"\\u2014"`, `"\\n"` → newline,
`"\\d+"` → unchanged.

**Migration behaviour, measured on 1.11.0:** an already-corrupted 4-backslash value stays
at 4 across three round-trips. Upgrading is a fixed point — growth stops immediately, the
migration write does not double once more, and it does **not** self-heal. Existing
inflated runs freeze at whatever length they reached; repairing them is a separate,
scoped one-time cleanup.

**Consequence for THIS todo:** the earlier "land both or neither" conclusion is void. The
unbounded defect closes by upgrading. The resync defect above is **still live at 1.11.0**
— `src/state.cts:3407` and `gsd-tools.cjs:1172` re-verified in the 1.11.0 tree, and the
full sweep table still applies. Upgrading does nothing for it.

### The methodological error, recorded because it recurred

Twice in this exchange I read 1.11.0 source and described it to a peer on 1.10.0 — first
`audit-open`'s `acknowledged` block, then `unescapeDoubleQuoted`'s line numbers, neither
of which exists in their build. In the second case I quoted a function at them as proof of
a mechanism, and they refuted it by measurement because the function was not there.

Running a command on their version and confirming it works is **not** verifying that the
payload or the code path I am describing exists there. Any claim citing `src/*.cts` needs
a `git show <their-tag>:` check before it goes to someone on another version.

## Provenance

Repro, isolation, and the correction to the encoding claim: a downstream
`bootstrap-terraform` session. The 17-site sweep, the `{ divergedFields }` false friend,
`cmdStateRecordSession` corroborating the operator's prior incident, the
propagated-by-imitation trail, and the `resync: false`/`stopped_at` scoping answer:
this session, against 1.11.0 source.
