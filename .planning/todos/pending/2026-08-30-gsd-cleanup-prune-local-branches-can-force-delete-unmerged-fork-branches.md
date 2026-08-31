---
created: 2026-08-30T00:00:00.000Z
title: "/gsd-cleanup's prune_local_branches hard-deletes any local branch with a gone upstream — protected-name filter doesn't cover local/<slug> fork branches"
area: workflows
severity: blocker
scope: Small
scope_note: One line to fix (extend the awk exclusion pattern, or switch -D to -d so an unmerged branch refuses rather than force-deletes) plus a note in the dry-run/confirmation text; no new verb, no schema change
files:
  - gsd-core/workflows/cleanup.md:210 (prune_local_branches step — the awk filter and `git branch -D`)
  - gsd-core/workflows/cleanup.md (show_dry_run step, referenced but not re-verified here — "same filter as the dry-run so the execution list matches exactly what the user confirmed")
---

## Problem

Surfaced by peer session `gsd-core-working` (cross-session message, 2026-08-30), verified
directly against repo source:

```bash
git branch -vv | awk '/: gone\]/ { if ($1 !~ /^\*$|^main$|^next$|^trunk$|^develop$/) print $1 }' | xargs -r git branch -D
```

The protected-name filter is `^main$|^next$|^trunk$|^develop$` — it does not exclude any
`local/<slug>` pattern. Per this repo's own branch model (`CLAUDE.md`), `local/<slug>` is
the durable, long-lived feature-branch namespace — the thing meant to survive across
`working` rebuilds and upstream pulls. Any such branch tracking a `fork/` remote (the
normal case — every `local/<slug>` branch here does) will show `[gone]` in `git branch -vv`
the moment its remote counterpart is deleted (e.g. after a feature is promoted upstream and
the fork branch is cleaned up, or simply deleted manually) — at which point the next
`/gsd-cleanup` run, behind a single confirmation shared with the phase-archival step, hard
force-deletes it via `-D`, which does not check whether the branch is merged.

**This is not hypothetical for this repo right now:** `local/track-planning-history` (this
session's own durable branch, currently ~17 commits ahead of `fork/local/track-planning-history`)
and `local/plan-scan-exclude-plan-check` both track `fork/` remotes and are both unprotected
by this filter. If either remote branch is ever deleted before those commits are otherwise
preserved, the next `/gsd-cleanup` confirmation silently takes them out.

Two compounding issues:

1. **Single shared confirmation.** The dry-run/confirmation step covers phase archival AND
   branch pruning together — a user confirming "archive these completed phases" is also
   authorizing "force-delete these branches," without necessarily reading the branch list
   as carefully as the phase list.
2. **`-D` not `-d`.** `git branch -D` force-deletes regardless of merge status. `git branch -d`
   would refuse (\"not fully merged\") and require an explicit force — which is the
   correct default for anything outside the three trunk-like names, since \"upstream gone\"
   (remote branch deleted) says nothing about whether the local branch's commits are
   preserved anywhere else.

## Fix

Smallest fix: extend the exclusion pattern to also skip `local/*` (this fork's convention)
or, more generally, any branch whose name doesn't match a short allowlist of prunable
patterns — inverting the current blocklist-of-three into an allowlist is safer given how
narrow the actual "safe to auto-prune" case is (a branch created and merged entirely through
the tool's own PR flow). Alternatively/additionally, change `-D` to `-d` so an unmerged
branch refuses instead of silently succeeding, forcing a human to notice and force-delete
deliberately if that's truly intended.

## Cross-references

- Reported by peer session `gsd-core-working` (cross-session message, 2026-08-30), while
  coordinating on the `init.phase-op` archived/unplanned-phase investigation
  (`2026-08-30-init-phase-op-cannot-distinguish-archived-from-unplanned-phase.md`) — separate
  concern, not the same defect class.
