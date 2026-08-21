---
created: 2026-08-20T23:15:00.000Z
title: Port 4.5 — graphify --exclude-file-types (corpus membership vs retrieval eligibility)
area: tooling
severity: major
files:
  - src/graphify.cts (filterGraphByFileType ~95 lines — THE IMPLEMENTATION, omitted from an earlier draft)
  - src/graphify-command-router.cts (+33 — flag parsing and validation only)
  - gsd-core/references/planner-load-graph-context.md (call site + matching-model docs)
  - agents/gsd-phase-researcher.md (call site + matching-model docs, +58/-5 — largest agent change)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.5 — full analysis)
---

## Problem

New flag separating **corpus membership** from **retrieval eligibility**. Agent call sites pass
`document` so the planner stops spending budget on the project's own planning notes — **68% of
nodes in the measured repo** — while rules can still join against them.

## Validation verdict — 2026-08-20, by execution

**Port. Most valuable item in the set. But two framing corrections and one sourcing gap.**

- ⚠ **`src/graphify.cts` was OMITTED from an earlier file list.** The router hunk is purely CLI
  parsing plus one call. `filterGraphByFileType` — the corpus/eligibility split, the
  `matched_nodes_excluded` counting, edge-consistency filtering, and the wiring into
  `graphifyQuery`/`applyBudget`/`buildQueryResponse` — is **all in `graphify.cts`**. A branch
  built from the old list would ship **a flag with no behaviour behind it.**
- ⚠ **"Purely additive / default-off" is true only for UNBUDGETED queries.** Measured: with no
  flag and no budget, patched output is byte-identical to pristine. With `--budget 200` and no
  flag, they differ (pristine 4 nodes/0 edges, patched 3/1). The filter never ran — that
  divergence is **4.3b's invariant removal**, not this flag. Never state the additive claim
  without that carve-out.
- ⚠ **The `.graphifyignore` rationale is UNSOURCED.** The patch comment argues upstream "only
  offers `.graphifyignore`, which deletes facts". That string appears **only inside the patch
  itself** — nowhere in 1.11.0 source, compiled output, docs, or git history, and no
  `.graphifyignore` file exists anywhere on this machine. It may refer to the separate external
  `graphify` tool rather than gsd-core. **Get a citation before shipping this rationale
  upstream**, or drop the comparison.
- **More defensive than first credited.** Every malformed input **fails loudly**, none silently
  no-ops: empty / whitespace / separator-only → usage error exit 1; unknown type →
  `Unknown file_type(s)` exit 1; wrong case (`Document`) → rejected, not silently non-matching;
  duplicates dedupe. The router validates against
  `KNOWN_FILE_TYPES = ['code','document','rationale','concept']` **before** calling the filter.
  The edges-vs-links key hazard its own comment names is genuinely closed — tested with a `links`
  fixture, it detected the key, dropped the node and both touching edges.
- **The 68% figure** is internally consistent (15,069 document + 5,573 code + 1,489 rationale +
  88 concept = 22,219 exactly) and names its corpus (`bootstrap-terraform`), but is **not
  reproducible off that repo**.
- **Docs bonus, independently shippable:** both call-site files teach the matching model —
  *"Choose the term the graph knows, not the concept. Matching is literal, case-insensitive
  substring — no stemming, no synonyms, no fuzzy matching."* Useful even if the flag never lands.

## Solution

First of the graphify block (runbook §5 item 4) — do it before 4.3/4.4/4.3b.

**Upstream viability: strong.** Additive, defaults preserved, clear rationale (minus the
`.graphifyignore` claim).

## Cross-references

- Analysis: runbook §4.5 · file→concern map: runbook §4b
