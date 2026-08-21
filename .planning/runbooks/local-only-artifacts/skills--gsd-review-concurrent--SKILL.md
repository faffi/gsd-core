---
name: gsd-review-concurrent
description: "Cross-AI peer review with the parallel-safe cloud reviewer lanes invoked concurrently instead of sequentially. Standalone wrapper over gsd-review — no core GSD files modified."
argument-hint: "--phase N [--gemini] [--codex] [--coderabbit] [--opencode] [--qwen] [--cursor] [--antigravity] [--kimi-code] [--claude] [--all]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
---

<objective>
Same output as /gsd-review (a structured REVIEWS.md), but the parallel-safe cloud
reviewer lanes run CONCURRENTLY, cutting the review step from Σ(lane times) toward
max(lane times). Achieved WITHOUT editing any core GSD file: this skill re-drives the
stock gsd-review workflow verbatim and substitutes ONE step — the invoke_reviewers
lane loop — with backgrounded invocations of core's own per-lane command
(`query review-lane invoke`). Core keeps ownership of every lane detail: argv, models,
effort, timeouts, handlers, diagnostic stubs, typed refusal reasons, watermark
stamping, and any lanes added in future GSD versions.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/review.md
</execution_context>

<process>
Execute the gsd-review workflow above EXACTLY as written, with a single substitution
at `<step name="invoke_reviewers">`. Every other step — detect_clis (including the
SELF_CLI claude auto-skip), gather_context, build_prompt, write_reviews,
present_results — runs unchanged, so all drift-prone logic (prompt assembly,
synthesis, frontmatter, source-grounding) stays owned by core and is never
duplicated here.

## Substitution at <step name="invoke_reviewers">

Core 1.9.0+ iterates declared lanes with `gsd_run query review-lane invoke --slug
<slug>` — one independent OS process per lane whose only writes are per-slug files
inside the run dir (`gsd-review-<slug>.md` / `.err`). That makes concurrent
invocation mechanically safe. Instead of core's sequential loop, partition the
SELECTED reviewers (comma-separated in `$SELECTED_REVIEWERS`; split with
`tr ',' ' '`) into two groups.

**Partition rule — an allow-list plus a fail-safe default. Every SELECTED slug
MUST land in exactly one group; none may be dropped.**

- PARALLEL-SAFE — the explicit allow-list (distinct providers → independent rate
  buckets):
  `gemini codex coderabbit opencode qwen cursor antigravity kimi-code`
  Note on `antigravity` (agy): parallel-safe ONLY while pinned to a non-Gemini model
  (e.g. GPT-OSS 120B) — its Antigravity/Google quota lane then stays distinct from
  the standalone `gemini` reviewer. If agy is ever set to a Gemini model, drop
  `gemini` from the concurrent run (or move agy to serial).
- SERIAL — **everything else**, i.e. `SELECTED − PARALLEL-SAFE`. Known members:
  `claude` (shares this session's Anthropic bucket — usually auto-skipped under
  Claude Code per SELF_CLI), `ollama` / `lm_studio` / `llama_cpp` (shared local
  GPU; these are also the only lanes with a promptBudget, and core's loop handles
  their prompt trimming). **Any slug you do not recognize also lands here.**

