# Roadmap: gsd-core (faffi fork) — v1.12

## Overview

This milestone repairs 22 captured defects that are instances of one shape: a verification surface
reporting on a *proxy* for the thing that matters. **One phase = one todo = one captured issue.**
The todos in `.planning/todos/pending/` are deliberately compartmentalized, and that compartmentation
is the phase structure — a phase whose contents need a sentence explaining why they belong together
is a bucket, not a phase.

Two exceptions, both shipping constraints rather than tidiness: the **graphify chain** (`4.4` → `4.3`
→ `4.3b`) shares one `ExpandResult` type and cannot be split across phases without splitting a type
change from its consumers; the **`quick.md` pair** (escape-description, reconcile-hash-column) touches
`src/markdown-table.cts` at adjacent lines and its preferred fix routes both through the same single
writer.

Ordering is justified by dependency, not severity — several blockers land late because they are
gated, and several minors land early because they unblock others.

**Hard gate on everything empirical (Phase 1):** `gsd-core/bin/lib/state.cjs` currently carries an
`advance-plan` workstream guard that `src/state.cts` does not have — gitignored build output from an
unmerged WIP branch, rebuilt only when absent. Any before/after measurement taken before
`npm run build:lib` measures a phantom. Phase 1 has no todo behind it **by design**: it is one
command, discovered by research (ADJ-3), and it is a phase only because every empirical phase depends
on it.

**A phase is not a PR.** A phase is a unit of context and sequencing; a PR is a unit of review. Most
phases here emit exactly one PR because one todo is one concern; where a phase spans two concerns its
`**PR shape**` line says so.

**Two todos are deliberately unmapped and get no phase:**
`build-a-handoff-skill-that-merges-rather-than-regenerates` (SEED-001 — an enhancement, deferred as
`TOOL-F02`) and `port-4-5-graphify-exclude-file-types-flag` (corpus membership vs retrieval
eligibility; no v1.12 requirement covers it). Do not stretch a phase goal to absorb either.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: The runtime build matches committed source** - `bin/lib/` stops carrying a guard `src/` does not have, so every later measurement is honest
- [ ] **Phase 2: A bounded subprocess leaves no survivor** - The `node --test` bound reaches the whole process tree, asserted on the survivor side
- [ ] **Phase 3: Local-only skills and agent survive `make install`** - The three rescued artifacts live in the repo, and the install pre-flight names what it found
- [ ] **Phase 4: Shell fences run under the login shell** - The cross-shell harness lands RED, the 11 sites turn it green, and a CST ratchet keeps them green
- [ ] **Phase 5: The workstream fail-safe refuses rather than misroutes** - One shared predicate, three guard sites, and a broken pointer that stays diagnosable
- [ ] **Phase 6: Body-only STATE.md writes leave `progress` alone** - An appended decision stops overwriting good counters with a stale disk scan
- [ ] **Phase 7: Workflow files route through resolved workstream paths** - 27 sites across 8 workflows write where the workstream resolves, and their readers agree
- [ ] **Phase 8: `pause-work`'s phase glob and dead gate** - The handoff lands in the phase directory, the understanding gate goes live, and the handoff is cleaned up
- [ ] **Phase 9: The quick-tasks table has one writer** - A pipe in a description stops producing a ragged row, and the `#` column has one contract
- [ ] **Phase 10: Port 4.10 — the planner reads MEMORY-RECALL.md** - The declared `plan:pre` producer finally has a consumer
- [ ] **Phase 11: The graphify chain — hop distance, seed scoring, and the restored floor** - `4.4` → `4.3` → `4.3b` over one shared type, with CI that fails on the invariant's deletion
- [ ] **Phase 12: Port 4.7 — review-lane timeouts land where they take effect** - The descriptor, its outer wrapper, and the literal-asserting tests move together
- [ ] **Phase 13: Port 4.8 — convergence max-cycles and concurrent routing** - The one authoritative site, its honest test, and a routing target that exists
- [ ] **Phase 14: Port 4.2 — `resolve-library-id` matches the live tool schema** - Three call sites carry the arguments the current API requires
- [ ] **Phase 15: Port 4.6 — the statusline reports against the real context window** - The percentage is measured against the model's actual window
- [ ] **Phase 16: `audit-open` reports the true todo count** - The count is taken before the display cap, not after
- [ ] **Phase 17: The context monitor attributes usage to the subagent that asked** - A subagent stops being warned with its parent's numbers
- [ ] **Phase 18: The glab forge port is live on 1.11.0** - `$FORGE` reaches its guards, and the port lives as tracked source rather than a patch file

## Phase Details

### Phase 1: The runtime build matches committed source
**Goal**: A before/after measurement anywhere in this tree reads the code that is actually committed
**Depends on**: Nothing (first phase)
**Requirements**: INST-01
**Success Criteria** (what must be TRUE):
  1. In a tree with a dangling active-workstream pointer, `node gsd-core/bin/gsd-tools.cjs query state advance-plan` behaves exactly as `src/state.cts` at HEAD implements — the phantom `advance-plan` guard that exists only in `gsd-core/bin/lib/state.cjs` is gone.
  2. A rebuild into a clean directory produces `gsd-core/bin/lib/*.cjs` byte-identical to what is then on disk, so no later phase's repro or fix-verification measures build output the source disagrees with.
**Plans**: TBD
**PR shape**: Not a PR at all — `gsd-core/bin/lib/` is gitignored build output. Nothing here is contributed.
**Note**: **This phase has no todo behind it, by design.** It is one command (`npm run build:lib`, or deleting `gsd-core/bin/lib/`) discovered by research (ADJ-3), and it is a phase only because it is the hard gate on every empirical phase in this milestone. Do not fabricate a todo for it. The stale guard came from compiling the unmerged WIP branch `local/state-advance-plan-fallback-fix` (`f72f1534`); `gsd-core/bin/ensure-runtime-build.cjs` rebuilds only when the output is *absent*, which is why it survived.

