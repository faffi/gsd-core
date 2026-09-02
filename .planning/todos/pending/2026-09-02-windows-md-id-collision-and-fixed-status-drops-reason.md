---
created: 2026-09-02T00:00:00.000Z
title: "WINDOWS.md window ids are allocated per-branch (total_count = entries.length), so parallel lanes mint colliding ids; markFixed never records a reason, unlike waive"
area: tooling
severity: minor
scope: Small
scope_note: Reporter's own framing — lower severity than the handoff-path defects; verified the mechanism (id derivation, markFixed's missing reason field) but not independently re-run the reporter's two-lane collision or measured the merge-conflict-resolution reason loss
files:
  - src/broken-windows.cts:129,159,185 (Ledger.total_count — always `ledger.entries.length`, i.e. derived from the local file's own array, not any cross-branch/cross-lane counter)
  - src/broken-windows.cts:356-369 (markFixed — entry spread `{ ...e, status: 'fixed', resolved_at }`, never sets or requires `reason`)
  - src/broken-windows.cts:325-352 (the sibling `waive` path, for contrast — requires a non-empty `reason`, guarded by `REASON.WINDOWS_WAIVE_REASON_EMPTY`, and records it on the entry)
---

## Problem

Reported by peer session `plane-custom-fields` (cross-session message, 2026-09-02), same
report as the handoff-path defects (`2026-09-02-handoff-path-has-no-workstream-scoping-cross-lane-data-loss.md`),
filed separately as a distinct, lower-severity subsystem. Two related observations:

**1. Id collision across parallel lanes.** `.planning/WINDOWS.md` is git-tracked and
per-branch; new entry ids are allocated by incrementing a count within that branch's own
file. Verified the mechanism directly: `total_count` (`src/broken-windows.cts:129,159,185`)
is always `ledger.entries.length` — derived purely from the current file's own array, with
no cross-branch or cross-lane coordination. The reporter's two parallel lanes each minted an
entry `#27` independently for unrelated windows; they verified ids 1–26 are byte-identical at
the merge-base, so only the post-fork tail collides. A wholesale merge-conflict resolution
then silently drops the losing side's `reason` text.

**2. `markFixed` never records a reason, unlike `waive`.** Confirmed by reading both
functions directly: `waive` (`:325-352`) requires a non-empty `reason` (rejects with
`WINDOWS_WAIVE_REASON_EMPTY` otherwise) and persists it on the entry. `markFixed`
(`:356-369`) does neither — its entry update spread never sets `reason` at all. So a window
resolved via `fix` carries no structured justification field; any substantive explanation
(the reporter cites a 2,423-character verification record) has to live outside the ledger
entirely — in the fix commit or elsewhere — and, per point 1, exists in exactly one copy
with nothing protecting it from a silent conflict-resolution drop.

**Not independently re-verified**: the reporter's exact two-lane collision (not reproduced
here) and the specific merge-conflict-resolution behavior that drops the losing `reason`
text (plausible given point 1, but the actual git-merge mechanics weren't traced).

## Fix

Not designed here — flagging for whoever picks this up. Candidate directions: allocate ids
via something branch-independent (a UUID, or a workstream-prefixed counter) rather than a
local array length; and give `markFixed` an optional `reason` parameter mirroring `waive`'s,
so a fix's justification has somewhere structured to live instead of depending on a single
copy surviving every future merge.

## Cross-references

- Reported by peer session `plane-custom-fields` (cross-session message, 2026-09-02).
- Same report's higher-severity finding, filed separately:
  `2026-09-02-handoff-path-has-no-workstream-scoping-cross-lane-data-loss.md`.
