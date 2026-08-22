---
created: 2026-08-20T23:19:00.000Z
title: Port 4.10 — mempalace recall line in the planner (the only item that survived validation unchanged)
area: tooling
severity: minor
scope: Small
scope_note: One already-validated line insertion; blocked on the zsh-array-index-guards todo landing first, which is a dependency not an effort driver
files:
  - agents/gsd-planner.md (+1 line — cat "$phase_dir"/*MEMORY-RECALL.md)
  - agents/gsd-planner.md:614 ($phase_dir binding — "Extract from init JSON")
  - capabilities/mempalace/capability.json:96-109 (the declared plan:pre producer)
  - skills/gsd-mempalace-recall/SKILL.md (step 4 — "The planner consumes it.")
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.10 — full analysis)
---

## Problem

`mempalace-recall` writes `MEMORY-RECALL.md` at `plan:pre` and nothing reads it. The patch adds
one line — `cat "$phase_dir"/*MEMORY-RECALL.md` — so the planner picks it up.

## Validation verdict — 2026-08-20

**PORT AS-IS. The only item in the set that survived validation unchanged, and the
strongest-founded of the ten.**

- **The producer is real and traceable**, unlike 4.1's. `capabilities/mempalace/capability.json:96-109`
  formally declares a `plan:pre` step: `{"ref":{"skill":"mempalace-recall"},
  "produces":["MEMORY-RECALL.md"],"when":"mempalace.enabled","onError":"skip"}`, and
  `skills/gsd-mempalace-recall/SKILL.md` step 4 says *"Write `MEMORY-RECALL.md` in the current
  phase directory. The planner consumes it."* Reproduced live:
  `gsd-tools query loop.render-hooks plan:pre` on a scratch project with `mempalace.enabled: true`
  returns the step in `activeHooks`.
- **Three real artifacts on disk**, written 2026-08-18/19 under
  `~/gsd-workspaces/{security-vpc,bedrock-access,ctem-gitlab-group}/…/phases/76-*/MEMORY-RECALL.md`,
  well-formed and matching the skill's documented format. **Live production usage, not just spec.**
- **`$phase_dir` is NOT the `$FORGE` defect class.** It is bound by prose in an earlier step
  (`gsd-planner.md:614`), and the three **pre-existing** sibling lines in the same fence
  (`*-CONTEXT.md`, `*-RESEARCH.md`, `*-DISCOVERY.md`) already rely on the identical cross-fence
  binding. The new line is a 4th use of a shipped pattern — it cannot introduce a scoping bug its
  neighbours do not already have.
- **Inert by default:** `mempalace.enabled` defaults `false`, so out of the box the step never
  fires and the glob never matches. Contribution is real but scoped to projects that opt in.
- ⚠⚠ **CORRECTED 2026-08-21: the patch hunk is STALE and must be rewritten before porting.**
  The earlier text here said the zsh `NOMATCH` caveat was "inherited — all three sibling lines
  share it." **That is now false.** Upstream rewrote the whole fence between 1.10.0 and 1.11.0.

  1.10.0 (what the patch was written against, and what the patch imitates):
  ```bash
  cat "$phase_dir"/*-CONTEXT.md 2>/dev/null
  ```
  1.11.0 `agents/gsd-planner.md:696-703` (what is actually there now):
  ```bash
  _CTX=( "$phase_dir"/*-CONTEXT.md )
  if [ -e "${_CTX[0]}" ]; then cat "${_CTX[@]}"; fi   # From /gsd:discuss-phase
  _RESEARCH=( "$phase_dir"/*-RESEARCH.md )
  if [ -e "${_RESEARCH[0]}" ]; then cat "${_RESEARCH[@]}"; fi
  _DISCOVERY=( "$phase_dir"/*-DISCOVERY.md )
  if [ -e "${_DISCOVERY[0]}" ]; then cat "${_DISCOVERY[@]}"; fi
  ```
  Array-glob + existence check on all three siblings.

  ⚠ **RE-CORRECTED 2026-08-22 — the paragraph that stood here was itself wrong.** It claimed
  *"upstream fixed exactly the zsh NOMATCH hazard."* **Upstream did not.** Measured against the
  1.11.0 form with the MEMORY-RECALL glob:

  ```
  no-match:  zsh:1: no matches found: /tmp/n410/*MEMORY-RECALL.md      # still aborts
  match:     SKIPPED                                                   # ${_R[0]} empty, cat never runs
  ```

  The array form is broken in **both** directions under zsh. What it actually fixed is
  bash-only: `cat glob 2>/dev/null` emits a spurious `cat: … No such file` and a non-zero exit
  in bash when the glob misses; the `[ -e ... ]` guard suppresses that. It has no bearing on zsh.

  So the honest comparison is: the 1.10.0 hunk and the 1.11.0 idiom are **both** broken under
  zsh, differently. Neither is a safe target. Port to the validated form in the Solution section.

## ⛔ BLOCKED 2026-08-21 — the surrounding idiom is dead under zsh

Do not port this until the guard bug is fixed. Writing the line in the block's current idiom
and then TESTING it showed the idiom itself never fires under zsh (arrays are 1-indexed, so
`${_X[0]}` is always empty). A 4th guard in the same form would be provably dead code.

Blocking todo: `.planning/todos/pending/2026-08-21-zsh-array-index-guards-silently-read-nothing.md`

Once that lands, port this line in whatever form that fix establishes — not the form below.

## Solution — REWRITTEN 2026-08-22. Do NOT use the raw patch hunk, and do NOT copy the neighbours.

Both the 1.10.0 hunk and the 1.11.0 block idiom are dead under zsh. Use the validated form —
8/8 across bash 3.2.57, zsh 5.9, **and POSIX `sh`**; correct ordering, silent on no-match,
exit 0, no shell options set, no non-POSIX flags:

```bash
find "$phase_dir" -maxdepth 1 -name '*MEMORY-RECALL.md' 2>/dev/null | sort | while IFS= read -r f; do cat "$f"; done
```

Insert after the `_DISCOVERY` pair in `<step name="gather_phase_context">`.

⚠ **Do not "simplify" to `${#_RECALL[@]} -gt 0`** — without a `nullglob` shim that is *worse*
than the current code in bash: an unmatched glob yields count 1 (the literal pattern) and emits
`cat: …: No such file`, where `[ -e "${_RECALL[0]}" ]` at least skips silently.

**Size:** `agents/gsd-planner.md` is 49,051 / 57,344 bytes (XL tier, `tests/agent-size-budget.test.cjs`)
— 8,293 free. The one-line addition is comfortably inside it. (Contrast `agents/gsd-verifier.md`,
which has 2 bytes.)

⚠ **The glob has NO leading dash** — the producer writes `MEMORY-RECALL.md`, not
`*-MEMORY-RECALL.md`, unlike all three siblings. That asymmetry is correct and is in the
original patch, but it reads as a typo, so keep the trailing comment naming the producer.


Runbook §5 item 2 — second, right after the 4.1 pilot, because it proves the `agents/` path
end-to-end at one line. Direct source, no translation.

**Upstream viability: strong.** One line, guarded, completes an existing capability's wiring.
**"Producer with no consumer" is confirmed:** a repo-wide `MEMORY-RECALL` grep at 1.11.0 finds
only the capability declaration, the producing skill, generated registry output and docs —
**zero** consumers in any agent or workflow. Arguably an upstream bug worth reporting as such.

## Cross-references

- Analysis: runbook §4.10 · sequence §5 item 2
