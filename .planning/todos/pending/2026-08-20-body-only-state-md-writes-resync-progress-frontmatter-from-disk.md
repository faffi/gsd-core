---
created: 2026-08-20T22:20:00.000Z
title: Body-only STATE.md writes resync progress frontmatter from disk
area: tooling
severity: blocker
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

## Second, INDEPENDENT defect in the same write path — backslash-escape doubling

The original report described "em-dashes came back double-encoded". **The reporter
withdrew that on measurement** — mojibake count was 0 before and 0 after, and literal
U+2014 went 1003 -> 1006, the +3 being the appended row's own text. No em-dash is
transformed. `platformReadSync`/`normalizeContent` are exonerated; do not re-derive the
encoding theory from the original wording.

What actually happens: existing `\uXXXX` escapes inside `stopped_at` (a ~12.9 KB
double-quoted scalar holding 19 of them) have their **backslash run doubled on every
write** — 1, 2, 4, 8 after three appends. Line 8 grew 12,883 -> 13,016 bytes; the first
write added exactly 19 bytes for 19 escapes, which pinned the mechanism.

**The asymmetry is in `src/frontmatter.cts` and is provable from source:**

- **Write** — `escapeDoubleQuoted:349-357` escapes *every* backslash unconditionally
  (`.replace(/\\/g, '\\\\')`).
- **Read** — `unescapeDoubleQuoted:122-152` recognizes only `\\`, `\"`, `\n`, `\t`,
  `\r`, `\xHH`. Anything else hits `:148-149` — `out += '\\' + next; // unrecognized
  escape — keep literally`. **`\u` is not in the recognized set.**

So `\u2014` survives the read as six literal characters and the write re-escapes its
backslash.

Note the writer emits `\xHH` for controls and **never emits `\uXXXX` in any branch** —
so GSD's own frontmatter writer did not create those escapes. Something else wrote them,
and whatever it was is still running.

### `resync: false` does NOT suppress it

Answered from source, and it changes the fix plan. `src/state.cts:3159-3160`:

> *"`syncStateFrontmatter` re-derives frontmatter status/stopped_at from the body on
> every write"*

`:3156`'s `preFm` snapshot — the thing `resync: false` restores — is scoped to the
**progress block**. `stopped_at` is protected by a separate #1230 preserve-when-unchanged
delta (`preBodyStoppedAt`, `:3177`) that is not gated on `resync`. The two snapshots are
deliberately independent (`:3164-3165`).

**Consequence: the one-line `{ resync: false }` fix closes the `completed_phases` bug and
leaves the escape doubling live.** Land both or neither.

### Open — possibly a THIRD defect

The 2ⁿ growth does not follow from the asymmetry alone. `\\` **is** recognized on read
(`:131-132`), so a round-trip of `\\u2014` should unescape and re-escape to itself —
stable at 2, not doubling. Exponential growth implies the value never reaches the unescape
branch. `parseQuotedScalar:163` only unescapes when the scalar both starts and ends with
`"`; otherwise it strips quotes **without unescaping**. A 12.9 KB scalar is a plausible
candidate for failing that delimiter test.

If confirmed, that is a third distinct defect — a long or unusual scalar silently skipping
unescape while still being escaped on write. Test posed to the reporter: does the parsed
value pass `startsWith('"') && endsWith('"')`?

### Why both defects evaded detection

`grep -c '—'` returns 19 before and 19 after, because `\\u2014` still *contains*
`\u2014`. A count-based probe is structurally blind to the corruption it is measuring.
It surfaced only via byte-length delta and a `cmp` char offset. Same shape as
`counts.todos` reporting a display cap: a measurement that looks like verification and
is not.

## Provenance

Repro, isolation, and the correction to the encoding claim: a downstream
`bootstrap-terraform` session. The 17-site sweep, the `{ divergedFields }` false friend,
`cmdStateRecordSession` corroborating the operator's prior incident, the
propagated-by-imitation trail, and the `resync: false`/`stopped_at` scoping answer:
this session, against 1.11.0 source.
