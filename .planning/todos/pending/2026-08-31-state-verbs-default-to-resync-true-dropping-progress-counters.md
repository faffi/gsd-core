---
created: 2026-08-31T00:00:00.000Z
title: "6 of 9 audited state.cts verbs default to resync:true and silently drop progress.* counters on write — the #3242 Bug A fix (resync:false) is applied at only 2 of ~14 call sites"
area: tooling
severity: blocker
scope: Medium
scope_note: Not a per-site patch — src/state.cts:201's own documented policy ("resync is driven by shouldResyncStateProgress rather than defaulting") already names the correct fix; applying it means computing a resync value at each of the ~9 unguarded call sites (or inverting the default) rather than hand-patching one verb. Empirical sweep done; implementation not started.
files:
  - src/state.cts:1640 (cmdStateRecordSession's readModifyWriteStateMd call — no options, confirmed clobbers)
  - src/state.cts (cmdStateRecordMetric's readModifyWriteStateMd call — no options, confirmed clobbers by empirical repro)
  - src/state.cts (cmdStateAddDecision's readModifyWriteStateMd call — no options, confirmed clobbers by empirical repro)
  - src/state.cts (cmdStateAddBlocker's readModifyWriteStateMd call — no options, confirmed clobbers by empirical repro)
  - src/state.cts (cmdStateAddRoadmapEvolution's readModifyWriteStateMd call — no options, confirmed clobbers by empirical repro)
  - src/state.cts (cmdStateResolveBlocker's readModifyWriteStateMd call — no options, confirmed clobbers by empirical repro, re-tested with a real blocker to resolve)
  - src/state.cts:201 (doc comment stating the intended policy: resync should be computed via `shouldResyncStateProgress`, not defaulted)
  - src/state.cts:650,785 (cmdStatePatch, cmdStateUpdate — the two verbs that DO compute resync correctly, both via a `shouldResync`-shaped computed value, which is why a literal-string `grep "resync: false"` misses one of them)
---

## Problem

Follow-on from `2026-08-30-context-guard-prose-remedy-doesnt-own-the-field-it-protects.md`,
which found that `cmdStateRecordSession` defaults to `resync: true` (rebuilding the entire
STATE.md frontmatter from disk on every call) and that this is an already-numbered,
documented bug (`#3242 Bug A`) with an established fix (`resync: false`) already applied to
`state.update`. `gsd-core-working` (cross-session message, 2026-08-31) asked the obvious
next question: is `record-session` the only verb missing the fix, or one of several?

**Verified twice before answering, because the first grep pass was itself wrong.**
`gsd-core-working` first ran `grep -rn "resync: false" src/*.cts`, got one hit
(`cmdStatePlannedPhase`), and nearly reported that `state.update` does NOT have the fix and
that the earlier finding's supporting claim was wrong. They caught it themselves before
sending: `cmdStateUpdate`'s `resync` value is *computed* (`{ resync: shouldResync, ... }` at
`state.cts:785`), not a literal `false`, so a literal-string grep silently misses it. The
codebase's own stated policy, quoted directly from `state.cts:201`: **"`resync` is driven by
`shouldResyncStateProgress` rather than defaulting."** Two verbs implement that policy today
(`cmdStatePatch:650`, `cmdStateUpdate:785`, both via a computed value) out of roughly
fourteen `readModifyWriteStateMd` call sites in the module.

**Empirical sweep, 2026-08-31** — seeded a synthetic `.planning/STATE.md` with a
`progress: { completed_phases: 4, percent: 50 }` block (no options passed, so every tested
verb's default resync behavior is what's under test) and ran each of the 9 verbs that pass
no resync-bearing options (`cmdStateRecordMetric`, `cmdStateUpdateProgress`,
`cmdStateAddDecision`, `cmdStateAddBlocker`, `cmdStateAddRoadmapEvolution`,
`cmdStateResolveBlocker`, `cmdStatePrune`, `cmdStateRebuild`, `cmdStateRecordSession`) via
their real CLI subcommands against a fresh copy of the fixture each time, then diffed:

| verb | CLI subcommand | result | evidence |
|---|---|---|---|
| `cmdStateRecordSession` | `state record-session --stopped-at ...` | **clobbers** | confirmed prior todo |
| `cmdStateRecordMetric` | `state record-metric --phase --plan --duration --tasks --files` | **clobbers** | wrote successfully (`true`), `progress:` block absent after |
| `cmdStateAddDecision` | `state add-decision --phase --summary` | **clobbers** | wrote successfully, `progress:` block absent after |
| `cmdStateAddBlocker` | `state add-blocker --text` | **clobbers** | wrote successfully, `progress:` block absent after |
| `cmdStateAddRoadmapEvolution` | `state add-roadmap-evolution --phase --action --note` | **clobbers** | wrote successfully, `progress:` block absent after |
| `cmdStateResolveBlocker` | `state resolve-blocker --text` | **clobbers** | re-tested with a real blocker present to resolve (first pass was a false-negative no-op — nothing to resolve); wrote successfully, `progress:` block absent after |
| `cmdStateUpdateProgress` | `state update-progress` | **inconclusive** | no-op against this fixture (`false`, file never written) — needs real on-disk phase/plan data to exercise meaningfully; likely SHOULD touch progress by design, not a clear defect candidate |
| `cmdStatePrune` | `state prune --dry-run` | **inconclusive** | no-op — fixture had no metrics history old enough to prune; not re-tested without `--dry-run` |
| `cmdStateRebuild` | `state rebuild` (no `--dry-run`) | **inconclusive** | no-op even without dry-run against this fixture (`false`) — rebuild is explicitly meant to reconstruct frontmatter, so not a "should preserve" candidate regardless |

**6 of 9 tested verbs confirmed to silently drop `progress.*` on write; the 3 inconclusive
ones are inconclusive because the fixture gave them nothing to do, not because they were
shown safe.** This confirms `gsd-core-working`'s framing: this is not "one call site missed
the policy," it's "the policy is implemented at 2 of ~14 call sites" — a systemic gap, not
an isolated oversight in `record-session`.

## Fix

Per the codebase's own stated intent (`state.cts:201`), the fix is not per-site patching —
compute `resync` via the same `shouldResyncStateProgress`-shaped logic `cmdStatePatch` and
`cmdStateUpdate` already use, applied at each of the confirmed-affected call sites (and
audited at the remaining `readModifyWriteStateMd` call sites in the module, since this sweep
covered 9 of ~14). Alternative: invert `readModifyWriteStateMd`'s default from
`resync: true` to `resync: false`, and have the small number of verbs that legitimately need
a full rebuild (`cmdStateRebuild`, likely `cmdStateUpdateProgress`) opt in explicitly — fewer
call sites to get right, since "don't touch progress" is the correct default for a
body-only/session-metadata/decision-log write, and "do touch progress" is the exception.

## Cross-references

- Parent finding: `2026-08-30-context-guard-prose-remedy-doesnt-own-the-field-it-protects.md`
  (the `cmdStateRecordSession`-specific instance, folded back to point here for the full
  sweep).
- Discriminating question posed by `gsd-core-working` (cross-session message, 2026-08-31);
  this todo is the empirical answer.
- Not yet audited: the remaining `readModifyWriteStateMd` call sites beyond the 9 tested here
  (this module has roughly 14 total per `gsd-core-working`'s count) — `cmdStateBeginPhase`,
  `cmdStatePlannedPhase`, and `cmdStateCompletePhase`'s `rmwOptions` path pass resync-bearing
  options already per their earlier count and were not re-tested here.