**Why SERIAL is the default and not a drop (fixes the drift this wrapper is most
exposed to).** Core derives reviewer flags from the live lane roster
(`gsd_run review-lane flags`, #2800/#2272), so convergence and `gsd-review` pick up
a newly shipped lane automatically. This list is hardcoded and will not. If an
unrecognized slug were merely "not in PARALLEL", it would be in neither loop: never
invoked, absent from REVIEWS.md, and — because the post-fan-out check only iterated
the parallel subset — never even reported as EMPTY. The CYCLE_SUMMARY counts would
then be computed from a reviewer that never ran. Sending unknown slugs to SERIAL
makes a future lane run *correctly, just not concurrently* — a performance
non-event instead of a silent correctness bug.

Slug spelling is not guessable — verified against core 1.10.0: `lm_studio` and
`llama_cpp` use **underscores**, `kimi-code` uses a **hyphen**, and `agy` is a flag
alias only (`--selected agy` → `malformed_lane`; the slug is `antigravity`). Derive
the groups from `$SELECTED_REVIEWERS`, never from user-typed flags.

Roster drift check — run when a GSD update lands, and add any genuinely
parallel-safe newcomer to the allow-list above:

```bash
# Lanes core knows about that this wrapper does not classify as parallel-safe.
# Each is currently routed to SERIAL. Confirm that is still the right call.
node "$HOME/.claude/gsd-core/bin/gsd-tools.cjs" review-lane flags \
  | tr ' ' '\n' | sed 's/^--//' | grep -vx agy \
  | grep -vxE 'gemini|codex|coderabbit|opencode|qwen|cursor|antigravity|kimi-code'
# expected today: claude, ollama, lm-studio, llama-cpp
# (flags are hyphenated; the corresponding SLUGS are lm_studio / llama_cpp)
```

### 0. Tool resolution — required in every substituted Bash block

`gsd_run` is NOT a PATH binary; core defines it per fenced block via its launcher
preamble. This wrapper's blocks must resolve the tool by absolute path instead:

```bash
GSD_TOOLS="$HOME/.claude/gsd-core/bin/gsd-tools.cjs"
```

and invoke as `node "$GSD_TOOLS" query review-lane invoke ...`.

### 1. Capture and splice RUN_DIR (unchanged contract)

`gather_context` creates the per-run directory and echoes `RUN_DIR=<path>`;
`build_prompt` writes `<RUN_DIR>/gsd-review-prompt.md`; `write_reviews` reads
`<RUN_DIR>/gsd-review-<slug>.md`.

**CRITICAL — substitute the concrete path, not a live variable.** `$RUN_DIR` does
NOT survive across separate Bash tool calls (each call is a fresh shell). Splice the
literal path core printed as `RUN_DIR=…` into every command below, and the repo
root as `<REPO_ROOT>` (from `git rev-parse --show-toplevel`). cwd for every invoke
must be the project root — core resolves config from cwd.

### 2. Fan out the parallel-safe group — ONE Bash call, run_in_background

The Bash tool caps foreground calls at 600,000 ms, while the codex/claude lane
timeout floors are 1,200,000 ms — a foreground barrier WILL be killed mid-review.
The fan-out call MUST therefore be issued with `run_in_background: true`; it
survives across turns and re-invokes you when it exits. Do NOT poll it; continue
when the completion notification arrives.

With `<RUN_DIR>`/`<REPO_ROOT>` spliced and PARALLEL_SELECTED = the space-separated
parallel-safe subset of the selected slugs:

```bash
cd "<REPO_ROOT>"
GSD_TOOLS="$HOME/.claude/gsd-core/bin/gsd-tools.cjs"
PIDS=()
for SLUG in {PARALLEL_SELECTED}; do
  node "$GSD_TOOLS" query review-lane invoke --slug "$SLUG" \
    --run-dir "<RUN_DIR>" --repo-root "<REPO_ROOT>" --json \
    > "<RUN_DIR>/gsd-review-lane-result-$SLUG.json" \
    2> "<RUN_DIR>/gsd-review-lane-invoke-$SLUG.err" &
  PIDS+=($!)
done
wait "${PIDS[@]}"
echo "fanout barrier complete"
for SLUG in {PARALLEL_SELECTED}; do
  [ -s "<RUN_DIR>/gsd-review-$SLUG.md" ] && echo "OK: $SLUG" || echo "EMPTY: $SLUG (see gsd-review-lane-invoke-$SLUG.err)"
done
```

**Accounting check — run this after the serial group (step 3) completes, with
`{ALL_SELECTED}` = every slug core selected, not just the parallel subset.** The
fan-out loop above can only report on lanes it ran; this is what catches a lane
that fell out of the partition entirely:

```bash
MISSING=""
for SLUG in {ALL_SELECTED}; do
  [ -s "<RUN_DIR>/gsd-review-$SLUG.md" ] || MISSING="$MISSING $SLUG"
done
if [ -n "$MISSING" ]; then
  echo "WARNING: no output for selected lane(s):$MISSING" >&2
  echo "Do NOT report review counts as complete — a selected reviewer produced nothing." >&2
fi
```

A lane appearing here means one of: it refused with a typed reason (check
`gsd-review-lane-result-<slug>.json`), it crashed (check `.err`), or the partition
failed to classify it. The third case is a wrapper bug — fix the partition rather
than the symptom. Surface this warning in the final summary; never let a silently
absent reviewer be folded into the CYCLE_SUMMARY counts as if it had run clean.

**The barrier MUST use an array (`PIDS+=($!)` / `wait "${PIDS[@]}"`), not a
space-joined string.** This is required, not stylistic: zsh does not word-split
unquoted parameter expansions, so `wait $PIDS` passes ONE argument, fails with
`wait: job not found`, and returns in ~0.007 s — skipping the barrier entirely and
reporting every still-running lane as EMPTY, with block exit status 0 so nothing
surfaces as an error. Measured: this reproduces in the `run_in_background: true`
shell, which is `/bin/zsh` 5.9 here. The append and the `wait` must change together —
an array assignment left with an unquoted `wait $PIDS` silently waits on only the
FIRST lane under bash, with no error message at all, which is worse. Keep
`PIDS=()` too: a scalar `PIDS=""` leaves an empty element that makes bash emit a
spurious ``wait: `': not a pid or valid job spec``.

Per-lane result JSON goes to separate files (never a shared `>>` append under
concurrency). Each lane self-reports failures into its own `gsd-review-<slug>.md`
diagnostic stub (core's contract), so no single failure aborts the barrier. Typed
refusals (`missing_binary`, `probe_failed`, `egress_host_changed`, …) appear in the
per-lane result JSON — surface them in the final summary rather than silently
dropping a lane.

### 3. Run the serial group with core's loop

For any SELECTED slug in the SERIAL group, run core's own invoke_reviewers loop
body exactly as written — including `prepare_trimmed_prompt_for_reviewer` for the
budgeted local lanes — but with the absolute-path tool resolution from step 0 in
place of `gsd_run`. Short local lanes (120 s floors) may run in a foreground Bash
call; a serial `claude` lane (1,200,000 ms floor) needs its own
`run_in_background: true` call, one lane at a time.

### 4. Continue to <step name="write_reviews">

Proceed with synthesis unchanged. It renders from `<RUN_DIR>/gsd-review-<slug>.md`
per the declared section order regardless of how the files were produced, so
concurrent + serial outputs combine identically. REVIEWS.md format, frontmatter,
and reviewer list are core's, untouched. Run-dir cleanup stays where core does it
(present_results) — never delete the run dir early.
</process>

<notes>
- Zero core edits: survives `gsd update`. The only local artifact is this skill —
  the former standalone engine (`bin/gsd-review-fanout.sh`) is retired; lane
  invocation is core's code end to end.
- Never pass a hook-trust bypass flag or probe for one (core bans it, #2479), and
  never place a `reviewer-lane:` HTML comment marker in any text that could be
  merged into review.md (parity-gate hygiene).
- Correctness of concurrency rests on the partition: only distinct-provider cloud
  lanes are backgrounded. Never background claude or a local-model lane.
- Concurrency safety is a verified property of core's invoke path (all writes are
  per-slug inside the run dir); re-verify that property if a future GSD major
  rearchitects review-lane-runner.
- To use inside the convergence loop, the local plan-review-convergence patch
  dispatches its review Agent against `Skill(skill='gsd-review-concurrent', ...)`.
  CYCLE_SUMMARY math is unaffected — synthesis is still a single pass over all
  outputs.
</notes>
