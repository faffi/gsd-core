---
created: 2026-08-31T00:00:00.000Z
title: "7 of 9 audited state.cts verbs default to resync:true and silently drop progress.* counters on write — the #3242 Bug A fix (resync:false) is applied at only 2 of ~14 call sites"
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
  - src/state.cts:5438-5495 (cmdStatePrune — non-dry-run write path confirmed clobbers; --dry-run branch never calls readModifyWriteStateMd at all)
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
| `cmdStatePrune` | `state prune --keep-recent 3` (no `--dry-run`, real `- [Phase 2] ...` entry seeded) | **clobbers** | resolved below — `--dry-run` structurally cannot write; the real write path does, confirmed |
| `cmdStateRebuild` | `state rebuild` (no `--dry-run`) | **inconclusive** | no-op even without dry-run against this fixture (`false`) — rebuild is explicitly meant to reconstruct frontmatter, so not a "should preserve" candidate regardless |

**7 of 9 tested verbs confirmed to silently drop `progress.*` on write; the 2 remaining
inconclusive ones are inconclusive because the fixture gave them nothing to do, not because
they were shown safe.** This confirms `gsd-core-working`'s framing: this is not "one call
site missed the policy," it's "the policy is implemented at 2 of ~14 call sites" — a
systemic gap, not an isolated oversight in `record-session`.

## Fix

**Read this section's argument as the reason to act, not the sweep above.** The empirical
sweep establishes the *mechanism* (resync-on-write silently drops progress counters) and
made the seven affected sites findable. It does not, by itself, establish that exactly
seven is the right number to fix — "we tested seven and they clobbered" invites "did you
test enough?" The argument below does not depend on how many verbs were tested: it shows
that these seven **cannot** hit the resync trigger, structurally, regardless of fixture or
test coverage. That's what closes the question, not the count.

**Simplified 2026-08-31, by `gsd-core-working`, verified directly.** `shouldResyncStateProgress`
(`src/state.cts:307-313`) only returns `true` when the fields being written intersect a
three-field trigger set, `STATE_PROGRESS_RESYNC_FIELDS = new Set(['Progress', 'Total Plans
in Phase', 'Total Phases'])` (`src/state.cts:301-305`). Confirmed both real call sites feed
it exactly the fields being written: `cmdStatePatch:633` passes `Object.keys(patches)`,
`cmdStateUpdate:766` passes `[field]`. None of the seven confirmed-clobbering verbs ever
write any of those three field names — `record-session` writes session labels,
`record-metric` writes a metric row, `add-decision`/`add-blocker`/`add-roadmap-evolution`/
`resolve-blocker` write body sections, `prune` removes list-item entries. So calling the
helper at any of the seven would provably return `false` every time — **"apply the
documented policy" and "hardcode `resync: false`" are the same change at all seven sites**,
because none of them can write a progress-trigger field. No computed-value threading needed;
seven literal `{ resync: false }` additions, each independently justifiable by the verb's
own field set.

**Keep the default-inversion question separate.** `readModifyWriteStateMd` still defaults to
`resync: true`, so the *next* verb added to this module inherits the same defect silently —
that's a distinct, larger-blast-radius concern (changes behavior at every site currently
relying on the rebuild, including the two below that couldn't be tested) and wants its own
change and its own tests, not folded into the seven-site fix.

**Shape of the recommended fix: one PR, seven sites, seven tests** — concern: "state verbs
that cannot write a progress-trigger field must not trigger a frontmatter rebuild." The
default-inversion becomes a follow-up, with the two untestable verbs (`update-progress`,
`rebuild`) as its open question.

## `prune` resolution — read `state-transition.cts` directly rather than guessing fixtures again

`gsd-core-working` found two independent reasons the first two `prune` attempts no-op'd:
(1) `cmdStatePrune`'s `--dry-run` branch (`state.cts:5480-5495`) reads the file directly and
never calls `readModifyWriteStateMd` at all — structurally cannot write, so any `--dry-run`
attempt is void regardless of fixture; (2) the non-dry-run path's prunable-entry predicates
match **list-item lines**, not section headings — `## Decisions` (or `Decisions Made` /
`Accumulated...Decisions`) requires entries shaped `- [Phase N] ...`; `## Metrics` is not a
prunable section at all (no `pruneSectionSpan` call for it), so seeding entries there was
always inert. Final run, matching both constraints (`current_phase: 10`, `## Decisions` with
a real `- [Phase 2] ...` entry, `--keep-recent 3`, **no** `--dry-run`): the write succeeded
(`true`, the decision entry was actually pruned) and the `progress:` block was gone
afterward. **`prune` clobbers via the same mechanism as the other six.**

`update-progress` and `rebuild` remain untested/inconclusive and are plausibly meant to
rebuild by design — left as the default-inversion follow-up's open question, not chased
further per `gsd-core-working`'s "wouldn't spend more than one run on this" guidance.

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