### Phase 2: A bounded subprocess leaves no survivor
**Goal**: When a `node --test` check hits its bound, nothing it started is still running
**Depends on**: Phase 1 (build-before-measure; the leak is observed against built output)
**Requirements**: INST-04, INST-05
**Success Criteria** (what must be TRUE):
  1. After a `node --test` check hits its bound, no descendant of the runner survives — asserted on the **survivor** side (`pgrep` / `lsof` finds nothing holding the temp directory), not merely that the parent returned a verdict.
  2. Cleanup is ordered *after* the survivor check, so `t.after` cannot delete the evidence the assertion needs (today the orphan holds the deleted temp dir as its `cwd` and only `lsof -p <pid>` reveals it).
  3. Reverting `--test-isolation=none` in `buildNodeTestArgs` (`src/prohibition-enforcement.cts:220-222`) turns that assertion RED — the assertion is the deliverable, not the flag.
  4. With isolation `none` the subject is imported into the runner process; the `GSD_PROHIB_SUBJECT` convention (#1279) and `childEnv()`'s `NODE_TEST_CONTEXT` / `NODE_OPTIONS` stripping still behave, verified rather than assumed — the change moves the wall that stripping guards.
**Plans**: TBD
**PR shape**: One concern — the isolation flag plus its survivor assertion, which must not be split (shipped flag-first, it regresses silently at the next refactor of `buildNodeTestArgs`).
**Note**: Sequenced before Phase 4 because the fence harness is about to double the number of spawned shells crossing this seam. `detached` is **not** a documented option for `spawnSync` / `execFileSync` and `options.signal` is async-only — at a synchronous call site the only two cures are *remove the tree* or *convert to async*; this takes the first. Measured 2026-08-22: two orphans at ~90% of a core each for 34 hours, killed instantly by a plain `SIGTERM` (the signal was never delivered, not ignored).

### Phase 3: Local-only skills and agent survive `make install`
**Goal**: Work authored in this fork is still there after the installer runs
**Depends on**: Nothing
**Requirements**: INSTALL-01, INSTALL-02
**Success Criteria** (what must be TRUE):
  1. `make install` run over a config dir containing `skills/gsd-review-concurrent/`, `skills/gsd-graph/` and `agents/gsd-prd-reviewer.md` leaves all three present afterward.
  2. The three artifacts exist in this repo as tracked source, so the installer's wipe-then-replace-from-source behaviour is *correct* rather than something to skip around — `bin/install.js` is not patched to skip unknown `gsd-*` directories, which would strand genuinely stale artifacts forever.
  3. The install pre-flight prints each user-authored file it found **by path** rather than a bare count, and tolerates a `manifest_version` older than the tracked release (the live install reads 1.10.0 against a repo tracking 1.11.0).
**Plans**: TBD
**PR shape**: One concern — the three files into the repo plus the `make install` pre-flight wired to `detect-custom-files`.
**Note**: The machinery already exists and is simply unreachable from `make install` — `gsd-file-manifest.json`, per-entry checksums + `saveLocalPatches`, and `detect-custom-files` / `restore-custom-files` with never-clobber semantics. Executed read-only against the live tree, `detect-custom-files --config-dir "$HOME/.claude"` returned 7 entries and named all three lost artifacts by path; most of the 7 are benign, which is why it must name them rather than refuse on a count. Do **not** add them to `USER_OWNED_ARTIFACTS` — that allowlist is scoped inside `gsd-core/`, not to sibling `skills/` / `agents/`. Phase 13's routing half is blocked on this landing.

### Phase 4: Shell fences run under the login shell
**Goal**: A shipped fence behaves under the login shell exactly as it does under bash, and an unsafe idiom cannot re-enter the corpus
**Depends on**: Phase 2 (the harness doubles the spawned-shell load across the seam Phase 2 repairs) and Phase 1
**Requirements**: INST-02, INST-03, SHELL-01, SHELL-02, SHELL-03, SHELL-04
**Success Criteria** (what must be TRUE):
  1. The fence-extraction harness executes each extracted fence once per shell over `{/bin/bash 3.2.57, /bin/zsh 5.9}` using **absolute** interpreter paths, and each test case name carries its shell, so a failure names which shell failed rather than which file.
  2. Run against the unfixed sites, `node --test tests/unreachable-shell-guard.test.cjs` exits non-zero on the zsh rows while the bash-only rows stay green — and `grep` over the harness finds no skip list, `skip`, `todo`, or expected-failure marker covering any fence site. That RED reading is the first plan's deliverable; the phase closes with the same harness green (INST-03).
  3. For each fixed glob-guard fence, running it under `/bin/zsh` 5.9 with a glob matching **zero** files completes with exit 0 and takes the empty branch (no `no matches found` abort), and with a glob matching **N > 0** files processes all N — and in both directions the fence's captured stdout is identical to the same fence run under `/bin/bash` 3.2.57. Reverting any single site fix turns the harness RED again.
  4. The two sites that are a different mechanism are fixed by their own mechanism, not by the glob idiom: `gsd-core/workflows/audit-fix.md:145`'s `AUDIT_TEST_EXIT=${PIPESTATUS[0]}` stops swallowing a test exit code, and `agents/gsd-verifier.md:85-86` moves to the existing `verification resolve-file` verb — with `wc -c agents/gsd-verifier.md` under 49,152 afterward (it is 49,150 today against a 49,152 cap, and the verb swap is the only known net-negative option).
  5. `scripts/lint-portable-glob-guard.cjs` reports zero violations over the shell-tagged fence corpus at a zero baseline with no allowlist escape, and reports a violation when any of the seven idioms is reintroduced into **one** fence of a multi-fence file — proving it operates per-fence, not per-file (`complete-milestone.md` has a shim at `:331` and an unprotected glob-array at `:369` in a *different* fence). Each of the seven rules is demonstrated matching its CST shape against the real corpus rather than a synthetic fixture, on `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1` loaded from the `.wasm` **by path** (never `require('tree-sitter-bash')`), with the ~19 pseudo-code fences as an enumerated exclusion list.
  6. The CI fence lane runs on `pull_request` — **no** `full_only: true` — as a narrow macOS-gated `shell-fences` job passing absolute interpreter paths.
**Plans**: TBD
**PR shape**: **PR-1** — the cross-shell harness plus the 11 site fixes together, green on arrival upstream (this is what discharges INST-03 in full: RED on `local/*`, green upstream, one PR). **PR-2** — the ratchet lint, with an ADR amending ADR-3409's premise (measured at 0.6% of fences, not a blocker).
**Note**: Flag for `--research-phase` — the tree-sitter rules are confirmed *expressible* but have never been run against the corpus; a spike closes that before the lint is wired into `lint:ci`. The same phase must settle process-substitution vs pipe before any `sh` lane is added: the two forms are mutually exclusive and `.planning/reference/shell-fence-portability.md` currently asserts both. `sh-syntax` is rejected for its positional-only JSON AST — **not** for lacking zsh, which it has. Update the reference doc in the same commit as the fixes. **Baseline caveat for the M7 rule (`grep -oP`):** its five shipped sites are `pause-work.md:18,21,24` (fixed in Phase 8) and `sync-skills.md:33,40` (**in no todo**) — so either wire that rule after Phase 8 and capture the `sync-skills.md` pair, or the lint cannot start at a zero baseline. Open process question for the maintainers, not a technical one: will a knowingly-RED harness PR be accepted? If not, the fallback is exactly PR-1 as written. Also confirm zsh is present on `ubuntu-latest`, or coverage rests on the three macOS shards alone.

### Phase 5: The workstream fail-safe refuses rather than misroutes
**Goal**: A state-mutating verb in workstream mode either writes the workstream's file or refuses — never the root file — and a broken pointer stays diagnosable from the CLI
**Depends on**: Phase 1 (a repro taken against stale `bin/lib/` is a phantom — this is the exact verb whose build output lies)
**Requirements**: WS-01, WS-02, WS-03, WS-04, WS-05, WS-06, WS-07, WS-08
**Success Criteria** (what must be TRUE):
  1. Given an active-workstream pointer naming `ws-a` and `.planning/workstreams/` removed entirely (T1), `gsd-tools state advance-plan` exits non-zero and root `.planning/STATE.md` has the same `shasum` before and after the call; the identical setup and assertion holds for `init progress` and `phase complete`, all three refusing through one predicate exported from `src/planning-workspace.cts`.
  2. The same three verbs refuse with the same `ERROR_REASON` code when `.planning/workstreams/` survives holding only a `.DS_Store` (T2) — proven by running one shared assertion body against both fixtures, not two hand-written tests.
  3. The refusal's stdout is JSON carrying `diagnoseUnresolvedActiveWorkstream`'s exact `{ present, value, reason }` shape, naming which marker failed, so a calling agent branches on the field without parsing prose; on `--raw` the same information also reaches stderr.
  4. A pointer-resolved authoritative read still exits 0 in both T1 and T2 and reports the non-resolution as a field; `gsd-tools workstream get` run twice in succession reports the same dangling pointer both times, keeping "never set" and "set but broken" distinguishable after the first look.
  5. `workstream complete` on a `.DS_Store`-blocked tree reports `reverted_to_flat: false` — matching the directory that demonstrably still exists — and clears the adapter it actually resolved from; meanwhile a flat project with no `.planning/workstreams/` and no pointer sees **no** new refusal from any of the three guarded verbs, asserted as a characterization test pinned *before* the predicate changes.
**Plans**: TBD
**PR shape**: **PR-A** — the corrected predicate in `planning-workspace.cts` plus **all three** guard sites (`init.cts:2926`, `phase.cts:2212`, `state advance-plan`) as ONE concern, matching upstream `51dfa683` (#2028) and superseding WIP `f72f1534`. **PR-B (read surface)** — `output()`'s conditional non-resolution field plus `workstream get` → `peekActiveWorkstream` (WS-05, WS-06). **PR-C** — `workstream complete` honesty (WS-07), a separate concern per `CONTRIBUTING.md:195`.
**Note**: The predicate is `listAvailableWorkstreams(cwd).length > 0 || diagnoseUnresolvedActiveWorkstream(cwd).present` — a monotone disjunction. Do **not** scope it around `fs.existsSync('.planning/workstreams')`, which reads false in exactly the T1 case that produces the bug. Do **not** hoist the guard into `dispatchHostCommand`: that kills the Class C diagnostics at the moment they are needed. Scope for v1.12 is the three guard sites only; the Class A tail is `WS-F01`. One unmeasured cell to verify in the call-site matrix: `diagnoseUnresolvedActiveWorkstream(cwd).present` in the post-`.DS_Store` state. The working tree on `local/state-advance-plan-fallback-fix` carries the superseded WIP diff in `src/state.cts` and `tests/state.test.cjs` — reconcile, do not merge.

### Phase 6: Body-only STATE.md writes leave `progress` alone
**Goal**: A body-only write to STATE.md changes only the body — good counters are never overwritten by a stale disk scan
**Depends on**: Phase 5 (`state.cts:657` (the guard) and `:679` (the resync argument) are the same function; and the silent `advance-plan` call that mutated the wrong STATE.md *also* rewrote its `progress` block, so fixing the write path first would mean correctly resyncing the wrong file)
**Requirements**: STATE-01
**Success Criteria** (what must be TRUE):
  1. Appending a decision or blocker to a STATE.md whose frontmatter reads `total_plans: 12, completed_plans: 7`, in a tree where a disk scan would compute different numbers, leaves the `progress` block byte-identical afterward.
  2. That holds at each of the six body-only write sites (`state.cts:868, 1086, 1154, 1259, 1344` and `gsd-tools.cjs:1172`) — one fixture per site, asserted on the frontmatter block rather than on the whole file, so a body change cannot mask a frontmatter regression.
  3. For each of the three `{ divergedFields }` sites (`state.cts:679, 1599, 4962`), running the verb against a fixture whose frontmatter and disk scan disagree produces the resync behaviour the phase specifies for that site, and reverting that site's argument flips the observed frontmatter — so the behaviour is pinned per site rather than assumed uniform.
**Plans**: TBD
**PR shape**: One concern — the resync argument on the body-only appenders. The `{ divergedFields }` decision is a second concern if it changes behaviour at any of the three sites.
**Note**: Flag for `--research-phase`. The `{ divergedFields }` three-site question is a genuine open design question, not a mechanical fix, and needs its own discussion before the change is written. `cmdStatePlannedPhase` (`state.cts:4044-4048`) is the correct in-file precedent; `gsd-tools.cjs:1166-1167` justifies itself by citing two exemplars that both carry the defect.

### Phase 7: Workflow files route through resolved workstream paths
**Goal**: In workstream mode a workflow writes its planning file where the workstream resolves, and whatever reads that file resolves the same way
**Depends on**: Phase 5 (the sweep consumes resolved paths whose correctness Phase 5 establishes) and Phase 4 (several of these sites are fence edits and must land on a tree the harness can see)
**Requirements**: ROUTE-01, ROUTE-03
**Success Criteria** (what must be TRUE):
  1. With a workstream resolving, exercising the file-writing step of each of the 8 affected workflows creates the file under `.planning/workstreams/<ws>/`, and a before/after listing of root `.planning/` shows **no** new file there — run across all 27 sites, not a sample.
  2. A write-then-read round trip in workstream mode agrees on scope — `state signal-waiting` writes `WAITING.json` to the path `init progress` reads, verified by the reader finding the signal the writer just wrote.
  3. No swept site is left with a writer resolving through `planningDir` and a reader hardcoding `path.join(cwd, '.planning', …)`; every remaining root-hardcoded read in the swept files is one that is *supposed* to be root-scoped, named as such.
**Plans**: TBD
**PR shape**: One concern — the routing sweep. Large but mechanical: 27 sites, 8 files.
**Note**: The Class D hardcoded-root sites bypass the resolver entirely and a guard cannot reach them — **D-2** (`state.signal-waiting` writes `planningDir(cwd)/WAITING.json` at `state.cts:3793` while `init.progress` reads `path.join(cwd, '.planning', 'WAITING.json')` at `init.cts:2526`) is a `src/` fix that appears in **no todo's file list**, and research classes D-1/D-2 as v1.12.x differentiators. Criterion 2 asserts the round trip anyway, so scope D-2's code half deliberately at plan time rather than discovering it mid-phase; if it is dropped, drop it explicitly and re-file. Shared-file collisions this phase creates downstream: `pause-work.md:67` (Phase 8), `quick.md:150,469` (Phase 9), `ship.md:510,513` (Phase 18) — all sequenced after this phase, never parallelised with it.

### Phase 8: `pause-work`'s phase glob and dead gate
**Goal**: A paused session's handoff lands where the resuming session looks for it, the understanding gate actually gates, and the handoff does not outlive the resume
**Depends on**: Phase 7 (`pause-work.md:67` is a routing-sweep site) and Phase 4 (the reference glob idiom this file is missing)
**Requirements**: ROUTE-02
**Success Criteria** (what must be TRUE):
  1. Against a fixture holding real `NN-slug/` phase directories containing `NN-PLAN.md`, `pause-work`'s phase detector returns the phase — the bare `*/PLAN.md` glob that matches nothing (18 other sites in `gsd-core/` use `*-PLAN.md`) no longer degrades detection to the `Default` branch, and the handoff is written to the phase directory rather than the planning root.
  2. The gate is live: changing the condition at `execute-phase.md:220` / `discuss-phase.md:165` changes observed behaviour, where today both check only the phase dir, always take the "doesn't exist → proceed" branch, and blocking constraints recorded at `:52` reach nothing that reads them.
  3. The handoff is deleted after resume, so the correctly-placed file cannot leave the three-question understanding ritual permanently stuck on — the inversion the todo warns about is asserted, not assumed, and both halves land in the same change.
  4. The three `grep -oP` detectors at `:18,21,24` produce the same captured values under BSD grep as under GNU grep — they are not silently empty on a runtime that bypasses the Claude Code `ugrep` shim.
**Plans**: TBD
**PR shape**: One concern — the todo's own warning is that the five coupled sub-fixes must ship together; a one-line glob fix alone inverts the defect rather than repairing it. The six secondary findings (`uncommitted_files` hardcoded `[]`, the unconditional "Committed as WIP" against `cmdCommit`'s `skipped:true`, zero state reads, the single hardcoded `HANDOFF.json` slot, blocking-constraint severity with no schema field) are separate concerns — triage them at plan time and re-file what does not ship here.
**Note**: `pause-work.md` has zero occurrences in `gsd-local-patches-1.10.0.diff` — this is pristine upstream behaviour, not local drift. The `#2962` nullglob shim present at `resume-project.md:67-68` never reached this file.

### Phase 9: The quick-tasks table has one writer
**Goal**: A quick task with any description writes a row that the table's own parser reads back unchanged
**Depends on**: Phase 7 (`quick.md:150,469` are routing-sweep sites in the same file)
**Requirements**: REPORT-03
**Success Criteria** (what must be TRUE):
  1. A quick task whose description contains a literal `|` (reproduction input: `Path | None`) produces a row with exactly the table's column count, and a subsequent `gsd_run quick-tasks-append` exits 0 — where the 2026-08-05 downstream failure produced a 7-cell row in a 6-column table, sat latent for two days, and then failed every later append with `row 22 has 7 cells, expected 6`, exit 1.
  2. The `#` column has exactly one writer with one contract: the hand-rolled row templates at `quick.md:619` and `:624` no longer interpolate `${quick_id}` into the column that `src/markdown-table.cts:762` computes as an ordinal.
  3. Applying an escaped description and then a `#` renumber, **in sequence**, yields a table that `src/markdown-table.cts` re-parses into the same rows it was given.
**Plans**: TBD
**PR shape**: Three plans in one phase, strictly sequenced — never parallelised, they touch `src/markdown-table.cts` at adjacent lines. **Plan 1** ships `escape-description`'s **option 1** (the standalone step-7c escaping instruction: escape `\` first, then `|`, mirroring `escapeCell`'s deliberate order at `src/markdown-table.cts:704-705`), which discharges the blocker on its own and does not wait on anyone. **Plan 2** is `reconcile-hash-column` — the `id` field on `QuickTaskFields` plus the fallback branch — gated on a maintainer answering its three open design questions. **Plan 3** is `escape-description`'s **option 2**, routing step 7c through `appendQuickTaskRow`, which supersedes plan 1 and is what actually satisfies criterion 2. One PR per plan, or plans 2–3 as one PR; never two concurrent PRs.
**Note**: The option choice is the maintainer's, not this roadmap's — the todo says *"a maintainer should pick between (1) and (2)"* and *"these two should be resolved together, option 2 second"*. The plan split above exists so a **blocker** (a ragged row permanently breaks every later programmatic append) is not held behind `reconcile-hash-column`'s three unanswered design questions. Option 2 is not a drop-in today: `QuickTaskFields` has no `id` field, so routing 7c through the helper right now silently replaces quick-ids with row ordinals. If the maintainer takes option 2 only, drop plan 1 and the phase is two plans in the order 2 → 3. **Coverage note for the operator:** `REPORT-03` ("the `#` column has one writer with one contract") is the only requirement covering this phase, and it reaches the escaping blocker only through option 2's single writer — the escaping blocker has no requirement text of its own. Add a `REPORT-04` if you want it named independently; this roadmap did not invent one.

