# Runbook — porting the 1.10.0 local patch set into the fork

**Goal:** bring the 19 modifications in `~/.claude/gsd-core` (installed 1.10.0) onto
`local/*` branches of this fork at 1.11.0, examining each for effectiveness and
robustness, and shaping each so it *could* go upstream.

**Status 2026-08-20:** analysis complete and **independently validated**; nothing ported yet.
Work through §4 one at a time.

> **Validated 2026-08-20** by a separate empiricist agent running every claim against the real
> trees. It found 3 CRITICAL errors — all corrected above and marked ⚠: the 540s timeout file
> (gemini/cursor → **antigravity**), a missing implementation file in 4.5 (**`src/graphify.cts`**),
> and a checklist whose first step deletes the Makefile it then calls. It also surfaced 4.3b,
> a removed invariant the first draft framed as additive. Claims it could NOT verify are marked
> "unverified" inline — treat those as open, not settled.

---

## 1. How the patch set was established

Diffed a **pristine 1.10.0 install** against `~/.claude`, not the git tag. `bin/install.js`
rewrites files on the way out, so a tag diff measures the build, not your edits:

| baseline (`gsd-core/` only) | files differing | false positives |
|---|---|---|
| git tag `v1.10.0` | 157 | 148 |
| pristine install, raw | 128 | 115 |
| pristine install, config-dir normalized | **13** | **0** |

Reproduce:

```bash
npx -y --package=@opengsd/gsd-core@1.10.0 -- gsd-core --claude --global \
    --config-dir /tmp/gsd-pristine-1100
cp -R /tmp/gsd-pristine-1100 /tmp/gsd-norm
find /tmp/gsd-norm -type f \( -name '*.md' -o -name '*.cjs' -o -name '*.js' -o -name '*.json' \) \
  -exec perl -pi -e 's{/tmp/gsd-pristine-1100}{\$HOME/.claude}g' {} +
diff -rq /tmp/gsd-norm ~/.claude          # FULL tree — the gsd-core-only form yields 13, not 19
```

The full-tree form yields 23 `Files … differ`: the **19** real GSD modifications plus 4
bookkeeping files that always differ (`.gsd-source`, `gsd-file-manifest.json`,
`gsd-install-state.json`, `settings.json`). Scope to `gsd-core/` only and you see 13,
because the other 6 live in `agents/`, `hooks/` and `skills/`.

Result: **19 modified files across `gsd-core/`, `agents/`, `hooks/`, `skills/` — all 19
recorded in `~/.claude/scripts/gsd-local-patches-1.10.0.diff`, zero unrecorded drift.**
Verified both directions with `comm`; both set differences empty.

**Scope of that claim:** it covers *modifications to shipped files* only. A full-tree diff also
shows ~45 `Only in ~/.claude` entries — 17 personal agents, ~13 hooks, ~14 skills (including
`gsd-review-concurrent`), a generated `gsd-core/USER-PROFILE.md`, and two stray patch artifacts
(`bin/lib/capability-registry.cjs.bak-540s`, `review-lane-descriptor.cjs.bak-540s`). Those are
additions, not drift, and survive updates because they are not `gsd-`-prefixed shipped content.

**All 8 concerns are still live at 1.11.0.** Verified individually — nothing was fixed
upstream in the interim (unlike the frontmatter escape-doubling defect, which was).

---

## 2. BLOCKING: most patches target build output, not source

Four of five patched `.cjs` files are **gitignored tsc output** in this repo. They cannot
be copied across — they must be re-authored against the TypeScript source.

| Patched file (installed tree) | True source here |
|---|---|
| `gsd-core/bin/lib/graphify.cjs` | `src/graphify.cts` |
| `gsd-core/bin/lib/graphify-command-router.cjs` | `src/graphify-command-router.cts` |
| `gsd-core/bin/lib/plan-scan.cjs` | `src/plan-scan.cts` |
| `gsd-core/bin/lib/review-lane-descriptor.cjs` | `src/review-lane-descriptor.cts` |
| `gsd-core/bin/lib/capability-registry.cjs` | **generated** — `capabilities/antigravity/capability.json` (`:121`), then `npm run gen:capability-registry` |
| `agents/*.md`, `gsd-core/**/*.md` | direct (tracked source) |
| `hooks/gsd-statusline.js` | direct (tracked; `scripts/build-hooks.js:64` copies it) |

