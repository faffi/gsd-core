---
created: 2026-08-20T23:13:00.000Z
title: "Port 4.3b — graphify: seed-floor invariant REMOVED (highest risk, CI is blind)"
area: tooling
resolves_phase: 6
severity: major
scope: Large
scope_note: Highest-risk item in the whole port campaign — the existing test suite is structurally blind to it, so a mandatory new adversarial RED test with a hand-built counterexample fixture is required, not optional
files:
  - src/graphify.cts (the applyBudget rewrite — the sole behaviour-changing commit of the block)
  - tests/graphify-query.test.cjs:560 ("the seed set is a floor the reduction never goes below")
  - tests/graphify-query.test.cjs:587 ("a larger budget never yields a smaller payload")
  - tests/graphify-query.test.cjs:513-538 (arbGraph — the fixture that cannot reach the bug)
  - .planning/runbooks/porting-local-patches-assets/graphify/4.3b-seedfloor-counterexample.cjs (proof AND RED-test template)
  - .planning/runbooks/porting-local-patches-assets/graphify/4.3b-fastcheck-blindspot.cjs (proves 0/200)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.3b — full analysis)
---

## Problem

`applyBudget` is rewritten so the seed set is no longer a floor. This is the **only**
behaviour-changing commit in the graphify block, and the highest-risk item in the entire
port campaign.

## Validation verdict — 2026-08-20, by execution

⚠⚠ **PORTING THIS PASSES CI WHILE BREAKING THE CONTRACT CI EXISTS TO PROTECT.**
**Do not treat a green test run as evidence.**

- **The regression net is structurally blind.** `tests/graphify-query.test.cjs:560` and `:587`
  encode exactly the invariant being removed. But their `arbGraph` fixture (`:513-538`) only
  produces a second seed if fast-check happens to generate the substring `auth`. Measured
  against the repo's pinned config (`numRuns: 200, seed: 42`, deterministic):
  **0 of 200 runs produced ≥2 seeds.** With one seed,
  `setFloor(Math.min(1, rankedSeeds.length))` pins the floor at the whole seed set and the
  invariant coincidentally holds.
- **Invariant break PROVEN**, and worse than "fewer nodes": on a 3-node fixture, seed `n0`
  survives at budget 120 but is **evicted at budget 150** — a *larger* budget yielding a
  *smaller* result. `total_nodes < seeds` reproduced on both synthetic and real corpora
  (`auth`: 727 seeds → 3 nodes at budget 500).
- **Fires only under budget pressure.** Above the cliff (budget > full payload) pristine and
  patched are **byte-identical**:
  ```
  PRISTINE  budget=2000  seeds=727  total_nodes=727  edges=0   budget_met=false  est=102710
  PATCHED   budget=2000  seeds=727  total_nodes=11   edges=9   budget_met=true   est=1954
  ```
- **Degenerate inputs are all handled** — zero seeds, budget 0, empty graph, all-equal scores
  (deterministic id-lexicographic tiebreak), negative budget: no exceptions, no NaN, and
  `budget_met: false` correctly reported when even the one-seed floor overshoots.
- **The two prior failed attempts are real** and transcribed in the patch comment (rev 1: floor
  shrunk only at `lo===0` → non-nested feasible sets; rev 2: floor capped at 60% of budget →
  bigger budget, fewer edges). The current approach held across 4 terms × 7 budgets — but that
  is a **coarse 7-point sweep**, and the author's own documented off-by-one dip (`argocd`,
  budget 22750, found at 357-step granularity) was **not** re-derived. Unverified, not doubted.

## Solution

**Mandatory, not optional:**

1. **Add a NEW RED test** with a deliberately multi-seed, differentiated-match-quality fixture.
   `porting-local-patches-assets/graphify/4.3b-seedfloor-counterexample.cjs` (the budget-120/150
   counterexample) is a ready template. Without this the port ships untested.
2. **Do not quietly edit `:560`/`:587`.** If they must change, state why in the same commit —
   they are the written record of the contract being removed.
3. Land **after** 4.3 and 4.4 so the behaviour change is isolated in one revertable commit.
4. Consider re-deriving the `argocd`/22750 dip at finer granularity before shipping.

Translate to `src/graphify.cts` — never edit `gsd-core/bin/lib/graphify.cjs`.

## SPEC cross-reference — 2026-08-25 (gsd-1.10.0-mods) — this is the fix contract, not just risk analysis

`~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` R1 gives the exact design this
todo's "mandatory NEW RED test" demanded but did not fully specify. Treat R1 as the acceptance
contract for whatever replaces `applyBudget`:

- **Total ordering, not tier deletion.** Rank every edge individually; ranking key in order:
  confidence → relation type → hop distance (4.4's WeakMap) → weight → lexical (final tiebreak,
  for determinism). Then a binary-search prefix finds the largest set fitting the budget.
- **Monotonicity is a named acceptance criterion, not just a desirable property**: increasing the
  budget must never decrease the returned edge count. This is precisely the invariant the current
  patch's tier approach violates (the budget-120/150 counterexample this todo already found).
- **Determinism is a separate, equally load-bearing criterion**: same corpus + same query + same
  budget → byte-identical result set across runs. Not previously stated as a requirement anywhere
  in this todo's own analysis.
- **Corroborating measurement, independent corpus:** SPEC-01 cites 82% zero-edge queries before /
  5% after (regression suite) and a separate `bootstrap-terraform` measurement of 68% planning-doc
  share — both from a different investigation than this todo's `auth`/727-seed measurement, same
  phenomenon.

Practical effect: the counterexample fixture this todo already built
(`4.3b-seedfloor-counterexample.cjs`) should be extended into two standing tests — one for
monotonicity (sweep budgets, assert non-decreasing edge count) and one for determinism (repeat the
same query N times, assert byte-identical JSON) — not just the single hand-built RED case.

## Cross-references

- Analysis: runbook §4.3b · scoring input: 4.3 todo · hop mechanism: 4.4 todo
- SPEC unit + fix contract: `~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` R1, acceptance criteria
