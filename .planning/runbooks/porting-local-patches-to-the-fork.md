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

**Eleven numbered items; ten live here** (4.9 glab is separated with its own todo). **Each has a tracking todo — see §4c.** Earlier drafts
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

### 4.3b — graphify: the seed-floor invariant is REMOVED ⚠ highest risk, and CI is blind to it

- **Files:** `src/graphify.cts` (the `applyBudget` rewrite, same ~315-line block)
- **Validated 2026-08-20 by execution.** Measured on the real corpus, `--budget` only, no
  `--exclude-file-types` anywhere:

  ```
  PRISTINE  budget=2000  seeds=727  total_nodes=727  total_edges=0  budget_met=false  est=102710
  PATCHED   budget=2000  seeds=727  total_nodes=11   total_edges=9  budget_met=true   est=1954
  ```
  Above the cliff (budget > full payload) the two are **byte-identical** — the change fires only
  under budget pressure.
- **Invariant break PROVEN**, with a counterexample that is worse than "fewer nodes": on a 3-node
  fixture, seed `n0` survives at budget 120 but is **evicted at budget 150** — a *larger* budget
  yielding a *smaller* result for that node. `total_nodes < seeds` reproduced on both synthetic
  and real corpora (`auth`: 727 seeds → 3 nodes at budget 500).
- ⚠⚠ **The existing regression net does not cover this — and will pass anyway.**
  `tests/graphify-query.test.cjs:560` (*"the seed set is a floor the reduction never goes below"*)
  and `:587` (*"a larger budget never yields a smaller payload"*) encode exactly the invariant
  being removed. But their `arbGraph` fixture (`:513-538`) only produces a second seed if
  fast-check happens to generate the substring `auth`. Measured against the repo's pinned config
  (`numRuns: 200, seed: 42`, deterministic): **0 of 200 runs produced ≥2 seeds.** With one seed,
  `setFloor(Math.min(1, rankedSeeds.length))` pins the floor at the whole seed set and the
  invariant coincidentally holds.
  **So porting 4.3b passes the suite while silently breaking the contract those tests exist to
  protect.** Do not treat a green run as evidence. The port must add a **new RED test with a
  deliberately multi-seed, differentiated-match-quality fixture** (the budget-120/150 counterexample
  is a ready template), and must not quietly edit `:560`/`:587` without stating why.
- **The two prior failed attempts are real** and transcribed in the comment (rev 1: floor shrunk
  only at `lo===0` → non-nested feasible sets; rev 2: floor capped at 60% of budget → bigger budget,
  fewer edges). The current approach held across 4 terms × 7 budgets with no regression — but that
  is a **coarse 7-point sweep**; the author's own documented off-by-one dip (`argocd`, budget 22750,
  found at 357-step granularity) was **not** re-derived. Unverified, not doubted.
- **Degenerate inputs are all handled** — zero seeds, budget 0, empty graph, all-equal scores
  (deterministic id-lexicographic tiebreak), negative budget: no exceptions, no NaN, and
  `budget_met: false` correctly reported when even the one-seed floor overshoots.

### 4.4 — graphify budget-cliff: per-edge hop distance

- **Files:** `src/graphify.cts` (rest of the block)
- **What it does:** tracks hop distance per edge in a **`WeakMap` keyed by object identity**.
- **Design note in the patch:** must NOT be a field on the edge, because
  `buildQueryResponse` passes edge objects through verbatim and a field would serialize
  into the response. `WeakMap` over `Map` so edges are collectable when the query drops them.
- **Effectiveness:** high — this is the mechanism that makes graded trimming possible.
- ⚠ **Robustness: one of its two stated rationales does not apply here.** The serialization
  concern is real — but satisfied by *any* external table, not specifically by `WeakMap`
  (`WeakMap.set` never mutates the key; so would a `Map`). The **retention** rationale is
  structurally void: `graph`/`scoped` stays live for the whole synchronous body of `graphifyQuery`,
  and `hopOf`'s keys are the same edge objects held in `graph.edges`, so every edge is strongly
  reachable until the call frame is discarded — at which point `Map` and `WeakMap` become
  collectable simultaneously. graphify runs as a one-shot CLI subprocess per query, so the leak it
  guards against cannot occur. Downgrade from "best-reasoned in the set"; the choice is harmless,
  the justification is half moot.
- **Upstream viability: strong**, and splittability is confirmed: 4.3 and 4.4 are **inert alone**
  because 4.3b's consumers use optional chaining (`seedScoreOf?.get(b) ?? 1`,
  `(hopOf && hopOf.get(e)) ?? 0`). Both are still independently TDD-testable — `seedAndExpand` is
  exported and returns the maps directly. 4.3b is the sole behaviour-changing commit.
