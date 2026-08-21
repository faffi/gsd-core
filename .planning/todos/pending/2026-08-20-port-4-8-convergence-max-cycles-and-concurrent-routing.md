---
created: 2026-08-20T23:18:00.000Z
title: Port 4.8 — convergence max-cycles 3→5 and route to gsd-review-concurrent
area: tooling
severity: major
files:
  - gsd-core/workflows/plan-review-convergence.md:31 (the ONE runtime-authoritative max-cycles site)
  - gsd-core/workflows/plan-review-convergence.md:453,462 (stale success-criteria checklist — REQUIRED edit)
  - skills/gsd-plan-review-convergence/SKILL.md (routing half)
  - skills/gsd-review-concurrent/SKILL.md (MUST come onto the same branch — Skill tool hard-errors on unknown names)
  - tests/plan-review-convergence.test.cjs:517-520 (passes for the wrong reason — REQUIRED edit)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.8 — full analysis)
---

## Problem

Two independent changes sharing a file: raise `max-cycles` from 3 to 5, and route the review
step to `gsd-review-concurrent` instead of `gsd-review`.

## Validation verdict — 2026-08-20

**Splittable as claimed — 4 hunks, no line overlap, no content dependency — but NEITHER HALF IS
SELF-CONTAINED at the file list first given.**

- **`max-cycles` has exactly ONE runtime-authoritative site:** `plan-review-convergence.md:31`
  (`if [ -z "$MAX_CYCLES" ]; then MAX_CYCLES=3; fi`). SKILL.md, the `commands/gsd/` twin, and
  every `docs/` mention are text with no runtime effect.
- ⚠ **Its test passes for the wrong reason.** `tests/plan-review-convergence.test.cjs:517-520`
  asserts `workflow.includes('MAX_CYCLES') && workflow.includes('3')`. After the bump `'3'` still
  matches unrelated text (`#2315`, `## 3. Validate Phase`), so the test stays green while its own
  message — *"parses --max-cycles with default of 3"* — becomes **false**. Touch it or the suite lies.
- ⚠ **The routing half leaves the file SELF-CONTRADICTING.** The patch changes the executable
  prompt to `gsd-review-concurrent` but never touches the file's own success-criteria checklist at
  `:453,462`, which still says `Skill("gsd-review")`. The routing test only passes via an
  OR-fallback that matches *that stale checklist* — an accidental pass, not validation.
- ⚠ **"Dangling reference" UNDERSELLS the failure mode.** `docs/ARCHITECTURE.md:125` records from
  #924: *"the Skill tool hard-errors on unknown names rather than re-routing."* So porting the
  routing without the skill either aborts loudly (fine — the orchestrator's "abort if
  CYCLE_SUMMARY absent" contract catches it) **or** the review subagent improvises, falls back to
  `gsd-review` or hand-rolls a review, and still emits a well-formed `CYCLE_SUMMARY` — the loop
  then reports counts as if the intended review ran. **The silent branch could not be ruled out.**
  Bring `skills/gsd-review-concurrent/SKILL.md` onto the same branch; it is self-contained.
- **`gsd-review-concurrent` IS genuinely parallel-safe**, not invoke-and-hope. Verified in 1.11.0:
  `review-lane-invocation.cjs:161-166` keys every write on slug (`gsd-review-${slug}.md` / `.err`).
  The one shared path, `gsd-review-prompt.md`, is written once by `build_prompt` (`review.md:242`)
  strictly before `invoke_reviewers` — single writer, then readers only. Its documented zsh
  `wait $PIDS` footgun was reproduced empirically (scalar form no-ops the barrier, exits 0 in
  ~6ms); the skill already uses the correct array form.
- ⚠ **3→5 is NOT "bounded like today."** `MAX_CYCLES` is the **only** hard bound. Stall detection
  (`§5c`) is informational — it prints a warning and falls through, with no early exit. No token
  budget, no wall-clock budget. Declared per-lane ceilings sum in the sequential path
  (codex/claude 1,200,000ms each; gemini/qwen/cursor/kimi 900,000), so a worst-case cycle can
  exceed an hour and five compound it. The bump adds **67% worst-case cost and removes no risk**;
  a stalled run burns 5 cycles before escalating instead of 3 — though stall detection would have
  flagged it at cycle 2. Preference call, but a costed one.

## Solution

Runbook §5 item 6 — **split first**, two commits:

1. **max-cycles 3→5** — plus the test message fix. Viable alone locally. An upstream PR would
   also need the `commands/gsd/` twin (kept in lockstep by project history) and 5 doc surfaces
   plus 4 localized trees.
2. **Routing** — plus the `:453,462` checklist fix **and** `skills/gsd-review-concurrent/SKILL.md`
   on the same branch. Cannot go upstream until the skill does.

## Cross-references

- Analysis: runbook §4.8 · sequence §5 item 6