### Phase 10: Port 4.10 — the planner reads MEMORY-RECALL.md
**Goal**: The `plan:pre` step that writes `MEMORY-RECALL.md` finally has a consumer
**Depends on**: Phase 4 (the sibling content-read lines this one imitates are rewritten there; porting the stale 1.10.0 hunk onto the 1.11.0 fence would reintroduce the defect Phase 4 just fixed)
**Requirements**: PORT-08
**Success Criteria** (what must be TRUE):
  1. With `mempalace.enabled: true` and a `MEMORY-RECALL.md` present in the phase directory, the planner's context fence emits its contents alongside `*-CONTEXT.md`, `*-RESEARCH.md` and `*-DISCOVERY.md`.
  2. The added line uses the same array-guard idiom as its three siblings **as Phase 4 leaves them**, not the stale 1.10.0 `cat "$phase_dir"/*-CONTEXT.md 2>/dev/null` hunk the original patch imitates — upstream rewrote the whole fence between 1.10.0 and 1.11.0, so the patch hunk must be re-authored before porting.
  3. With `mempalace.enabled` at its default `false` the step never fires and the glob matches nothing — and under `/bin/zsh` 5.9 that zero-match path completes with exit 0 rather than aborting the fence.
**Plans**: TBD
**PR shape**: One concern — a single line in `agents/gsd-planner.md`, re-authored against 1.11.0.
**Note**: The strongest-founded item in the port campaign — the producer is formally declared at `capabilities/mempalace/capability.json:96-109`, the skill's own step 4 says *"The planner consumes it"*, and three real artifacts written 2026-08-18/19 exist on disk. `$phase_dir` is not the `$FORGE` defect class: it is bound by prose at `gsd-planner.md:614` and three pre-existing sibling lines already rely on the identical cross-fence binding.

