---
created: 2026-08-20T23:15:00.000Z
title: Port 4.5 — graphify --exclude-file-types (corpus membership vs retrieval eligibility)
area: tooling
severity: major
scope: Medium
scope_note: A real ~95-line new function plus router wiring and docs across two agent files; already well-validated, but the .graphifyignore rationale needs a citation before shipping upstream
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

## SPEC cross-reference — 2026-08-25 (gsd-1.10.0-mods) — adds two requirements not previously scoped here

`~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` covers this flag as part of a
4-file unit (with 4.3/4.3b/4.4) and adds real new scope beyond what this todo currently lists:

- **R3 — a `scope` field on the wire shape (NEW, not currently in this todo's file list or
  requirements).** Query output must distinguish "term absent from the corpus" from "term filtered
  out by `--exclude-file-types`" — without it, a caller (the planner's retry policy) cannot tell
  "search harder" from "stop, there is nothing here." This needs implementing inside `graphify.cts`
  alongside `filterGraphByFileType`, and needs a corresponding doc update.
- **R5 — planner-doc corrections beyond what's currently captured**, all in
  `gsd-core/references/planner-load-graph-context.md` (already in this todo's file list, but the
  specific edits were not enumerated before):
  - budget guidance **2000 → 20000** (the current 2000 budget is why the 47×/51× overshoot this
    todo's own Problem section measures happens at all)
  - add `--exclude-file-types document` to the documented invocation
  - replace "pick a keyword that captures the phase goal" with literal-substring term-selection
    rules (the graph does no stemming/synonym matching — a wrong mental model here silently
    produces bad queries)
  - replace the retry policy with a narrow two-signal rule: retry ONLY on `total_nodes: 0`, or
    `total_edges: 0 && budget_met: true`. Explicitly NOT retry triggers, each measured net-negative
    on a 45-defect retrospective: 1–2 nodes returned (no signal), a `contains`-dominated result set
    (naive dominance-retry measured **net −1**: lost 6 defects to gain 5)
  - read the new `scope` field to distinguish absent-term from filtered-out

Acceptance evidence from the same retrospective: honest recall at budget 20000 reached **14/16**
reachable defects (after removing 7 self-referential hits from a contaminated corpus — quote that
number, not the uncorrected one).

Practical effect: this todo's scope grows from "flag + filter function" to "flag + filter function
+ scope field + full retry-policy rewrite in the planner doc." Land all four SPEC-01 files (this
one, 4.3, 4.3b, 4.4) together — a partial port ships a doc instructing agents to read `scope`/
`matched_nodes_excluded` fields that don't exist yet.

## Cross-references

- Analysis: runbook §4.5 · file→concern map: runbook §4b
- SPEC unit: `~/Desktop/gsd-1.10.0-mods/SPEC-01-graphify-retrieval-quality.md` R2 (confirms filter timing), R3 (new `scope` field), R4 (confirms CLI validation), R5 (planner doc rewrite)
