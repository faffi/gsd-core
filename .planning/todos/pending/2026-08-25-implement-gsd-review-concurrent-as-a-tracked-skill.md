---
created: 2026-08-25T09:10:00.000Z
title: "Implement gsd-review-concurrent as a tracked skill — it is a contract with core, not a file to copy"
area: tooling
severity: major
scope: Medium
scope_note: "The 217 lines already exist and are correct. The work is re-verifying the contract they assert against 1.11.0, giving them a tracked home, and adding the test that proves the partition cannot silently drop a lane — not transcription"
files:
  - .planning/runbooks/local-only-artifacts/skills--gsd-review-concurrent--SKILL.md (the rescued copy — byte-identical to the installed one, verified 2026-08-25)
  - $HOME/.claude/skills/gsd-review-concurrent/SKILL.md (the live artifact; UNTRACKED anywhere, destroyed by make install)
  - skills/gsd-review-concurrent/SKILL.md (⚠ DOES NOT EXIST — the tracked home it needs)
  - gsd-core/workflows/plan-review-convergence.md:142,187,189 (the three local dispatch edits — present in the INSTALLED 1.10.0 copy, absent from the repo's 1.11.0 copy)
  - $HOME/.claude/scripts/gsd-local-patches-1.10.0.diff:822,831,834 (where those three edits are recorded)
  - skills/gsd-plan-review-convergence/SKILL.md (max-cycles 3→5, also recorded in the patch)
  - src/review-lane-invocation.cts (the core seam the skill drives)
  - gsd-core/bin/gsd-tools.cjs:1227-1232,1410 (review-lane invoke + --run-dir/--repo-root parsing)
  - .planning/todos/pending/2026-08-20-port-4-8-convergence-max-cycles-and-concurrent-routing.md (covers the ROUTING half; treats this skill as "must be IMPORTED")
  - .planning/todos/pending/2026-08-20-local-only-skills-and-agent-destroyed-by-make-install.md (BLOCKS a durable home)
  - .planning/todos/pending/2026-08-21-zsh-array-index-guards-silently-read-nothing.md (this skill's PIDS barrier is a reference implementation of that fix)
---

## Problem

`gsd-review-concurrent` exists only at `$HOME/.claude/skills/gsd-review-concurrent/SKILL.md`.
It is in **no** git repository — not this fork, not upstream — and `make install` deletes it
(`gsd-tools detect-custom-files` names it among the three casualties). The only copies are the
live one and the rescue at `.planning/runbooks/local-only-artifacts/`.

`port-4-8` covers the *routing* change that points convergence at this skill, and describes the
skill itself as a file that "must be IMPORTED." That verb is the problem this todo exists to fix.
**The 217 lines are not a document — they are a contract asserted against a specific core version.**
Copying them into `skills/` without re-verifying that contract produces a wrapper that looks
installed and silently mis-drives core.

## What the skill actually is (the essence to preserve)

A wrapper that re-drives the stock `gsd-review` workflow **verbatim** and substitutes exactly one
step — `<step name="invoke_reviewers">` — replacing core's sequential lane loop with backgrounded
invocations of core's own per-lane command. Review time goes from Σ(lane times) toward
max(lane times).

Five properties carry the whole design. An implementation that loses any one of them is not this
skill:

1. **Zero core edits.** Core keeps ownership of argv, models, effort, timeouts, handlers,
   diagnostic stubs, typed refusal reasons, watermark stamping, and any lane added in a future
   version. That is what makes it survive `gsd update`, and it is why the wrapper substitutes a
   *step* rather than forking the workflow.

2. **The partition is an allow-list with a fail-safe default — and the default is the design.**
   Parallel-safe = distinct-provider cloud lanes (`gemini codex coderabbit opencode qwen cursor
   antigravity kimi-code`). **Everything else, including any slug the wrapper does not recognise,
   goes SERIAL.** The reasoning is the load-bearing part: core derives its reviewer roster live
   (`review-lane flags`, #2800/#2272) so it picks up new lanes automatically; this allow-list is
   hardcoded and cannot. If an unrecognised slug were merely "not parallel," it would be in
   **neither** loop — never invoked, absent from REVIEWS.md, and never even reported EMPTY, because
   the post-fan-out check only iterates the parallel subset. CYCLE_SUMMARY would then be computed
   from a reviewer that never ran. Routing unknowns to SERIAL turns a silent correctness bug into a
   performance non-event.

3. **The accounting check runs over ALL_SELECTED, not the parallel subset.** This is the only thing
   that catches a lane which fell out of the partition entirely. It must warn loudly and must
   forbid reporting review counts as complete.

4. **The barrier must use a PID array.** `PIDS+=($!)` / `wait "${PIDS[@]}"` — never a space-joined
   string. Under zsh (the `run_in_background` shell here, 5.9) an unquoted `wait $PIDS` passes ONE
   argument, fails with `wait: job not found`, returns in ~0.007 s, and reports every still-running
   lane as EMPTY **with exit status 0**. Under bash the same code silently waits on only the first
   lane. The append and the `wait` must change together.

5. **The fan-out must be `run_in_background: true`.** The Bash tool caps foreground calls at
   600,000 ms; codex/claude lane timeout floors are 1,200,000 ms. A foreground barrier is killed
   mid-review. Related: `$RUN_DIR` does not survive across Bash calls, so the literal path core
   printed must be spliced into every command.

## Contract re-verified against 1.11.0 — 2026-08-25

The skill was written against core **1.10.0**; this repo is **1.11.0**. Every assertion still holds,
measured today:

| Assertion | Result |
|---|---|
| `review-lane invoke --slug` exists | ✓ `gsd-tools.cjs:1410` |
| `--run-dir` / `--repo-root` parsed | ✓ `gsd-tools.cjs:1231-1232` |
| Slugs use `lm_studio` / `llama_cpp` (underscores), `kimi-code` (hyphen) | ✓ `src/review-lane-descriptor.cts` |
| `antigravity` is the slug; `--agy` is a flag | ✓ flags list carries both; slug list only `antigravity` |
| The skill's own drift check returns `claude, ollama, lm-studio, llama-cpp` | ✓ exactly as predicted |

So the port is **not** blocked on a core change. Re-run that table on every GSD update; the skill
carries the drift-check command for exactly this purpose.

## Solution

1. **Give it a tracked home** at `skills/gsd-review-concurrent/SKILL.md` in this repo, so it travels
   through `fork` and stops depending on a rescue copy. Blocked on the local-artifact-survival todo
   for the `make install` half.
2. **Record the contract table above inside the skill** as a dated verification block, so the next
   reader re-runs it rather than trusting it.
3. **Add the test the design implies and does not have:** feed the partition a slug that is in
   neither list and assert it lands in SERIAL — not dropped. This is the failure the wrapper was
   written to prevent and the one nothing currently checks.
4. **Fix the one condition no test can catch:** the `antigravity` lane is parallel-safe *only* while
   pinned to a non-Gemini model. If it is ever set to a Gemini model, its quota bucket collides with
   the standalone `gemini` lane. The key is **`review.models.agy`**, NOT `review.models.antigravity`
   — `src/review-lane-descriptor.cts:194-195,444` records that resolving by slug "would look up
   `review.models.antigravity`, miss, and silently ignore" the setting. Make this a precondition the
   skill checks, not a footnote.

5. **Read the lane result JSON instead of testing file size.** See the review findings below — core
   returns `stubbed: boolean` and the wrapper already captures it to disk, then ignores it.

## Known defects in the current implementation (reviewed 2026-08-25)

| Sev | Defect |
|---|---|
| HIGH | `[ -s gsd-review-<slug>.md ]` reports **OK for a lane that ran and failed** — `writeReviewOrStub` (`src/review-lane-runner.cts:424-439`) always writes a non-empty file, a stub on failure. The accounting check has the same flaw and cannot flag it. Core returns `stubbed: boolean` in the JSON the wrapper already writes to `gsd-review-lane-result-<slug>.json` and never reads |
| HIGH | The two failure modes have OPPOSITE file outcomes — a refusal (`runner:1051-1055`) writes NO file; a ran-and-failed lane writes a stub. The skill's stated diagnosis list ("refused, crashed, or partition failure") is wrong: a crash produces a stub and never reaches MISSING |
| MED | Mixed placeholder syntax (`<RUN_DIR>` vs `{PARALLEL_SELECTED}`) with no substitution guard. `{FOO}` is valid shell — an unsubstituted brace expands to itself and runs the loop once with a garbage slug |
| MED | The drift check covers the lane ROSTER but not the WORKFLOW STRUCTURE the substitution depends on. Nothing asserts `<step name="invoke_reviewers">` still exists or still holds the loop |
| LOW | Typed refusals are told to be "surfaced in the final summary" but no code reads them — same root cause as HIGH-1 |

## Do NOT

- **Do not transcribe and call it done.** The lines are correct; the contract is what needs proving.
- **Do not "simplify" the PID array to a string.** See property 4 — it is a measured failure, and it
  reports success while doing nothing.
- **Do not background `claude` or any local-model lane.** `claude` shares this session's Anthropic
  bucket; `ollama`/`lm_studio`/`llama_cpp` share one local GPU and are the only lanes with a
  promptBudget, whose trimming core's loop owns.
- **Do not derive the groups from user-typed flags.** Derive from `$SELECTED_REVIEWERS` — `--agy` is
  a flag alias and `--selected agy` yields `malformed_lane`.

## Cross-references

- `port-4-8` — the routing half (`plan-review-convergence.md` → this skill) plus max-cycles 3→5.
  That todo also records two required edits this one does not cover: a stale success-criteria
  checklist at `:453,462` that still says `Skill("gsd-review")` and makes the file
  self-contradicting, and `tests/plan-review-convergence.test.cjs:517-520`, which passes for the
  wrong reason.
- `local-only-skills-and-agent-destroyed-by-make-install` — blocks the durable home.
- `zsh-array-index-guards-silently-read-nothing` — **this skill's barrier is a correct reference
  implementation of that fix**, written by someone who hit the bug in production and measured it.
  Worth citing there as prior art, alongside `review.md:248-273`.