Run `make build` after any `src/` or `capabilities/` edit — the compiled lib is what runs.

---

## 3. Gates every branch must clear

From `CONTRIBUTING.md` / `docs/contributor-standards.md` (distilled in
`.planning/reference/contributing-reference.md`):

- **One concern per PR.** Nine live concerns → nine branches. The graphify block is one diff
  hunk but four concerns (4.3, 4.3b, 4.4, 4.5); split the commits even though the port is atomic.
- **Branch off `next`**, never off `working` or another `local/*`.
- **TDD is a merge gate** for behavior-adding work: RED (failing test, own commit) → GREEN
  → REFACTOR, committed separately.
- **Changeset** required when touching `bin/`, `gsd-core/`, `src/`, `agents/`, `commands/`,
  `hooks/`: `npm run changeset -- --type <T> --pr <N>`. Never edit `CHANGELOG.md`.
- **Never edit `.claude/agents/`** — that is install-sync output. Edit `agents/`.
- Verify before push: `env -u GSD_AGENTS_DIR npm test`, `npm run lint:ci`,
  `GITHUB_BASE_REF=next node scripts/changeset/lint.cjs`.
- Upstream additionally requires a maintainer-labelled issue before any code. That gate is
  theirs, not ours — it only applies if a branch is actually promoted.

**Local-first is the default.** Each branch is useful on its own merits via
`make rebuild-working && make install`. Upstream promotion is optional and per-branch.

---

## 4. The concerns

**Ten numbered items; nine live** (4.9 glab is separated with its own todo). Earlier drafts
said "eight" — that predates splitting the graphify block, which is three concerns (4.3,
4.3b, 4.4, 4.5 — four counting the flag) sharing one diff hunk.

Ordered by recommended sequence. Each is independent unless noted.

### 4.1 — `plan-scan`: exclude `PLAN-CHECK.md` from the plan count ⭐ start here

- **Files:** `src/plan-scan.cts` (13 lines added)
- **What it does:** `{phase}-PLAN-CHECK.md` was **observed in production** and is the same
  class of derivative artifact as `-PLAN-REVIEW.md`, which is already excluded.
  ⚠ **Provenance unverified:** a repo-wide grep across the 1.11.0 fork, the pristine 1.10.0
  install and the full `~/.claude` tree finds **zero producers** of that filename;
  `gsd-plan-checker` returns an inline YAML block (`gsd-core/workflows/plan-phase.md:1085`),
  not a file. The incident is real and documented (`~/.claude/runbooks/gsd-update-runbook.md:259-272`
  — rbac-backport phase 05 read 7 plans/6 summaries pristine, 6/6 patched), but do not claim
  a producer upstream without locating one. The regex defect alone justifies the fix.
  **The artifact itself was found** at
  `~/gsd-workspaces/plane-audit-logs/plane/.planning/workstreams/rbac-backport/phases/05-*/05-PLAN-CHECK.md`
  — a real "Phase 05 Plan Check" report beside exactly 6 PLAN/SUMMARY pairs, matching the
  incident. But `gsd-plan-checker`'s frontmatter carries `disallowedTools: Write, Edit, MultiEdit`,
  so that agent **cannot** have written it, and no workflow at 1.10.0 or 1.11.0 has a `Write`
  targeting that name. Honest framing: "reapply if this recurs", not "this happens today". Without the exclusion it falls
  through the loose `/PLAN/i` fallback in `isRootPlanFile` and counts as an executable plan.
- **Consequence (stated in the patch):** a phase with N real plans and N summaries reads
  N+1 plans / N summaries → `implementation_complete: false`. **A phase that can never
  register as done.**