### Phase 11: The graphify chain — hop distance, seed scoring, and the restored floor
**Goal**: graphify's budget reduction never drops below the seed floor, and CI fails when that invariant is *deleted* — not merely when it is violated
**Depends on**: Nothing
**Requirements**: PORT-01, PORT-04
**Success Criteria** (what must be TRUE):
  1. graphify's budget-cliff uses per-edge hop distance and its seeds are scored by match quality, landing as `port-4-4` → `port-4-3` → `port-4-3b` in that order over the shared `ExpandResult` type (which `4.4` extends and `4.3` consumes) — no reordering, and `4.4`/`4.3` are inert on their own until `4.3b` lands.
  2. Deleting the seed-floor assertion lines from `tests/graphify-query.test.cjs` (`:560`, `:587`) on a scratch branch makes CI fail — demonstrated by actually removing them and observing the espree invariant-title lock name the missing title. `scripts/lint-removed-but-needed.cjs` does **not** cover this: it keys on deleted *files*.
  3. `arbGraph` reliably produces ≥2 differentiated-quality seeds — where at the pinned `numRuns: 200, seed: 42` it produced them in **0 of 200 runs** — and the counterexample RED test from `.planning/runbooks/porting-local-patches-assets/graphify/4.3b-seedfloor-counterexample.cjs` is in the suite and fails against the unfixed `applyBudget`.
  4. A PR touching only `tests/graphify-query.test.cjs` starts the mutation workflow — `mutation.yml`'s `on.paths` allow-list and `scripts/mutation-matrix.cjs`'s `COVERED` change in **one** commit — and the recorded floor comes from a CI measurement, not a local run that counts timeouts as kills (measured divergence: `prompt-budget` 99.6% local vs 68.3% CI).
