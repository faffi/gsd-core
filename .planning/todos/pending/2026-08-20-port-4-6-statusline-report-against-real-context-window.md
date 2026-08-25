---
created: 2026-08-20T23:16:00.000Z
title: "Port 4.6 — statusline: report against the model's real context window"
area: tooling
resolves_phase: 6
severity: major
scope: Small
scope_note: Single tracked source file, no build translation; the source change and the 3-assertion test rewrite land together in one well-understood commit
files:
  - hooks/gsd-statusline.js (tracked source — no .cjs/.cts translation needed)
  - tests/gsd-statusline.test.cjs:664-692 (PORT-BLOCKING — 3 of 6 assertions break)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.6 — full analysis)
---

## Problem

The statusline context meter does its own buffer-scaling arithmetic instead of trusting Claude
Code's pre-calculated `used_percentage`, which the docs define as already measuring against the
model's full context window.

## Validation verdict — 2026-08-20, by execution

**Port. Stronger than first written — and it has a PORT-BLOCKING companion change.**

- ⚠ **Porting breaks 3 of 6 existing assertions** in `tests/gsd-statusline.test.cjs:664-692`
  (`context meter respects CLAUDE_CODE_AUTO_COMPACT_WINDOW (#2219)`). Measured with the test
  file's own fixtures: `:668` expects `normalizedUsed===60`, gets 50; `:677` expects 100, gets
  50; `:683` expects 60, gets 50. **Expected** — the patch deletes the buffer-scaling those
  assertions exist to protect. **A behaviour-REMOVING change triggers the same TDD merge gate as
  a behaviour-adding one.** Rewrite `:664-692` to assert the unbuffered contract, or delete the
  block with a pointer to the new one, **in the same commit**.
- **Measurably SAFER than pristine**, not merely equivalent. Executed edge cases:
  - `used_percentage` present but `remaining_percentage` absent → pristine shows **no meter at
    all**, patched shows 46%.
  - **Live pristine bug:** with `CLAUDE_CODE_AUTO_COMPACT_WINDOW` set on a non-1M model,
    pristine's dynamic-buffer branch defaults `total_tokens` to 1,000,000, mis-scales, and
    **pins the bar at 100% while real usage is 30%.** Patched reads 30%.
- **1M-agnostic by construction** — the patched code does zero window-size arithmetic.
- **Cannot break other hosts.** No runtime/host branching exists in the file; both versions gate
  the whole meter on Claude-specific field presence, and absence no-ops identically. The
  "host-specific" caveat applies to the *env var*, not to file-level breakage.
- ⚠ **Two citation defects to fix before shipping** (neither substantive):
  - The doc quote is a **paraphrase** — the live doc says *"always measures against the model's
    full context window"*, not "always reflects the model's actual full…".
  - The comment pairs "+16 points" with "(real 60% shown as 72%)" in one sentence, but that
    example is a **12**-point gap. Both numbers are real, from two different scenarios — the +16
    comes from the separate 84%→100% pinning case. Split them.
  - Issue refs `#2219`/`#2451` no longer resolve to the right items upstream; the
    currently-resolvable pair for the buffer bug is **`#1194`/`#1211`**.

## Solution

Runbook §5 item 5, after re-verifying the env-var contract. Source file is tracked directly —
no translation. The test rewrite and the source change **must land in the same commit**.

**Upstream viability: moderate** — but the case is stronger than first stated, since the patch
fixes a reproducible pristine display bug rather than only matching a doc contract.

## Cross-references

- Analysis: runbook §4.6 · sequence §5 item 5