- **Effectiveness:** high for the observed instance. ⚠ **Not a "class" fix** — validated
  2026-08-20 by enumeration against patched and unpatched `isRootPlanFile`. It excludes exactly
  one anchored literal (`-PLAN-CHECK.md$`, case-insensitive). These all still leak and
  reproduce the identical N+1 failure: `-PLAN-NOTES.md`, `-PLAN-DRAFT.md`, `-REPLAN.md`,
  `PLANNING.md`, `05-planning.md`, `-PLAN-CHECKLIST.md`, and bare `PLAN-CHECK.md` (no dash).
  Frame it as "fixes the one observed instance"; the underlying defect is the unanchored
  `/PLAN/i` fallback itself.
- **Robustness:** good — it extends an existing exclusion list rather than adding a new
  mechanism. Carries its own reapplication date (2026-08-04, reapplied 2026-08-12).
- **Upstream viability: strongest of the set.** Pure bug fix, trivially testable, no
  preference component.
- **Why first:** smallest surface, easiest RED test, establishes the whole pattern
  (branch → translate `.cjs`→`.cts` → TDD → changeset → build → verify) at minimum scale.
- **Test shape — already written and run.** Mirror `row11` (`-PLAN-REVIEW.md`) in
  `tests/plan-count-single-owner.test.cjs:173-184`. Measured on a real 3-pair fixture against
  this repo's built `plan-scan.cjs`:
  `BEFORE → planCount 4, summaryCount 3, completed false` · `AFTER → 3, 3, true`.
  RED confirmed mechanically (`2 !== 1`), GREEN confirmed with the patch applied to a /tmp copy.
- **Robustness — the mechanism is right, and deliberately so.** `src/plan-scan.cts:119-134`
  documents that the loose fallback is *intentionally* permissive so an off-pattern real plan
  (lowercase `plan.md`) still counts; `plan-count-single-owner.test.cjs` row12+ pins that.
  Tightening the fallback risks false negatives on real plans. Named anchored exclusions have
  zero false-negative risk — verified `-PLAN-CHECKLIST.md` still counts, so the anchor does not
  over-match. Three such regexes already exist (`OUTLINE`/`PRE_BOUNCE`/`REVIEW`); this is the
  established pattern, just an incomplete application of it.

### 4.2 — context7: `resolve-library-id` requires `query` as well as `libraryName`

- **Files (3, not 4):** `agents/gsd-advisor-researcher.md`, `agents/gsd-executor.md`,
  `gsd-core/references/research-documentation-lookup.md`
