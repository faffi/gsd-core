---
created: 2026-08-20T23:12:00.000Z
title: "Port 4.3 — graphify seed-floor: score seeds by match quality"
area: tooling
resolves_phase: 6
severity: minor
scope: Small
scope_note: One exported, directly TDD-testable function, inert on its own; land before 4.3b and after 4.5 per the graphify cluster's sequencing
files:
  - src/graphify.cts (seedAndExpand — scoring only; part of the ~315-line block)
  - src/graphify.cts:280-285 (ExpandResult interface — must gain seedScoreOf, see 4.4)
  - .planning/runbooks/porting-local-patches-assets/graphify/4.3-pristine-vs-patched.cjs
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.3 — full analysis)
---

## Problem

A substring sweep is treated as an inviolable floor. `"auth"` also matches
author/authorization/authentik → **701 seeds, 95,231 tokens, 47× the planner's 2,000-token
budget** (measured, in the patch comment).

The patch scores each seed by match quality so the budget trimmer can shed weak matches.

## Validation verdict — 2026-08-20

**Port. Low risk — this commit is INERT ON ITS OWN.**

- **Splittability confirmed.** 4.3 changes no behaviour by itself: 4.3b's consumers use
  optional chaining (`seedScoreOf?.get(b) ?? 1`). **4.3b is the sole behaviour-changing
  commit** in the graphify block. Still independently TDD-testable — `seedAndExpand` is
  exported and returns the maps directly.
- **Scoring only, no filtering at that site** — a deliberately conservative seam. Verify the
  trimmer is the sole consumer.
- ⚠ **The measured numbers drift.** `4.3-pristine-vs-patched.cjs` reads a **live** project
  graph: 727 seeds today vs the patch comment's 701, ~51× vs 47×. The phenomenon re-derives;
  the exact digits do not. Do not cite a stale figure as current.
- **Upstream viability: strong**, given the measurement — but an upstream PR needs a
  reproducible benchmark rather than a one-off number.

## Solution

Part of the graphify block (runbook §5 item 4), after 4.5. Land as its own commit **before**
4.3b so the behaviour change is isolated and revertable.

Translate from the `bin/lib/graphify.cjs` patch hunk to `src/graphify.cts` — never edit the
compiled lib.

## SPEC cross-reference — 2026-08-25 (gsd-1.10.0-mods)

`~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` packages 4.3 + 4.3b + 4.4 + 4.5
as **one unit** ("a partial port yields a document instructing agents to read fields that are not
emitted"). It reconfirms this commit's scoring-only, inert-alone framing and supplies the ranking
key 4.3b's fix must use scoring output for (confidence, relation type, hop distance, weight,
lexical tiebreak — see 4.3b's amendment). No new requirement lands on 4.3 itself; land it as part
of that four-todo unit, not standalone.

## Cross-references

- Analysis: runbook §4.3 · the behaviour change that consumes this: 4.3b todo · mechanism: 4.4 todo
- SPEC unit: `~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` (implement with 4.3b, 4.4, 4.5)
