---
created: 2026-08-08T11:57:14Z
title: Escape ${DESCRIPTION} in quick.md step 7c table row
area: tooling
severity: blocker
scope: Small
scope_note: Option 1 is a single doc instruction edit; option 2 is the preferred fix but is coupled with the reconcile-hash-column todo and should land second
files:
  - gsd-core/workflows/quick.md:613 (step "7c. Append new row to table:")
  - gsd-core/workflows/quick.md:619 (VALIDATE_MODE 6-column row template)
  - gsd-core/workflows/quick.md:624 (non-VALIDATE_MODE 5-column row template)
  - gsd-core/workflows/quick.md:627 (the safe alternative, already documented but only routed to from fast.md)
  - src/markdown-table.cts:701-707 (escapeCell — the escaping this path skips)
  - src/markdown-table.cts:545-551 (insertTableRow doc comment already names this exact hazard class)
---

## Problem

**Reported by a downstream consumer: the `secops-plugin` project.** Verified against
this repo at HEAD `343835fa`; every line number above was read directly from that HEAD.

`gsd-core/workflows/quick.md` step 7c (L613) hands the model two raw markdown row
templates to interpolate via the Edit tool:

```
L619: | ${quick_id} | ${DESCRIPTION} | ${date} | ${commit_hash} | ${VERIFICATION_STATUS} | [${quick_id}-${slug}](./quick/${quick_id}-${slug}/) |
L624: | ${quick_id} | ${DESCRIPTION} | ${date} | ${commit_hash} | [${quick_id}-${slug}](./quick/${quick_id}-${slug}/) |
```

`${DESCRIPTION}` is free-form user text. **Nothing anywhere in step 7c tells the
model to escape a literal `|`.** A description containing a pipe silently splits
into extra cells and produces a ragged row.

### This has already caused a production failure downstream

- **2026-08-05**, in the `secops-plugin` repo, a quick-task description containing
  the literal string `Path | None` was interpolated straight into the row.
- That produced a **7-cell row in a 6-column table**.
- It sat **latent for two days** — nothing detects a ragged row at write time.
- It then broke **every subsequent programmatic append**: an unrelated task's
  `gsd_run quick-tasks-append` failed with `row 22 has 7 cells, expected 6`, **exit 1**.
- Reproduced on a scratch copy. **Reproduction input: any description containing a
  literal `|`, e.g. `Path | None`.**

This is a blocker by this repo's own taxonomy: one bad row permanently breaks a
workflow for that project until a human hand-repairs STATE.md.

### The codebase already knows about this hazard — this path is the exemption

- `escapeCell` (`src/markdown-table.cts:701-707`) escapes `\` then `|`, and the
  schema-backed helper applies it to **every** cell.
- `insertTableRow`'s doc comment (`src/markdown-table.cts:545-551`) spells out this
  exact hazard — "a caller-supplied name containing a literal `|` or `\` cannot
  silently split the new row into extra columns" — and explicitly name-drops
  `appendQuickTaskRow` as behaving the same way.
- `quick.md:627` itself already documents the safe writer:
  *"For a schema-safe append outside this workflow (e.g. from fast.md),
  `gsd_run quick-tasks-append --task <text>` performs the equivalent write via the
  shared, schema-backed `appendQuickTaskRow` helper (#2133, ADR-2143 §3/§7)."*
  (#2133 = the issue that replaced fast.md's inline `awk NF-2` column-count guess with
  the schema-backed helper; ADR-2143 §3 = the table schema registry, §7 = the fail-loud
  unrecognized-schema guard — both summarized in the helper's doc comment at
  `src/markdown-table.cts:718-736`.)

So the workflow routes only the **secondary** caller (fast.md) through the safe,
schema-backed path, while the **primary** path hand-rolls the row with no escaping.
The divergence, not the missing instruction, is the underlying cause.

## Solution

Two options, and the better one is currently **blocked**:

1. **Minimal / in-scope now:** add an explicit escaping instruction to step 7c —
   escape `\` first, then `|`, in `${DESCRIPTION}` (mirror `escapeCell`'s order at
   `src/markdown-table.cts:704-705`; escaping the escape char first is deliberate,
   per the CodeQL `js/incomplete-sanitization` note there). This documents around
   the divergence rather than removing it.

2. **Better / preferred:** route step 7c through the same schema-backed
   `appendQuickTaskRow` helper that `quick.md:627` already points fast.md at. That
   eliminates the second writer entirely instead of asking the model to remember to
   escape.

**Option 2 is NOT a drop-in today.** `QuickTaskFields` has no `id` field, so the
helper fills the `#` column with a position-derived ordinal, not a quick-id — routing
7c through it right now would silently replace quick-ids with row ordinals. See the
companion todo `2026-08-08-reconcile-hash-column-contract-in-markdown-table.md`.
**These two should be resolved together**, option 2 second.

Note: `src/markdown-table.cts` is the source of truth; `gsd-core/bin/lib/markdown-table.cjs`
is the built artifact — do not patch the built artifact.

*Captured, not decided — a maintainer should pick between (1) and (2).*