- ⚠ **`gsd-core/workflows/discovery-phase.md` DOES NOT EXIST at 1.11.0.** Deleted upstream in
  `c5b83cb0` — *"delete two unreachable workflows"* (#3560/#3564), confirmed an ancestor of
  `v1.11.0`. It was dead code: nothing referenced it. The patch predates the deletion (patch
  authored Aug 12, deleted Aug 15). There is **no successor file** — `git log --follow` finds
  no rename. Drop it from scope; do not hunt for somewhere to re-anchor its hunk.
- **What it does:** upstream documents the call as taking `libraryName` only. The patch
  corrects it to **both required**, and expands the "context7 genuinely unavailable"
  fallback conditions (user scope lives in `~/.claude.json`, etc.).
- **Effectiveness:** high — a wrong call signature fails every documentation lookup.
- **Robustness:** doc-only, no build, no runtime risk. Verified: 3 stale `libraryName`-only
  sites remain at 1.11.0 and the patch covers all of them — a repo-wide grep finds no others.
- **Verified against the live tool schema**, not docs: `resolve-library-id`'s `required` array
  is `["query", "libraryName"]`. Both genuinely required.
- **Upstream viability: strong.** Factual API correction, verifiable against the context7
  tool schema.
- ⚠ **Open question, now with evidence.** `gsd-executor.md` *drops*
  `mcp__plugin_context7_context7__*` from the availability check. Validated 2026-08-20:
  that pattern is **live and current** in 1.11.0 — present in 8 other files
  (`gsd-domain-researcher`, `gsd-project-researcher`, `gsd-advisor-researcher`,
  `gsd-ui-researcher`, `gsd-phase-researcher`, `gsd-ai-researcher`, `gsd-planner`,
  `docs/AGENTS.md`). Not legacy cruft.
  **Scope of the change is narrower than it looks:** the removal is from *body prose* only —
  the frontmatter `tools:` allowlist at `~/.claude/agents/gsd-executor.md:4` still grants it.
  So the effect is a detection gap (the model may not think to look under that name), not a
  permissions gap. Decide deliberately; do not port it as if it were part of the API fix.
  **Settled 2026-08-20:** the plugin is *installed but disabled* here
  (`~/.claude/settings.json:251` → `"context7@claude-plugins-official": false`, with 1,574
  historical uses recorded) — real config currently switched off, not cruft. The live tools in
  use come from a separate user-scope HTTP entry at `~/.claude.json:4431`. And nothing in CI
  constrains it: `tests/context7-tool-name-parity.test.cjs` never references the plugin-scoped
  name. Porting the prose removal is safe; it is a judgement call, not a correctness fix.

### 4.3 — graphify seed-floor: score seeds by match quality

- **Files:** `src/graphify.cts` (part of the ~315-line block)
- **What it does:** scores each seed by match quality so the budget trimmer can shed weak
  matches, instead of treating a substring sweep as an inviolable floor.
- **Measured, in the patch comment:** `"auth"` also matches author/authorization/authentik
  → **701 seeds, 95,231 tokens, 47× the planner's 2,000-token budget.**
- **Effectiveness:** high — it carries a quantified before. (An earlier draft called it the
  *only* such patch; that is wrong. 4.5 measures `document 15,069 / 22,219 nodes (68%)` and
  4.6 measures `+16 points, real 60% shown as 72%`.)
- **Robustness:** scoring only, no filtering at that site — a deliberately conservative
  seam. Verify the trimmer is the sole consumer.
- **Upstream viability: strong**, given the measurement. Needs a reproducible benchmark
  rather than a one-off number.

### 4.3b — graphify: the seed-floor invariant is REMOVED ⚠ largest undescribed change

- **Files:** `src/graphify.cts` (the `applyBudget` rewrite, inside the same ~315-line block)
- **Surfaced by validation 2026-08-20.** 4.3 and 4.4 describe scoring and hop-tracking as
  conservative/additive. The same hunk also **replaces the whole-tier confidence-deletion
  algorithm with a continuous per-edge ranker** (confidence → relation → hop → weight →
  lexical, binary search over prefix length, two-pass seed-floor optimisation whose comment
  records two prior failed attempts).
- **The patch says so itself, verbatim:** *"upstream's 'seeds are an inviolable floor'
  invariant is REMOVED by this patch — PASS 1 pins the floor to a single seed and PASS 2
  grows it only as far as the budget allows. So `total_nodes` may be far below the seed
  count, and a reader must NOT assume `total_nodes >= seeds matched`."*
- **This is unconditional.** It fires for **any** budgeted graphify query, not only when
  `--exclude-file-types` is passed. Output shape changes for every existing budgeted caller.
- **Robustness: the highest-risk item in the set**, and the one whose framing was most wrong
  in the first draft. It is not additive and it breaks a documented invariant.
- **Upstream viability: needs its own PR and its own argument.** Removing an invariant is a
  breaking change to a contract; it wants the benchmark from 4.3 plus an explicit note that
  `total_nodes >= seeds` no longer holds.
- **Action:** port 4.3/4.4/4.3b together — they are one hunk — but write them up as three
  commits, and do not describe the result as additive.

### 4.4 — graphify budget-cliff: per-edge hop distance

- **Files:** `src/graphify.cts` (rest of the block)
- **What it does:** tracks hop distance per edge in a **`WeakMap` keyed by object identity**.
- **Design note in the patch:** must NOT be a field on the edge, because
  `buildQueryResponse` passes edge objects through verbatim and a field would serialize
  into the response. `WeakMap` over `Map` so edges are collectable when the query drops them.
- **Effectiveness:** high — this is the mechanism that makes graded trimming possible.
- **Robustness: the best-reasoned patch in the set.** It anticipates two failure modes
  (serialization leak, retention leak) and states why each choice avoids them.
- **Upstream viability: strong**, but it is coupled to 4.3 — sequence them together even
  as separate commits.

### 4.5 — graphify `--exclude-file-types`

- **Files:** `src/graphify.cts` (**the implementation — `filterGraphByFileType()`, ~95 lines**),
  `src/graphify-command-router.cts` (+33, **flag parsing only**), plus call sites in
  `gsd-core/references/planner-load-graph-context.md` and `agents/gsd-phase-researcher.md`
- ⚠ **Corrected 2026-08-20:** an earlier draft omitted `src/graphify.cts`. The router hunk is
  purely CLI parsing plus one call; `filterGraphByFileType` — the corpus/eligibility split, the
  `matched_nodes_excluded` counting, edge-consistency filtering, and the wiring into
  `graphifyQuery`/`applyBudget`/`buildQueryResponse` — is all in `graphify.cts`. A branch built
  from the old list would ship a flag with no behaviour behind it.
- **What it does:** new flag separating **corpus membership** from **retrieval
  eligibility**. Upstream offers only `.graphifyignore`, which deletes facts outright.
  Agent call sites pass `document` so the planner stops spending budget on the project's own
  planning notes — **68% of nodes in the measured repo** — while rules can still join
  against them.
- **Effectiveness:** high; the conceptual split is the real contribution. The 68% figure is
  internally consistent (15,069 document + 5,573 code + 1,489 rationale + 88 concept = 22,219
  exactly) and names its corpus (`bootstrap-terraform`), but is not reproducible off that repo.
- **Robustness: more defensive than first credited.** Validated by execution 2026-08-20 —
  every malformed input **fails loudly**, none silently no-ops: empty / whitespace / separator-only
  → usage error exit 1; unknown type → `Unknown file_type(s)` exit 1; wrong case (`Document`) →
  rejected, not silently non-matching; duplicates dedupe correctly. The router validates against
  `KNOWN_FILE_TYPES = ['code','document','rationale','concept']` **before** calling the filter.
  The edges-vs-links key hazard its own comment names is genuinely closed — tested with a `links`
  fixture, it detected the key, dropped the node and both touching edges.
- ⚠ **"Purely additive / default-off" is true only for UNBUDGETED queries.** Measured: with no
  flag and no budget, patched output is byte-identical to pristine. With `--budget 200` and no
  flag, they differ (pristine 4 nodes/0 edges, patched 3/1). The filter never ran — that
  divergence is **4.3b's invariant removal**, not this flag. Do not state the additive claim
  without that carve-out.
- ⚠ **The `.graphifyignore` rationale is unsourced.** The patch comment argues upstream "only
  offers `.graphifyignore`, which deletes facts". That string appears **only inside the patch
  itself** — nowhere in 1.11.0 source, compiled output, docs, or git history, and no
  `.graphifyignore` file exists anywhere on this machine. It may refer to the separate external
  `graphify` tool rather than gsd-core. **Get a citation before shipping this rationale upstream.**
- **Upstream viability: strong.** Additive, defaults preserved, clear rationale.
- **Docs bonus:** both call-site files teach the matching model — *"Choose the term the
  graph knows, not the concept. Matching is literal, case-insensitive substring — no
  stemming, no synonyms, no fuzzy matching."* That is genuinely useful independent of the flag.

### 4.6 — statusline: report against the model's real context window

- **Files:** `hooks/gsd-statusline.js` (+25/−21) — **direct source, no translation needed**
- **What it does:** reports usage against the model's actual full window so it matches
  `/context` exactly, citing Claude Code's `CLAUDE_CODE_AUTO_COMPACT_WINDOW` contract.
- **Effectiveness:** high if the cited contract is current.
- **Robustness: verify before porting.** The patch cites `code.claude.com/docs/en/env-vars`.
  Re-check that env var still behaves as described — this is exactly the class of
  third-party claim that goes stale.
- **Upstream viability: moderate.** Depends on whether upstream wants to track a Claude
  Code-specific env var; it is host-specific in a multi-host project.

### 4.7 — review-lane timeouts 540s → 1800s

- **Files:** `capabilities/antigravity/capability.json` (`:121`) → regenerate registry;
  `src/review-lane-descriptor.cts`
- ⚠ **Corrected 2026-08-20:** an earlier draft named `capabilities/{gemini,cursor}/capability.json`.
  Both contain **zero** `540s`/`--print-timeout` hits — gemini's only timeout key is an
  unrelated `timeoutFloorMs: 900000`. The patched values sit under `"slug": "antigravity"`.
  Editing gemini/cursor would change the wrong lane.
- **What it does:** native `--print-timeout` 540s→1800s and external cap 600000ms→1920000ms.
  Both layers move together, preserving outer-cap > inner-timeout.
- **Effectiveness:** unknown — **this is the weakest patch in the set.**
- **Robustness:** the two-level relationship is correctly maintained. But it is the **only
  patch whose comment states what changed without stating what failed.** Every other patch
  names a wrong outcome; this one names a number.
- **Upstream viability: weak as-is.** Needs "review lane X timed out at 540s on workload Y"
  to be arguable. Without that it reads as local tuning, which is a fine reason to keep it
  local and a poor reason to ask upstream to change a default.
- **Action:** before porting, decide whether you can reconstruct what timed out. If not,
  port it local-only and label it tuning.

### 4.8 — convergence: `max-cycles` 3→5, and route to `gsd-review-concurrent`

- **Files:** `skills/gsd-plan-review-convergence/SKILL.md`,
  `gsd-core/workflows/plan-review-convergence.md`
- **What it does:** two unrelated things in one patch — raises the replan cycle default,
  and swaps the sequential reviewer for your personal `gsd-review-concurrent` skill.
- **Effectiveness:** the concurrent routing is a real throughput win; the default bump is
  preference.
- **Robustness:** the routing hard-depends on `skills/gsd-review-concurrent`, which is a
  **personal skill not present upstream**. Porting the workflow change without the skill
  produces a dangling reference.
- **Upstream viability: none as bundled.** Split it: the `max-cycles` default could be
  argued separately; the routing cannot go upstream at all until the skill does.
- **Action:** split into two, keep the routing local, and bring the skill onto the same
  branch so the reference resolves.

### 4.9 — glab / GitLab support (already tracked)

- **Files:** `gsd-core/workflows/{ship,inbox,pr-branch}.md`, `gsd-core/references/checkpoints.md`
- **Status: already captured** as a blocker todo —
  `.planning/todos/pending/2026-08-20-migrate-the-glab-forge-port-*.md`. Upstream refused
  GitLab support (#2138); permanently local. The port is also **inert as installed**
  (`$FORGE` never reaches its guards). Do not re-analyse here; work that todo.

### 4.10 — mempalace recall line in the planner

- **Files:** `agents/gsd-planner.md` (+1)
- **What it does:** `cat "$phase_dir"/*MEMORY-RECALL.md` so the planner picks up
  `mempalace-recall`'s `plan:pre` output.
- **Effectiveness:** high value per byte — without it the recall step produces an artifact
  nothing reads.
- **Robustness:** `2>/dev/null`, so it no-ops when the capability is off. Safe.
- **Upstream viability: strong.** One line, guarded, completes an existing capability's
  wiring. Arguably an upstream bug that the producer had no consumer.

---

## 4b. Where each modified file lands

The concerns above cut across directories, so the four **agent** files in particular are
split over three sections. Full map of all 19:

| File | Concern | Source translation needed? |
|---|---|---|
| `agents/gsd-advisor-researcher.md` | 4.2 context7 | no — direct |
| `agents/gsd-executor.md` | 4.2 context7 (+ the `mcp__plugin_context7_*` question) | no — direct |
| `agents/gsd-phase-researcher.md` | 4.5 exclude-file-types (call site + matching-model docs) | no — direct |
| `agents/gsd-planner.md` | 4.10 mempalace recall | no — direct |
| `gsd-core/references/planner-load-graph-context.md` | 4.5 (call site + docs) | no |
| `gsd-core/references/research-documentation-lookup.md` | 4.2 | no |
| `gsd-core/references/checkpoints.md` | 4.9 glab | no |
| ~~`gsd-core/workflows/discovery-phase.md`~~ | **4.2 — DROP** | file deleted upstream (`c5b83cb0`) |
| `gsd-core/workflows/plan-review-convergence.md` | 4.8 convergence | no |
| `gsd-core/workflows/ship.md` · `inbox.md` · `pr-branch.md` | 4.9 glab | no |
| `skills/gsd-plan-review-convergence/SKILL.md` | 4.8 convergence | no |
| `hooks/gsd-statusline.js` | 4.6 statusline | no — tracked source |
| `bin/lib/graphify.cjs` | **4.3 + 4.3b + 4.4 + 4.5** (one hunk, four concerns) | **yes → `src/graphify.cts`** |
| `bin/lib/graphify-command-router.cjs` | 4.5 | **yes → `src/graphify-command-router.cts`** |
| `bin/lib/plan-scan.cjs` | 4.1 | **yes → `src/plan-scan.cts`** |
| `bin/lib/review-lane-descriptor.cjs` | 4.7 timeouts | **yes → `src/review-lane-descriptor.cts`** |
| `bin/lib/capability-registry.cjs` | 4.7 timeouts | **yes → `capabilities/antigravity/capability.json` + regenerate** |

**All four agent edits are direct-source and need no translation** — `agents/*.md` is
tracked here. Two of them (`gsd-executor`, `gsd-phase-researcher`) are the *only* place a
concern's rationale is written down for the model rather than for a human, so they carry
weight out of proportion to their line counts.

Note `gsd-phase-researcher.md` is the largest agent change (+58/−5): it is not just a call
site, it teaches the literal-substring matching model. That prose is independently useful
and could ship even if 4.5's flag did not.

## 5. Recommended sequence

1. **4.1 plan-scan** — pilot. Smallest, sharpest, establishes the pattern.
2. **4.10 mempalace line** — one line, proves the `agents/` path end to end.
3. **4.2 context7** — doc-only, four files, resolve the `mcp__plugin_context7_*` question.
4. **4.5 exclude-file-types**, then **4.3 seed-floor** + **4.4 budget-cliff** — the graphify
   block. Largest and most valuable; do it once the pattern is routine.
5. **4.6 statusline** — after re-verifying the env-var contract.
6. **4.8 convergence** — split first.
7. **4.7 timeouts** — last; decide local-only vs. justified.
8. **4.9 glab** — separate, already has its own todo.

## 6. Per-branch checklist

> ⚠ **The Makefile does not exist on `next`.** It is tracked on `working`/`local/*` only
> (`b20ee61b`, deliberately never merged). `git checkout -b <slug> next` therefore **deletes
> it from disk**, and every `make` command below fails with "No rule to make target".
> Either copy it onto the new branch first, or use the `npm` equivalents shown.

```bash
git checkout -b local/<slug> next
cp ../Makefile . 2>/dev/null || git checkout local/track-planning-history -- Makefile
# translate the patch to real source (§2) — never edit bin/lib/*.cjs
# RED: failing test, own commit
# GREEN: minimal fix
# REFACTOR: separate commit
npm run build                                # or `make build` if you restored the Makefile
env -u GSD_AGENTS_DIR npm test
npm run lint:ci
# then: git checkout working && make rebuild-working && make install
```

Add a changeset only if the branch is being promoted to a contribution branch off `next`.

## 7. Standing caveats

- **Never edit `gsd-core/bin/lib/*.cjs`** — gitignored build output; the edit vanishes on
  the next `make build` and never reaches source.
- **Never edit `.claude/agents/`** — install-sync output. Edit `agents/`.
- The installed `~/.claude` tree is 1.10.0. Patches were authored there; **line numbers will
  have drifted at 1.11.0.** Re-anchor by content, not by line — but first check the file still
  exists. At least one patch target (`gsd-core/workflows/discovery-phase.md`) was **deleted**
  upstream between 1.10.0 and 1.11.0; "re-anchor by content" would send you hunting for a home
  that no longer exists. Confirm `git ls-files <path>` before porting any hunk.
- Every patch is currently *only* in `~/.claude/scripts/gsd-local-patches-1.10.0.diff`. Until
  a branch exists, `/gsd-update` (which installs upstream via npx) destroys it.