**Plans**: TBD
**PR shape**: One PR, three plans in fixed order (`4.4` → `4.3` → `4.3b`) — they share one type and `4.3b` is the sole behaviour-changing commit of the block. This is one of the two sanctioned merges in this roadmap: splitting the type change from its consumers ships a half-applied type change.
**Note**: Flag for `--research-phase` — the mutation floor must be set from a CI measurement, so the phase needs a measurement step planned, not a number assumed. A mutation score is a threshold, not an identity lock (floors sit at "measured minus 1–2 points", so deleting one assertion can drop the score by less than the margin and still pass) — which is the durable reason the espree lock stays. `scripts/lib/allowlist-ratchet.cjs` already implements the wanted semantics; do not hand-roll a third. `port-4-5` (`--exclude-file-types`) is deliberately **not** in this chain: corpus membership vs retrieval eligibility is a different concern and no v1.12 requirement covers it.

### Phase 12: Port 4.7 — review-lane timeouts land where they take effect
**Goal**: A review lane that needs a longer bound gets one, at every layer that can kill it
**Depends on**: Phase 4 (`gsd-core/workflows/review.md` carries fence fixes there, and this phase edits the same file — the fence fix is the reference implementation and lands first)
**Requirements**: PORT-06
**Success Criteria** (what must be TRUE):
  1. A review lane observed to time out does so at its configured bound rather than the default — the change lands at `src/review-lane-descriptor.cts:422-434`, the only file with runtime effect, reaching `resolveLanePlan` → `cp.spawnSync(..., { timeout })`.
  2. `capabilities/antigravity/capability.json:121` is not claimed as the fix: `antigravity` is already a first-party lane, `mergeReviewerLanes` does `if (bySlug.has(slug)) continue;`, and mutating the registry entry provably leaves the merged object `===` the untouched first-party one. If it is touched at all, it is for validator consistency, stated as such.
  3. `gsd-core/workflows/review.md:295-300` — the third, undocumented timeout layer — is raised in the same change, so the outer Bash-tool wrapper still exceeds the new inner bound; landing one without the other produces a silent SIGKILL surfacing as an unexplained empty stub.
  4. The four literal-asserting tests (`antigravity-reviewer.test.cjs:126-152`, `review-lane-invocation.test.cjs:88`, `review-lane-descriptor.test.cjs:775,954`) are updated in the same commit, so no test passes by matching a stale literal.
