---
created: 2026-08-20T23:14:00.000Z
title: Port 4.4 — graphify budget-cliff: per-edge hop distance in a WeakMap
area: tooling
severity: minor
files:
  - src/graphify.cts (hopOf WeakMap — rest of the ~315-line block)
  - src/graphify.cts:280-285 (ExpandResult interface — MUST be extended, missing from runbook §2)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.4 — full analysis)
---

## Problem

Graded budget trimming needs to know each edge's hop distance from a seed. The patch tracks it
in a **`WeakMap` keyed by object identity**, deliberately *not* as a field on the edge — because
`buildQueryResponse` passes edge objects through verbatim and a field would serialize into the
response.

## Validation verdict — 2026-08-20

**Port. Low risk — INERT ON ITS OWN** (4.3b's consumer uses `(hopOf && hopOf.get(e)) ?? 0`).

- ⚠ **Translation detail MISSING from runbook §2.** The `.cjs` patch just adds keys to an
  object literal. The `.cts` port must **also extend the `ExpandResult` interface**
  (`src/graphify.cts:280-285`) with `hopOf: WeakMap<GraphEdge, number>` and
  `seedScoreOf: WeakMap<GraphNode, number>`. Miss this and the build fails.
- ⚠ **One of its two stated rationales does not apply here.** The serialization concern is
  real — but satisfied by *any* external table, not specifically by `WeakMap` (`Map.set` never
  mutates the key either). The **retention** rationale is structurally void: `graph`/`scoped`
  stays live for the whole synchronous body of `graphifyQuery`, and `hopOf`'s keys are the same
  edge objects held in `graph.edges`, so every edge is strongly reachable until the call frame
  is discarded — at which point `Map` and `WeakMap` become collectable simultaneously. graphify
  runs as a one-shot CLI subprocess per query, so the leak it guards against **cannot occur**.
  The choice is harmless; the justification is half moot. Downgrade the patch comment's
  "best-reasoned" framing rather than repeating it upstream.
- **Independently TDD-testable** — `seedAndExpand` is exported and returns the maps directly.

## Solution

Part of the graphify block (runbook §5 item 4). Land with or just after 4.3, **before** 4.3b.

## Cross-references

- Analysis: runbook §4.4 · the consumer: 4.3b todo · scoring sibling: 4.3 todo
