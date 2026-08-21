# Runbook — porting the 1.10.0 local patch set into the fork

**Goal:** bring the 19 modifications in `~/.claude/gsd-core` (installed 1.10.0) onto
`local/*` branches of this fork at 1.11.0, examining each for effectiveness and
robustness, and shaping each so it *could* go upstream.

**Status 2026-08-20:** analysis complete, nothing ported yet. Work through §4 one at a time.

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
diff -rq /tmp/gsd-norm/gsd-core ~/.claude/gsd-core
```

Result: **19 modified files across `gsd-core/`, `agents/`, `hooks/`, `skills/` — all 19
recorded in `~/.claude/scripts/gsd-local-patches-1.10.0.diff`, zero unrecorded drift.**

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
| `gsd-core/bin/lib/capability-registry.cjs` | **generated** — `capabilities/{gemini,cursor}/capability.json`, then `npm run gen:capability-registry` |
| `agents/*.md`, `gsd-core/**/*.md` | direct (tracked source) |
| `hooks/gsd-statusline.js` | direct (tracked; `scripts/build-hooks.js:64` copies it) |

Run `make build` after any `src/` or `capabilities/` edit — the compiled lib is what runs.

---

## 3. Gates every branch must clear

From `CONTRIBUTING.md` / `docs/contributor-standards.md` (distilled in
`.planning/reference/contributing-reference.md`):

- **One concern per PR.** Eight concerns → eight branches. The graphify trio should split
  into three; they are independently defensible.
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

## 4. The eight concerns

Ordered by recommended sequence. Each is independent.

### 4.1 — `plan-scan`: exclude `PLAN-CHECK.md` from the plan count ⭐ start here

- **Files:** `src/plan-scan.cts` (13 lines added)
- **What it does:** `{phase}-PLAN-CHECK.md` is the `gsd-plan-checker`'s derivative output —
  same class as `-PLAN-REVIEW.md`, which is already excluded. Without the exclusion it falls
  through the loose `/PLAN/i` fallback in `isRootPlanFile` and counts as an executable plan.
- **Consequence (stated in the patch):** a phase with N real plans and N summaries reads
  N+1 plans / N summaries → `implementation_complete: false`. **A phase that can never
  register as done.**
- **Effectiveness:** high. Precise, one-line-class fix with a named wrong outcome.
- **Robustness:** good — it extends an existing exclusion list rather than adding a new
  mechanism. Carries its own reapplication date (2026-08-04, reapplied 2026-08-12).
- **Upstream viability: strongest of the set.** Pure bug fix, trivially testable, no
  preference component.
- **Why first:** smallest surface, easiest RED test, establishes the whole pattern
  (branch → translate `.cjs`→`.cts` → TDD → changeset → build → verify) at minimum scale.
- **Test shape:** fixture phase dir with N plans + N summaries + one `PLAN-CHECK.md`;
  assert `implementation_complete === true`. Fails before, passes after.

### 4.2 — context7: `resolve-library-id` requires `query` as well as `libraryName`

- **Files:** `agents/gsd-advisor-researcher.md`, `agents/gsd-executor.md`,
  `gsd-core/workflows/discovery-phase.md`, `gsd-core/references/research-documentation-lookup.md`
- **What it does:** upstream documents the call as taking `libraryName` only. The patch
  corrects it to **both required**, and expands the "context7 genuinely unavailable"
  fallback conditions (user scope lives in `~/.claude.json`, etc.).
- **Effectiveness:** high — a wrong call signature fails every documentation lookup.
- **Robustness:** doc-only, no build, no runtime risk.
- **Upstream viability: strong.** Factual API correction, verifiable against the context7
  tool schema.
- **Note:** `gsd-executor.md` also *drops* `mcp__plugin_context7_context7__*` from the
  availability check. **Confirm that is intentional** — if the plugin-scoped server is
  still a real deployment, removing it narrows detection. This is the one part of 4.2 that
  is not obviously a correction.

### 4.3 — graphify seed-floor: score seeds by match quality

- **Files:** `src/graphify.cts` (part of the ~315-line block)
- **What it does:** scores each seed by match quality so the budget trimmer can shed weak
  matches, instead of treating a substring sweep as an inviolable floor.
- **Measured, in the patch comment:** `"auth"` also matches author/authorization/authentik
  → **701 seeds, 95,231 tokens, 47× the planner's 2,000-token budget.**
- **Effectiveness:** high, and it is the only patch in the set with a quantified before.
- **Robustness:** scoring only, no filtering at that site — a deliberately conservative
  seam. Verify the trimmer is the sole consumer.
- **Upstream viability: strong**, given the measurement. Needs a reproducible benchmark
  rather than a one-off number.

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

- **Files:** `src/graphify-command-router.cts` (+33), plus call sites in
  `gsd-core/references/planner-load-graph-context.md` and `agents/gsd-phase-researcher.md`
- **What it does:** new flag separating **corpus membership** from **retrieval
  eligibility**. Upstream offers only `.graphifyignore`, which deletes facts outright.
  Agent call sites pass `document` so the planner stops spending budget on the project's own
  planning notes — **68% of nodes in the measured repo** — while rules can still join
  against them.
- **Effectiveness:** high; the conceptual split is the real contribution.
- **Robustness:** additive flag, default-off ⇒ no behaviour change for existing users.
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

- **Files:** `capabilities/{gemini,cursor}/capability.json` → regenerate registry;
  `src/review-lane-descriptor.cts`
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
| `gsd-core/workflows/discovery-phase.md` | 4.2 | no |
| `gsd-core/workflows/plan-review-convergence.md` | 4.8 convergence | no |
| `gsd-core/workflows/ship.md` · `inbox.md` · `pr-branch.md` | 4.9 glab | no |
| `skills/gsd-plan-review-convergence/SKILL.md` | 4.8 convergence | no |
| `hooks/gsd-statusline.js` | 4.6 statusline | no — tracked source |
| `bin/lib/graphify.cjs` | 4.3 + 4.4 | **yes → `src/graphify.cts`** |
| `bin/lib/graphify-command-router.cjs` | 4.5 | **yes → `src/graphify-command-router.cts`** |
| `bin/lib/plan-scan.cjs` | 4.1 | **yes → `src/plan-scan.cts`** |
| `bin/lib/review-lane-descriptor.cjs` | 4.7 timeouts | **yes → `src/review-lane-descriptor.cts`** |
| `bin/lib/capability-registry.cjs` | 4.7 timeouts | **yes → `capabilities/*/capability.json` + regenerate** |

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

```bash
git checkout -b local/<slug> next
# translate the patch to real source (§2) — never edit bin/lib/*.cjs
# RED: failing test, own commit
# GREEN: minimal fix
# REFACTOR: separate commit
make build                                   # compiled lib is what runs
env -u GSD_AGENTS_DIR npm test
npm run lint:ci
make rebuild-working && make install         # exercise it for real
```

Add a changeset only if the branch is being promoted to a contribution branch off `next`.

## 7. Standing caveats

- **Never edit `gsd-core/bin/lib/*.cjs`** — gitignored build output; the edit vanishes on
  the next `make build` and never reaches source.
- **Never edit `.claude/agents/`** — install-sync output. Edit `agents/`.
- The installed `~/.claude` tree is 1.10.0. Patches were authored there; **line numbers will
  have drifted at 1.11.0.** Re-anchor by content, not by line.
- Every patch is currently *only* in `~/.claude/scripts/gsd-local-patches-1.10.0.diff`. Until
  a branch exists, `/gsd-update` (which installs upstream via npx) destroys it.