- ⚠ **Translation detail missing from §2:** the `.cjs` patch just adds keys to an object literal;
  the `.cts` port must also extend the `ExpandResult` interface (`src/graphify.cts:280-285`) with
  `hopOf: WeakMap<GraphEdge, number>` and `seedScoreOf: WeakMap<GraphNode, number>`.

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

**Validated 2026-08-20 by execution.** Stronger than first written — and it has a
**port-blocking companion change the first draft missed.**

- ⚠ **Porting breaks 3 of 6 existing assertions** in `tests/gsd-statusline.test.cjs:664-692`
  (`context meter respects CLAUDE_CODE_AUTO_COMPACT_WINDOW (#2219)`). Measured with the test
  file's own fixtures: `:668` expects `normalizedUsed===60`, gets 50; `:677` expects 100, gets
  50; `:683` expects 60, gets 50. Expected — the patch deletes the buffer-scaling those
  assertions exist to protect. **A behaviour-removing change triggers the same TDD merge gate as
  a behaviour-adding one.** Rewrite `:664-692` to assert the unbuffered contract, or delete the
  block with a pointer to the new one, **in the same commit**.
- **The patch is measurably safer than pristine**, not merely equivalent. Executed edge cases:
  `used_percentage` present but `remaining_percentage` absent → pristine shows **no meter at
  all**, patched shows 46%. And a **live pristine bug**: with `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  set on a non-1M model, pristine's dynamic-buffer branch defaults `total_tokens` to 1,000,000,
  mis-scales, and **pins the bar at 100% while real usage is 30%**. Patched reads 30%.
- **1M-agnostic by construction** — the patched code does zero window-size arithmetic; it trusts
  CC's pre-calculated `used_percentage`, which the docs define as already measuring against the
  model's full window.
- **Cannot break other hosts.** No runtime/host branching exists in the file; both versions gate
  the whole meter on Claude-specific field presence, and absence no-ops identically. The
  "host-specific" caveat applies to the *env var*, not to file-level breakage.
- ⚠ **Two citation defects to fix before shipping** (neither substantive): the doc quote is a
  paraphrase — the live doc says *"always measures against the model's full context window"*, not
  "always reflects the model's actual full…"; and the comment pairs "+16 points" with
  "(real 60% shown as 72%)" in one sentence, but that example is a **12**-point gap. Both numbers
  are real, from two different scenarios — the +16 comes from the separate 84%→100% pinning case.
  Also, issue refs `#2219`/`#2451` no longer resolve to the right items upstream; the
  currently-resolvable pair for the buffer bug is `#1194`/`#1211`.
- **Upstream viability: moderate**, unchanged — but the case is stronger than first stated, since
  the patch fixes a reproducible pristine display bug rather than only matching a doc contract.

### 4.7 — review-lane timeouts 540s → 1800s ⚠ MOSTLY INERT AS SPECIFIED

**Validated 2026-08-20 by execution. The earlier file list, ported exactly, changes nothing.**

- **The `capability.json` half is provably dead for dispatch.** `antigravity` is already a
  **first-party** lane in `REVIEWER_LANES` (`src/review-lane-descriptor.cts`), and the merge
  loop does `if (bySlug.has(slug)) continue;` (`:654`, D8) — documented at `:608-610`:
  *"an overlay declaring a slug that already names a first-party lane is silently superseded…
  never overwritten."* Demonstrated: mutating the registry's `antigravity.reviewer` to
  `1800s`/`1920000` and re-running `mergeReviewerLanes` still yields `600000` / `540s`, and the
  merged object is `===` the untouched first-party entry. The registry block is read only by
  the validator and roster derivation — never for the invoke timeout.
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
  following the unmodified guidance under-provisions the outer wrapper and the host kills the
  whole loop before the new inner budget is ever reached. **`review.md` is a required companion
  edit.**