**Plans**: TBD
**PR shape**: One concern — the descriptor value, its required companion prose edit, and the four tests.
**Note**: The port as originally specified changes nothing; do not execute it as written. Nothing enforces outer > inner — no validator or test compares the `--print-timeout` string against `timeoutFloorMs`. Justification for the raise is still **none** on record beyond the dated runbook entry; the todo itself says consider deferring entirely, so the plan's opening must state carried-vs-contributed and, if contributed, the failure story.

### Phase 13: Port 4.8 — convergence max-cycles and concurrent routing
**Goal**: The convergence loop's bound is the value it claims, and its review step routes to a skill that exists
**Depends on**: Phase 3 (`skills/gsd-review-concurrent/SKILL.md` is not in this repo at all and `make install` destroys it — the routing half is blocked until it is tracked source)
**Requirements**: PORT-07
**Success Criteria** (what must be TRUE):
  1. `gsd-core/workflows/plan-review-convergence.md:31` — the one runtime-authoritative site — defaults `MAX_CYCLES` to 5, and the `commands/gsd/` twin, the SKILL.md and the `docs/` mentions agree rather than diverging.
  2. `tests/plan-review-convergence.test.cjs:517-520` asserts the value its own message names, rather than staying green because `'3'` still matches `#2315` and `## 3. Validate Phase` elsewhere in the file.
  3. The review step routes to `gsd-review-concurrent`, **and** the file's own success-criteria checklist at `:453,462` says the same — the routing test no longer passes through an OR-fallback that matches the stale checklist.
  4. The routing target exists as tracked source before the routing lands, so `Skill()` can neither hard-error on an unknown name (`docs/ARCHITECTURE.md:125`, from #924) nor let the review subagent improvise a fallback that still emits a well-formed `CYCLE_SUMMARY` — the silent branch that could not be ruled out.
**Plans**: TBD
**PR shape**: Two commits, no line overlap: the `max-cycles` bump with its test, then the routing change with its checklist fix. Both in one PR — the file is self-contradicting until the checklist follows the prompt.
**Note**: 3→5 is **not** "bounded like today": `MAX_CYCLES` is the only hard bound — stall detection at §5c prints a warning and falls through with no early exit, and there is no token or wall-clock budget. Say so in the plan rather than treating the bump as cosmetic. `gsd-review-concurrent` is genuinely parallel-safe (every write keyed on slug; the one shared path written once before the readers), and it already uses the array form of `wait "${PIDS[@]}"` whose scalar form no-ops the barrier.

### Phase 14: Port 4.2 — `resolve-library-id` matches the live tool schema
**Goal**: A documentation lookup reaches the tool instead of failing on its call signature
**Depends on**: Nothing
**Requirements**: PORT-02
**Success Criteria** (what must be TRUE):
  1. Every `resolve-library-id` call signature in the shipped instructions carries the arguments the current API requires (`query` as well as `libraryName`) — at `agents/gsd-advisor-researcher.md`, `agents/gsd-executor.md`, and `gsd-core/references/research-documentation-lookup.md`.
  2. The change is doc-only across those three files with no runtime edit, and splits cleanly into two commits (call signatures; fallback conditions and the `mcp__plugin_context7_context7__*` judgement call).
**Plans**: TBD
**PR shape**: One concern, two commits. No changeset implications beyond the `agents/` touch.
**Note**: Already validated against the live tool schema — no spike needed.

### Phase 15: Port 4.6 — the statusline reports against the real context window
**Goal**: The percentage the statusline shows is measured against the window the model actually has
**Depends on**: Nothing
**Requirements**: PORT-03
**Success Criteria** (what must be TRUE):
  1. Given a model whose context window differs from the previously hardcoded value, `hooks/gsd-statusline.js` reports usage as a fraction of the model's real window.
  2. The 3 of 6 assertions at `tests/gsd-statusline.test.cjs:664-692` that break under the new behaviour are rewritten in the same commit, so the suite asserts the new contract rather than being made green by deletion.
**Plans**: TBD
**PR shape**: One concern — `hooks/gsd-statusline.js` is tracked source with no `.cts` → `.cjs` translation, so the source change and the test rewrite are one commit.
**Note**: Interacts with Phase 17 only by file family, not by line — `gsd-statusline.js:608-620` writes the bridge file Phase 17's monitor reads. If both land close together, sequence them; they are not the same concern.

### Phase 16: `audit-open` reports the true todo count
**Goal**: A count that is capped for display is not also capped in the number reported
**Depends on**: Nothing
**Requirements**: REPORT-01
**Success Criteria** (what must be TRUE):
  1. `audit-open` against a fixture holding more open todos than the display cap reports the true total in `counts.todos`, while still listing at most 5 items.
  2. The count is taken **before** slicing, mirroring `scanContextQuestions` — the correct pattern already in the same file — so the fix does not rest on `countReal` reasoning about the `_remainder_count` sentinel row after the fact.
**Plans**: TBD
**PR shape**: One concern — one function in `src/audit.cts`, small diff.
**Note**: The human renderer at `src/audit.cts:1402-1413` already handles the cap correctly; only the machine-readable count is wrong, which is why an operator reading the terminal never sees it.

### Phase 17: The context monitor attributes usage to the subagent that asked
**Goal**: A subagent is warned about its own context, or not warned at all — never about its parent's
**Depends on**: Nothing
**Requirements**: REPORT-02
**Success Criteria** (what must be TRUE):
  1. A hook payload carrying an `agent_id` no longer has the parent-keyed bridge file (`/tmp/claude-ctx-{session_id}.json`) applied to it — `session_id` is shared between a session and every subagent it spawns, and `agent_id` is the only field that distinguishes them.
  2. A top-level session's own events (no `agent_id`) still receive the WARNING / CRITICAL injection at the 35% / 25%-remaining thresholds, so the guard clause narrows the monitor rather than disabling it.
  3. A fresh, low-usage subagent — including one of several concurrent forks — receives no "context almost full" injection while the parent is near its limit.
**Plans**: TBD
**PR shape**: One concern — a single guard clause in `hooks/gsd-context-monitor.js`, already implemented and verified in the live install; porting it here is the same minimal diff.
**Note**: The bridge file structurally can only ever reflect the parent, since only one `statusLine` is ever rendered. `subagentStatusLine` is absent/unset in this install, so there is no second writer to key on.

### Phase 18: The glab forge port is live on 1.11.0
**Goal**: A GitLab-hosted project's ship path actually runs `glab`, and the port survives the next install
**Depends on**: Phase 7 (`ship.md:510,513` are routing-sweep sites; this is the largest `ship.md` change and goes last to minimise conflicts)
**Requirements**: PORT-05
**Success Criteria** (what must be TRUE):
  1. `$FORGE` reaches its guards — the inertness proof in `.planning/runbooks/porting-local-patches-assets/glab/fence-derive.sh` and `fence-create-pr.sh` no longer reproduces, and the `stubbin/gh` / `stubbin/glab` stubs show `glab` is the binary actually invoked on a GitLab remote.
  2. All 1.11.0 sites are covered, including `ship.md:497` which is **new at 1.11.0 and unported**, and the four byte-stable families (`inbox.md`'s nine sites, `pr-branch.md:301`, `references/checkpoints.md:414`, `ship.md:90`) are re-anchored at their 1.11.0 line numbers rather than 1.10.0's.
  3. The FORGE fail-open defect is closed by the fence-scoping redesign rather than by widening the guard — a fence that cannot see `$FORGE` fails closed instead of falling through to `gh`.
  4. The port lives as tracked source in this repo rather than as `~/.claude/scripts/gsd-local-patches-1.10.0.diff`, so `make install` cannot silently drop it.
**Plans**: TBD
**PR shape**: One concern — but the largest change in the milestone. The unverified GitLab field mapping needs an empirical spike before the diff is written; the ship-note `[ci skip]` trailer is patched-but-undocumented and its documentation goes in the same change.
**Note**: Flag for `--research-phase` — the field-mapping spike is a real unknown, not a mechanical port. This is the last phase deliberately: it is the biggest `ship.md` rewrite and Phase 7's routing sweep touches the same file.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18

Phases 11 and 14–17 have no dependencies and may be pulled forward at any point as filler.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. The runtime build matches committed source | 0/TBD | Not started | - |
| 2. A bounded subprocess leaves no survivor | 0/TBD | Not started | - |
| 3. Local-only skills and agent survive `make install` | 0/TBD | Not started | - |
| 4. Shell fences run under the login shell | 0/TBD | Not started | - |
| 5. The workstream fail-safe refuses rather than misroutes | 0/TBD | Not started | - |
| 6. Body-only STATE.md writes leave `progress` alone | 0/TBD | Not started | - |
| 7. Workflow files route through resolved workstream paths | 0/TBD | Not started | - |
| 8. `pause-work`'s phase glob and dead gate | 0/TBD | Not started | - |
| 9. The quick-tasks table has one writer | 0/TBD | Not started | - |
| 10. Port 4.10 — the planner reads MEMORY-RECALL.md | 0/TBD | Not started | - |
| 11. The graphify chain — hop distance, seed scoring, and the restored floor | 0/TBD | Not started | - |
| 12. Port 4.7 — review-lane timeouts land where they take effect | 0/TBD | Not started | - |
| 13. Port 4.8 — convergence max-cycles and concurrent routing | 0/TBD | Not started | - |
| 14. Port 4.2 — `resolve-library-id` matches the live tool schema | 0/TBD | Not started | - |
| 15. Port 4.6 — the statusline reports against the real context window | 0/TBD | Not started | - |
| 16. `audit-open` reports the true todo count | 0/TBD | Not started | - |
| 17. The context monitor attributes usage to the subagent that asked | 0/TBD | Not started | - |
| 18. The glab forge port is live on 1.11.0 | 0/TBD | Not started | - |

## Coverage

All 34 v1.12 requirements map to exactly one phase. No orphans, no duplicates. Every phase carries at
least one requirement.

| Phase | Todo | Requirements | Count |
|-------|------|--------------|-------|
| 1 | *(none — by design, see PIN-B)* | INST-01 | 1 |
| 2 | `node-test-timeout-leaks-an-orphaned-spinning-grandchild` | INST-04, INST-05 | 2 |
| 3 | `local-only-skills-and-agent-destroyed-by-make-install` | INSTALL-01, INSTALL-02 | 2 |
| 4 | `zsh-array-index-guards-silently-read-nothing` | INST-02, INST-03, SHELL-01, SHELL-02, SHELL-03, SHELL-04 | 6 |
| 5 | `state-advance-plan-silently-falls-back-to-root-state-md` | WS-01, WS-02, WS-03, WS-04, WS-05, WS-06, WS-07, WS-08 | 8 |
| 6 | `body-only-state-md-writes-resync-progress-frontmatter-from-disk` | STATE-01 | 1 |
| 7 | `route-workflow-files-through-resolved-workstream-paths` | ROUTE-01, ROUTE-03 | 2 |
| 8 | `fix-pause-work-s-broken-phase-glob-and-dead-gate` | ROUTE-02 | 1 |
| 9 | `escape-description-in-quick-md-7c-table-row` + `reconcile-hash-column-contract-in-markdown-table` | REPORT-03 | 1 |
| 10 | `port-4-10-mempalace-recall-line-in-the-planner` | PORT-08 | 1 |
| 11 | `port-4-4` + `port-4-3` + `port-4-3b` | PORT-01, PORT-04 | 2 |
| 12 | `port-4-7-review-lane-timeouts-540s-to-1800s` | PORT-06 | 1 |
| 13 | `port-4-8-convergence-max-cycles-and-concurrent-routing` | PORT-07 | 1 |
| 14 | `port-4-2-context7-resolve-library-id-requires-query` | PORT-02 | 1 |
| 15 | `port-4-6-statusline-report-against-real-context-window` | PORT-03 | 1 |
| 16 | `audit-open-counts-todos-reports-the-display-cap-not-the-count` | REPORT-01 | 1 |
| 17 | `context-monitor-misattributes-parent-session-usage-to-subagents` | REPORT-02 | 1 |
| 18 | `migrate-the-glab-forge-port-from-gsd-1-10-0-to-1-11-0` | PORT-05 | 1 |
| **Total** | **20 todos → 18 phases** | | **34** |

**Requirement changes made by this revision** (the split from 6 phases to 18 forced two, both
recorded in `REQUIREMENTS.md`):

- **`PORT-06` was compound** — *"Review-lane timeouts **and** convergence routing"* — written for a
  bucket phase. `port-4-7` and `port-4-8` are separate todos and now separate phases, so it is split:
  `PORT-06` keeps the timeouts, **`PORT-07`** (new) carries convergence routing.
- **`PORT-08`** (new) covers `port-4-10` (the planner's `MEMORY-RECALL.md` read), which is captured
  work that **no** v1.12 requirement covered — it was carried only inside the old Phase 4's note.

Nothing else was added. The `escape-description` blocker is delivered under `REPORT-03` because its
preferred fix routes the row through the same single writer; if you want it named independently, add
`REPORT-04` — this roadmap declined to invent it.

**Deliberately unmapped, no phase:** `build-a-handoff-skill-that-merges-rather-than-regenerates`
(→ `TOOL-F02`) and `port-4-5-graphify-exclude-file-types-flag`.

`WS-F01`, `WS-F02`, `TOOL-F01` and `TOOL-F02` are Future Requirements — deferred past v1.12 and
deliberately unmapped.
