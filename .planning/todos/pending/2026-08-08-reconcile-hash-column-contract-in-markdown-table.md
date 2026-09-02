---
created: 2026-08-08T11:57:14Z
title: Reconcile the # column's two conflicting writers
area: tooling
resolves_phase: 5
severity: major
scope: Medium
scope_note: Small code delta (one optional field, one fallback branch) but three open design questions a maintainer must answer first; blocks the escape-description todo's option 2
files:
  - src/markdown-table.cts:710-716 (QuickTaskFields — no `id` field)
  - src/markdown-table.cts:737 (appendQuickTaskRow)
  - src/markdown-table.cts:762 (rowNumber = parsed.value.rows.length + 1)
  - src/markdown-table.cts:765 (case '#': returns the ordinal)
  - gsd-core/workflows/quick.md:619 (hand-rolled row writes ${quick_id} into the same column)
  - gsd-core/workflows/quick.md:624 (same, non-VALIDATE_MODE variant)
---

## Problem

**Reported by a downstream consumer: the `secops-plugin` project.** Verified against
this repo at HEAD `343835fa`; every line number above was read directly from that HEAD.

The `#` column of STATE.md's "Quick Tasks Completed" table has **two writers with two
incompatible contracts.**

**Writer A — the schema-backed helper (`src/markdown-table.cts`):**

- `QuickTaskFields` (`:710-716`) declares exactly `description`, `date`, `commit`,
  `status?`, `directory?`. **There is no `id` field**, so a caller has no way to
  supply a quick-id.
- `appendQuickTaskRow` (`:737`) computes `const rowNumber = parsed.value.rows.length + 1;`
  (`:762`) and emits `case '#': return escapeCell(String(rowNumber));` (`:765`).
- So `#` gets a **position-derived ordinal**.

**Writer B — quick.md's hand-rolled template (`gsd-core/workflows/quick.md:619, :624`):**

- Fills the same `#` column with `${quick_id}`.

### Why this is the bigger of the two defects

- A table written by both writers contains a **mix of quick-ids and row ordinals in
  the same column**, and neither writer can tell which one it is looking at. There is
  no discriminator.
- The ordinal is **position-derived**, so it is not even stable: delete or reorder a
  row and every subsequent `#` silently means something different.
- **`/gsd-fast` is structurally incapable of emitting a quick-id.** There is no field
  to pass one through, so no caller can fix this from the outside — it can only be
  fixed here, in `QuickTaskFields`.

### It also blocks the correct fix for the companion defect

The companion todo `2026-08-08-escape-description-in-quick-md-7c-table-row.md` records
an unescaped-`|` defect in `quick.md` step 7c that **already caused a production
failure** in `secops-plugin` on 2026-08-05: a description containing the literal
`Path | None` produced a 7-cell row in a 6-column table, sat latent for two days, then
broke every subsequent programmatic append with `row 22 has 7 cells, expected 6`,
exit 1.

The right fix there is to route step 7c through this same schema-backed helper — which
`quick.md:627` already points fast.md at. **Doing that today would silently replace
quick-ids with row ordinals in the `#` column.** That is precisely why the two findings
have to be resolved together, and this one first.

## Solution

**Suggested direction, noted rather than decided** (a maintainer should confirm the
shape and the fallback semantics):

1. Add an optional `id` to `QuickTaskFields` (`src/markdown-table.cts:710-716`).
2. Have the `#` case (`:765`) **prefer `fields.id`** and fall back to the existing
   position-derived `rowNumber` (`:762`) when it is absent — preserving today's
   behaviour for callers that pass nothing.
3. *Then* route `quick.md` step 7c through the helper, retiring the hand-rolled
   template and closing the companion todo's option 2.

Open questions for whoever picks this up:

- Should the fallback stay silent, or should a mixed-content table be detected and
  reported? (A `#` column holding both forms is currently undiagnosable.)
- Does anything read the `#` column back and depend on it being an ordinal?
- `gsd_run quick-tasks-append` needs a corresponding way to pass an id through.

Note: `src/markdown-table.cts` is the source of truth; `gsd-core/bin/lib/markdown-table.cjs`
is the built artifact — do not patch the built artifact.

*Captured, not fixed — no source was modified.*