- **Registry regeneration is deterministic** — regenerated on a clean tree, byte-identical to the
  committed file. Note this **refutes** `~/.claude/runbooks/gsd-update-runbook.md:404` ("the
  registry is generated from the descriptor"): it is generated from `capabilities/<id>/capability.json`
  only, and `review-lane-descriptor` has no generation relationship to it.
- **Buffer, not ratio:** 600s−540s = 60s becomes 1920s−1800s = 120s. Outer>inner holds, but
  **nothing enforces it** — no validator or test compares the `--print-timeout` string against
  `timeoutFloorMs`. Land one without the other and you get a silent SIGKILL surfacing as an
  unexplained empty stub, the exact failure `review.md:302-306` warns about.
- **Four test files assert the literals** and will break: `tests/antigravity-reviewer.test.cjs:126-152`,
  `tests/review-lane-invocation.test.cjs:88`, `tests/review-lane-descriptor.test.cjs:775,954`.
- **Justification: still none.** Exhaustive search found one artifact —
  `~/.claude/runbooks/gsd-update-runbook.md:399-412`, item 12 — which dates the edit (2026-08-14)
  and describes the mechanics, and notes the patch *"sat in no diff and no runbook entry"* until a
  drift check caught 13 modified against a patch set of 11. It records **no workload, no observed
  timeout, no failure**. "Names a number, not a failure" is confirmed.
- **Revised action:** (a) drop `capabilities/antigravity/capability.json` from the required-for-effect
  list — keep it only for validator/doc consistency; (b) add `gsd-core/workflows/review.md`'s
  guidance as a required companion edit; (c) update the four test files; (d) **local-only** — with
  no failure story there is no upstream case for changing a default.

### 4.8 — convergence: `max-cycles` 3→5, and route to `gsd-review-concurrent`

**Validated 2026-08-20.** Splittable as claimed — 4 hunks, no line overlap, no content
dependency — but **neither half is self-contained at the file list first given.**

- **`max-cycles` has exactly ONE runtime-authoritative site:** `plan-review-convergence.md:31`
  (`if [ -z "$MAX_CYCLES" ]; then MAX_CYCLES=3; fi`). SKILL.md, the `commands/gsd/` twin, and
  every `docs/` mention are text with no runtime effect.
- ⚠ **Its test passes for the wrong reason.** `tests/plan-review-convergence.test.cjs:517-520`
  asserts `workflow.includes('MAX_CYCLES') && workflow.includes('3')`. After the bump `'3'` still
  matches unrelated text (`#2315`, `## 3. Validate Phase`), so the test stays green while its own
  message — *"parses --max-cycles with default of 3"* — becomes false. Touch it or the suite lies.
- ⚠ **The routing half leaves the file self-contradicting.** The patch changes the executable
  prompt to `gsd-review-concurrent` but never touches the file's own success-criteria checklist at
  `:453,462`, which still says `Skill("gsd-review")`. The routing test only passes via an
  OR-fallback that matches *that stale checklist* — an accidental pass, not validation.
- **`gsd-review-concurrent` is genuinely parallel-safe**, not invoke-and-hope. Verified in 1.11.0
  source: `review-lane-invocation.cjs:161-166` keys every write on slug
  (`gsd-review-${slug}.md` / `.err`). The one shared path, `gsd-review-prompt.md`, is written once
  by `build_prompt` (`review.md:242`) strictly before `invoke_reviewers` — single writer, then
  readers only. Its documented zsh `wait $PIDS` footgun was reproduced empirically (scalar form
  no-ops the barrier, exits 0 in ~6ms); the skill already uses the correct array form.
- ⚠ **"Dangling reference" undersells the failure mode.** GSD's own `docs/ARCHITECTURE.md:125`
  records from #924: *"the Skill tool hard-errors on unknown names rather than re-routing."* So
  porting the routing without the skill either aborts loudly (fine — the orchestrator's
  "abort if CYCLE_SUMMARY absent" contract catches it) **or** the review subagent improvises,
  falls back to `gsd-review` or hand-rolls a review, and still emits a well-formed
  `CYCLE_SUMMARY` — the loop then reports counts as if the intended review ran. The silent branch
  could not be ruled out. **Bring the skill onto the same branch**; it is a single self-contained
  `SKILL.md`.
- ⚠ **3→5 is not "bounded like today."** `MAX_CYCLES` is the **only** hard bound. Stall detection
  (`§5c`) is informational — it prints a warning and falls through, with no early exit. No token
  budget, no wall-clock budget. Declared per-lane ceilings sum in the sequential path
  (codex/claude 1,200,000ms each; gemini/qwen/cursor/kimi 900,000; …), so a worst-case cycle can
  exceed an hour and five of them compound it. The bump adds **67% worst-case cost and removes no
  risk**, and a stalled run now burns 5 cycles before escalating instead of 3 — though stall
  detection would have flagged it at cycle 2. Preference call, but a costed one.
- **Upstream viability.** *max-cycles:* viable alone, but an upstream PR also needs the test
  message, the `commands/gsd/` twin (kept in lockstep by project history), and 5 doc surfaces plus
  4 localized trees. None of that is needed for a local-only default. *Routing:* cannot go upstream
  until the skill does.

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
  nothing reads. **Validated 2026-08-20; strongest-founded item in the set.**
- **The producer is real and traceable**, unlike 4.1's. `capabilities/mempalace/capability.json:96-109`
  formally declares a `plan:pre` step: `{"ref":{"skill":"mempalace-recall"},
  "produces":["MEMORY-RECALL.md"],"when":"mempalace.enabled","onError":"skip"}`, and
  `skills/gsd-mempalace-recall/SKILL.md` step 4 says *"Write `MEMORY-RECALL.md` in the current
  phase directory. The planner consumes it."* Reproduced live: `gsd-tools query loop.render-hooks
  plan:pre` on a scratch project with `mempalace.enabled: true` returns the step in `activeHooks`.
- **Three real artifacts on disk**, written this week (Aug 18-19) under
  `~/gsd-workspaces/{security-vpc,bedrock-access,ctem-gitlab-group}/…/phases/76-*/MEMORY-RECALL.md`,
  well-formed and matching the skill's documented format. Live production usage, not just spec.
- **`$phase_dir` is NOT the `$FORGE` defect class.** It is bound by prose in an earlier step
  (`gsd-planner.md:614`, "Extract from init JSON"), and the three **pre-existing** sibling lines
  in the same fence (`*-CONTEXT.md`, `*-RESEARCH.md`, `*-DISCOVERY.md`) already rely on the
  identical cross-fence binding. The new line is a 4th use of a shipped pattern — it cannot
  introduce a scoping bug its neighbours do not already have.
- **Inert by default:** `mempalace.enabled` defaults `false`, so out of the box the step never
  fires and the glob never matches. Contribution is real but scoped to projects that opt in.
- ⚠ **zsh caveat (minor, inherited).** Under zsh's default `NOMATCH`, a non-matching glob makes
  the *shell* abort and print `no matches found:` **before `cat` runs**, so `2>/dev/null` does not
  suppress it. Verified by direct execution. Does not fire in practice — Claude Code's Bash tool
  runs fences via `bash -c` — and all three sibling lines share it. Not introduced here.
- **Upstream viability: strong.** One line, guarded, completes an existing capability's wiring.
  **"Producer with no consumer" is confirmed:** a repo-wide `MEMORY-RECALL` grep at 1.11.0 finds
  only the capability declaration, the producing skill, generated registry output and docs —
  **zero** consumers in any agent or workflow. Arguably an upstream bug.

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

## 4c. Where each concern is tracked

**Every concern in §4 now has its own todo** (`.planning/todos/pending/`), created 2026-08-20.
The todo is the unit of *obligation* and carries that concern's validation verdict inline; this
runbook is the unit of *sequence* and holds the full analysis. Neither supersedes the other —
keep both sides of the link current.

Enumerate them with `node gsd-core/bin/gsd-tools.cjs list-todos`, or
`ls .planning/todos/pending/2026-08-20-port-*.md` for just this campaign.

| Concern | Severity | Todo file (all under `.planning/todos/pending/`) |
|---|---|---|
| 4.1 plan-scan | minor | `2026-08-20-port-4-1-plan-scan-exclude-plan-check.md` |
| 4.2 context7 | major | `2026-08-20-port-4-2-context7-resolve-library-id-requires-query.md` |
| 4.3 seed scoring | minor | `2026-08-20-port-4-3-graphify-score-seeds-by-match-quality.md` |
| 4.3b invariant removal | **major** ⚠ | `2026-08-20-port-4-3b-graphify-seed-floor-invariant-removal.md` |
| 4.4 budget-cliff | minor | `2026-08-20-port-4-4-graphify-budget-cliff-per-edge-hop-distance.md` |
| 4.5 exclude-file-types | major | `2026-08-20-port-4-5-graphify-exclude-file-types-flag.md` |
| 4.6 statusline | major | `2026-08-20-port-4-6-statusline-report-against-real-context-window.md` |
| 4.7 timeouts | major | `2026-08-20-port-4-7-review-lane-timeouts-540s-to-1800s.md` |
| 4.8 convergence | major | `2026-08-20-port-4-8-convergence-max-cycles-and-concurrent-routing.md` |
| 4.9 glab | blocker | `2026-08-20-migrate-the-glab-forge-port-from-gsd-1-10-0-to-1-11-0.md` |
| 4.10 mempalace | minor | `2026-08-20-port-4-10-mempalace-recall-line-in-the-planner.md` |

**None of these are `blocker` except 4.9** — deliberately. Nothing here is broken; these are
ports of working local patches. Five genuine blockers already sit in `todos/pending/` and
stamping this campaign `blocker` would destroy that signal.

**Deliberately NOT captured as seeds, backlog, or threads.** Seeds need a *trigger condition*
and an undecided proposal — the decision here is already made. Backlog needs a `ROADMAP.md`,
which this repo does not have (it is not run as a GSD project). A thread would be a second
ordered index of the same set, free to diverge from this runbook; the bidirectional link above
gives the campaign grouping without a duplicate registry.

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
