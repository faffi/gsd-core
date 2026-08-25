---
created: 2026-08-20T23:17:00.000Z
title: Port 4.7 — review-lane timeouts 540s→1800s (MOSTLY INERT AS SPECIFIED)
area: tooling
resolves_phase: 6
severity: major
scope: Small
scope_note: One value change plus a required companion prose edit and four literal-asserting tests to update, all mechanical; no failure story yet so consider deferring entirely
files:
  - src/review-lane-descriptor.cts:422-434 (THE ONLY FILE WITH RUNTIME EFFECT)
  - capabilities/antigravity/capability.json:121 (provably DEAD for dispatch — keep for validator consistency only)
  - gsd-core/workflows/review.md:295-300 (REQUIRED COMPANION EDIT — the third, undocumented timeout layer)
  - tests/antigravity-reviewer.test.cjs:126-152 (asserts the literals — will break)
  - tests/review-lane-invocation.test.cjs:88 (asserts the literals — will break)
  - tests/review-lane-descriptor.test.cjs:775,954 (asserts the literals — will break)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.7 — full analysis)
---

## Problem

Raises the `antigravity` review lane's timeout floor from 540s to 1800s.

## Validation verdict — 2026-08-20, by execution

⚠ **THE FILE LIST AS ORIGINALLY SPECIFIED, PORTED EXACTLY, CHANGES NOTHING.**
Do not execute this as written.

- **The `capability.json` half is provably DEAD for dispatch.** `antigravity` is already a
  **first-party** lane in `REVIEWER_LANES` (`src/review-lane-descriptor.cts`), and the merge
  loop does `if (bySlug.has(slug)) continue;` (`:654`, D8) — documented at `:608-610`:
  *"an overlay declaring a slug that already names a first-party lane is silently superseded…
  never overwritten."* Demonstrated: mutating the registry's `antigravity.reviewer` to
  `1800s`/`1920000` and re-running `mergeReviewerLanes` still yields `600000` / `540s`, and the
  merged object is `===` the untouched first-party entry. The registry block is read only by the
  validator and roster derivation — **never for the invoke timeout.**
- **The one file with runtime effect** is `src/review-lane-descriptor.cts:422-434` (comment +
  `invoke.args` + `timeoutFloorMs`) → compiled lib → `resolveLanePlan`
  (`src/review-lane-invocation.cts:365-367`) → `cp.spawnSync(..., { timeout })` at
  `gsd-tools.cjs:1446`.
- ⚠ **There is a THIRD timeout layer the patch never touches.**
  `gsd-core/workflows/review.md:295-300` tells the calling agent to wrap the whole
  `invoke_reviewers` loop in a Bash-tool `timeout:` of *"at least 900000, and 1200000 when Codex
  or headless Claude are in the selection."* That is hand-written prose — nothing generates or
  lints it against the data (`grep -rln timeoutFloorMs scripts/` is empty). Raising antigravity's
  floor to **1,920,000ms makes it the largest of any lane**, above Codex's 1,200,000. An operator
  following the unmodified guidance under-provisions the outer wrapper and **the host kills the
  whole loop before the new inner budget is ever reached.** `review.md` is a REQUIRED companion edit.
- **Buffer, not ratio:** 600s−540s = 60s becomes 1920s−1800s = 120s. Outer>inner holds, but
  **nothing enforces it** — no validator or test compares the `--print-timeout` string against
  `timeoutFloorMs`. Land one without the other → silent SIGKILL surfacing as an unexplained empty
  stub, the exact failure `review.md:302-306` warns about.
- **Registry regeneration is deterministic** — regenerated on a clean tree, byte-identical. This
  **refutes** `~/.claude/runbooks/gsd-update-runbook.md:404` ("the registry is generated from the
  descriptor"): it is generated from `capabilities/<id>/capability.json` only, and
  `review-lane-descriptor` has no generation relationship to it.
- **Justification: still NONE.** Exhaustive search found one artifact —
  `~/.claude/runbooks/gsd-update-runbook.md:399-412`, item 12 — which dates the edit (2026-08-14)
  and describes the mechanics, and notes the patch *"sat in no diff and no runbook entry"* until a
  drift check caught 13 modified against a patch set of 11. It records **no workload, no observed
  timeout, no failure.** "Names a number, not a failure" is confirmed.

## Solution

Runbook §5 item 7 — **last**. Revised action:

1. **Drop** `capabilities/antigravity/capability.json` from the required-for-effect list — keep
   it only for validator/doc consistency.
2. **Add** `gsd-core/workflows/review.md`'s guidance as a required companion edit.
3. Update the four test files that assert the literals.
4. **LOCAL-ONLY.** With no failure story there is no upstream case for changing a default.
   Consider deferring entirely until a real timeout is observed.

## Cross-references

- Analysis: runbook §4.7 · sequence §5 item 7
