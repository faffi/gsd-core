# Roadmap: gsd-core (faffi fork) — v1.12

## Overview

This milestone repairs 22 captured defects that are instances of one shape: a verification surface
reporting on a *proxy* for the thing that matters. The roadmap therefore front-loads **instruments**
— the runtime rebuild that stops the CLI disagreeing with `src/`, a fence harness that runs under the
shell production actually uses, a survivor assertion for the subprocess bound, and an installer
pre-flight so the work survives `make install`. Only once measurement can fail does repair begin: the
extracted workstream predicate and its three guard sites, then the STATE.md write path that shares a
function with one of them, then the fence sites and their ratchet lint, then the workflow routing
sweep that consumes the resolved paths, and finally the port-campaign remainder. Ordering is
justified by dependency, not severity — two blockers land late because they are gated, and two minor
items land early because they unblock others.

**Hard gate on everything empirical:** `gsd-core/bin/lib/state.cjs` currently carries an
`advance-plan` workstream guard that `src/state.cts` does not have — gitignored build output from an
unmerged WIP branch, rebuilt only when absent. Any before/after measurement taken before
`npm run build:lib` measures a phantom.

**A phase is not a PR.** A phase is a unit of context and sequencing; a PR is a unit of review. The
PR splits from `REQUIREMENTS.md`'s "PR boundaries" table are carried into each phase below so they
survive into planning.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Instruments before repairs** - Measurement that reads shipped code, runs under the real shells, and survives `make install`
- [ ] **Phase 2: Workstream resolution refuses rather than misroutes** - One shared predicate, three guard sites, and a broken pointer that stays diagnosable
- [ ] **Phase 3: STATE.md write integrity** - A body-only append stops resyncing `progress` frontmatter from a disk scan
- [ ] **Phase 4: Shell fences that run under the login shell** - The 11 fence sites fixed and the harness turned green, with a CST ratchet lint behind them
- [ ] **Phase 5: Workflow files routed through resolved workstream paths** - Writers and readers agree on scope; `pause-work`'s glob and gate go live
- [ ] **Phase 6: Port campaign remainder and reporting correctness** - Concerns 4.2–4.10 closed, with CI that can see the seed-floor invariant's deletion

## Phase Details

### Phase 1: Instruments before repairs
**Goal**: Every later measurement in this milestone reads the code that actually ships, runs under the shells that actually run it, and is not destroyed by `make install`
**Depends on**: Nothing (first phase)
**Requirements**: INST-01, INST-02, INST-04, INST-05, INSTALL-01, INSTALL-02
**Success Criteria** (what must be TRUE):
  1. In a tree with a dangling active-workstream pointer, `node gsd-core/bin/gsd-tools.cjs query state advance-plan` behaves exactly as `src/state.cts` at HEAD implements — the phantom `advance-plan` guard that exists only in `gsd-core/bin/lib/state.cjs` is gone, and a rebuild into a clean directory produces `bin/lib/*.cjs` byte-identical to what is on disk.
  2. The fence-extraction harness executes each extracted fence once per shell over `{/bin/bash 3.2.57, /bin/zsh 5.9}` using **absolute** interpreter paths, and each test case name carries its shell, so a failure report names which shell failed rather than which file.
  3. Run on `local/*` against the unfixed sites, `node --test tests/unreachable-shell-guard.test.cjs` exits non-zero on the zsh rows while the bash-only rows stay green — and `grep` over the harness finds no skip list, `skip`, `todo`, or expected-failure marker covering any fence site. The phase closes with the harness RED and unmerged; Phase 4 ships it green.
  4. After a `node --test` check hits its bound, no descendant of the runner survives — asserted on the survivor side (`pgrep`/`lsof` finds nothing holding the temp directory), with cleanup ordered *after* the survivor check so `t.after` cannot delete the evidence. Reverting `--test-isolation=none` in `buildNodeTestArgs` turns that assertion RED.
  5. `make install` run over a config dir containing `skills/gsd-review-concurrent/`, `skills/gsd-graph/` and `agents/gsd-prd-reviewer.md` leaves all three present afterward, and its pre-flight prints each user-authored file it found **by path** rather than a bare count — tolerating a `manifest_version` older than the tracked release.
**Plans**: TBD
**PR shape**: The three local-only artifacts + the `make install` pre-flight are one concern; the harness parameterization is a tests-only change needing no changeset; the runtime rebuild is not a PR at all.
**Note**: Verify with the isolation flag in place that the `GSD_PROHIB_SUBJECT` convention and `childEnv()`'s `NODE_TEST_CONTEXT` / `NODE_OPTIONS` stripping still behave — the flag imports the subject into the runner process and moves the wall that stripping guards. Also confirm zsh is present on `ubuntu-latest`, or coverage rests on the three macOS shards alone.

### Phase 2: Workstream resolution refuses rather than misroutes
**Goal**: A state-mutating verb in workstream mode either writes the workstream's file or refuses — never the root file — and a broken pointer stays diagnosable from the CLI
**Depends on**: Phase 1 (build-before-measure; a repro taken against stale `bin/lib/` is a phantom)
**Requirements**: WS-01, WS-02, WS-03, WS-04, WS-05, WS-06, WS-07, WS-08
**Success Criteria** (what must be TRUE):
  1. Given an active-workstream pointer naming `ws-a` and `.planning/workstreams/` removed entirely (T1), `gsd-tools state advance-plan` exits non-zero and root `.planning/STATE.md` has the same `shasum` before and after the call; the identical setup and assertion holds for `init progress` and `phase complete`, all three refusing through one predicate exported from `src/planning-workspace.cts`.
  2. The same three verbs refuse with the same `ERROR_REASON` code when `.planning/workstreams/` survives holding only a `.DS_Store` (T2) — proven by running one shared assertion body against both fixtures, not two hand-written tests.
  3. The refusal's stdout is JSON carrying `diagnoseUnresolvedActiveWorkstream`'s exact `{ present, value, reason }` shape, naming which marker failed, so a calling agent branches on the field without parsing prose; on `--raw` the same information also reaches stderr.
  4. A pointer-resolved authoritative read still exits 0 in both T1 and T2 and reports the non-resolution as a field; `gsd-tools workstream get` run twice in succession reports the same dangling pointer both times, keeping "never set" and "set but broken" distinguishable after the first look.
  5. `workstream complete` on a `.DS_Store`-blocked tree reports `reverted_to_flat: false` — matching the directory that demonstrably still exists — and clears the adapter it actually resolved from; meanwhile a flat project with no `.planning/workstreams/` and no pointer sees **no** new refusal from any of the three guarded verbs, asserted as a characterization test pinned before the predicate changes.
**Plans**: TBD
**PR shape**: **PR-A** — the corrected predicate in `planning-workspace.cts` plus **all three** guard sites (`init.cts:2926`, `phase.cts:2212`, `state advance-plan`) as ONE concern, matching upstream `51dfa683` (#2028) and superseding WIP `f72f1534`. **PR-B (read surface)** — `output()`'s conditional non-resolution field plus `workstream get` → `peekActiveWorkstream` (WS-05, WS-06); this split is sized here, it is not one of the pinned splits, and it is *not* research's earlier "PR-B", which was `state advance-plan` and now lives inside PR-A. **PR-C** — `workstream complete` honesty (WS-07), a separate concern.
**Note**: The predicate is `listAvailableWorkstreams(cwd).length > 0 || diagnoseUnresolvedActiveWorkstream(cwd).present` — a monotone disjunction. Do **not** scope it around `fs.existsSync('.planning/workstreams')`, which reads false in exactly the T1 case that produces the bug. Do **not** hoist the guard into `dispatchHostCommand`: that kills the Class C diagnostics at the moment they are needed. One unmeasured cell to verify in the call-site matrix: `diagnoseUnresolvedActiveWorkstream(cwd).present` in the post-`.DS_Store` state.

### Phase 3: STATE.md write integrity
**Goal**: A body-only write to STATE.md changes only the body — good counters are never overwritten by a stale disk scan
**Depends on**: Phase 2 (`state.cts:657` (guard) and `:679` (resync arg) are the same function; and the silent `advance-plan` call that mutated the wrong STATE.md *also* rewrote its `progress` block, so fixing the write path first would mean correctly resyncing the wrong file)
**Requirements**: STATE-01
**Success Criteria** (what must be TRUE):
  1. Appending a decision or blocker to a STATE.md whose frontmatter reads `total_plans: 12, completed_plans: 7`, in a tree where a disk scan would compute different numbers, leaves the `progress` block byte-identical afterward.
  2. That holds at each of the six body-only write sites (`state.cts:868, 1086, 1154, 1259, 1344` and `gsd-tools.cjs:1172`) — one fixture per site, asserted on the frontmatter block rather than on the whole file, so a body change cannot mask a frontmatter regression.
  3. For each of the three `{ divergedFields }` sites, running the verb against a fixture whose frontmatter and disk scan disagree produces the resync behaviour the phase specifies for that site, and reverting that site's argument flips the observed frontmatter — so the behaviour is pinned per site rather than assumed uniform.
**Plans**: TBD
**PR shape**: One concern — the resync argument on the body-only appenders. The `{ divergedFields }` decision is a second concern if it changes behaviour at any of the three sites.
**Note**: Flag for `--research-phase`. The `{ divergedFields }` three-site question is a genuine open design question, not a mechanical fix, and needs its own discussion before the change is written.

### Phase 4: Shell fences that run under the login shell
**Goal**: A shipped fence behaves under the login shell exactly as it does under bash, and an unsafe idiom cannot re-enter the corpus
**Depends on**: Phase 1 (the harness must exist and be able to see the difference before any site is touched — fixing sites first is round five of #2770 → #2962 → #3300 → #3409)
**Requirements**: SHELL-01, SHELL-02, SHELL-03, SHELL-04, INST-03
**Success Criteria** (what must be TRUE):
  1. For each fixed glob-guard fence, running it under `/bin/zsh` 5.9 with a glob matching **zero** files completes with exit 0 and takes the empty branch (no `no matches found` abort), and with a glob matching **N > 0** files processes all N — and in both directions the fence's captured stdout is identical to the same fence run under `/bin/bash` 3.2.57.
  2. The Phase 1 harness, otherwise unchanged, goes from RED to green across all 11 fence-idiom sites, and reverting any single site fix turns it RED again — the harness and the site fixes reach upstream in **one** PR, green on arrival, with no skip list or expected-failure marker anywhere in the change.
  3. `scripts/lint-portable-glob-guard.cjs` reports zero violations over the shell-tagged fence corpus at a zero baseline with no allowlist escape, and reports a violation when any of the seven idioms is reintroduced into **one** fence of a multi-fence file — proving it operates per-fence, not per-file (`complete-milestone.md` has a shim at `:331` and an unprotected glob-array at `:369` in a different fence).
  4. Each of the seven rules is demonstrated matching its CST shape against the real corpus rather than a synthetic fixture, on `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1` loaded from the `.wasm` by path (never `require('tree-sitter-bash')`), with the ~19 pseudo-code fences as an enumerated exclusion list.
  5. `wc -c agents/gsd-verifier.md` is under 49,152 after the fix, and the CI fence lane runs on `pull_request` — no `full_only: true` — as a narrow macOS-gated `shell-fences` job passing absolute interpreter paths.
**Plans**: TBD
**PR shape**: **PR-1** — the cross-shell harness plus the 11 site fixes together, green on arrival upstream (this is what discharges INST-03's "one PR" half; Phase 1 delivered its RED half). **PR-2** — the ratchet lint, with an ADR amending ADR-3409's premise (measured at 0.6% of fences, not a blocker).
**Note**: Flag for `--research-phase` — the tree-sitter rules are confirmed *expressible* but have never been run against the corpus; a spike closes that before the lint is wired into `lint:ci`. The same phase must settle process-substitution vs pipe before any `sh` lane is added: the two forms are mutually exclusive and `.planning/reference/shell-fence-portability.md` currently asserts both. `sh-syntax` is rejected for its positional-only JSON AST — **not** for lacking zsh, which it has. Update the reference doc in the same commit as the fixes. `port-4-10` (mempalace recall line) is blocked on the content-read site fixes.

### Phase 5: Workflow files routed through resolved workstream paths
**Goal**: In workstream mode a workflow writes its planning file where the workstream resolves, and whatever reads that file resolves the same way
**Depends on**: Phase 2 (the sweep consumes resolved paths whose correctness Phase 2 establishes) and Phase 4 (several of these files are fence edits and must land on a tree the harness can see)
**Requirements**: ROUTE-01, ROUTE-02, ROUTE-03, REPORT-03
**Success Criteria** (what must be TRUE):
  1. With a workstream resolving, exercising the file-writing step of each of the 8 affected workflows creates the file under `.planning/workstreams/<ws>/`, and a before/after listing of root `.planning/` shows **no** new file there — run across all 27 sites, not a sample.
  2. `pause-work`'s phase glob returns a non-empty list against a fixture holding real `NN-slug/` phase directories, and its gate is live: changing the gate's condition changes observed behaviour, where today it cannot.
  3. A write-then-read round trip in workstream mode agrees on scope — `state signal-waiting` writes `WAITING.json` to the path `init progress` reads, verified by the reader finding the signal the writer just wrote.
  4. The `#` column in the quick-tasks table has exactly one writer: applying an escaped description containing `|` and then a `#` renumber, in sequence, yields a table that `src/markdown-table.cts` re-parses into the same rows it was given.
**Plans**: TBD
**PR shape**: The routing sweep is one concern. The `quick.md` pair (`escape-description` then `reconcile-hash-column`) share `src/markdown-table.cts` at adjacent lines and must be sequenced or merged, never parallelised. `pause-work` carries two todos with overlapping lines — sequence them.
**Note**: The Class D hardcoded-root sites (D-1 `quick-tasks-append`, D-2 the `WAITING.json` split-brain, D-3 the context-monitor root check) belong to this target feature; a guard cannot reach them. Shared-file collisions to sequence rather than parallelise: `pause-work.md`, `quick.md`, `ship.md` (routing sweep vs. Phase 6's glab rewrite).

### Phase 6: Port campaign remainder and reporting correctness
**Goal**: The 1.10.0 → 1.11.0 port campaign is closed out, with the graphify seed-floor invariant restored under CI that fails on its **deletion**, and the counts the tooling reports are the counts that are true
**Depends on**: Phase 1 (the installer fix clears `port-4-8`) and Phase 4 (`review.md`'s fence fix is the reference implementation and lands first)
**Requirements**: PORT-01, PORT-02, PORT-03, PORT-04, PORT-05, PORT-06, REPORT-01, REPORT-02
**Success Criteria** (what must be TRUE):
  1. Deleting the seed-floor assertion lines from `tests/graphify-query.test.cjs` on a scratch branch makes CI fail — demonstrated by actually removing them and observing the espree invariant-title lock name the missing title. (`scripts/lint-removed-but-needed.cjs` does not cover this: it keys on deleted *files*.)
  2. A PR touching only `tests/graphify-query.test.cjs` starts the mutation workflow — `mutation.yml`'s `on.paths` allow-list and `scripts/mutation-matrix.cjs`'s `COVERED` change in **one** commit — and the recorded floor comes from a CI measurement, not a local run that counts timeouts as kills.
  3. graphify scores seeds by match quality and budget-cliff uses per-edge hop distance, landing as `port-4-4` → `port-4-3` → `port-4-3b` in that order over the shared `ExpandResult` surface, with `arbGraph` reliably producing ≥2 differentiated-quality seeds where it produced them in 0 of 200 runs before.
  4. `ship.md`'s glab path is reachable and exercised on 1.11.0 rather than inert; separately, a review lane observed to time out does so at its configured bound rather than the default, and convergence routing takes the configured route — the timeout half after Phase 4's `review.md` work, the routing half after Phase 1's installer fix.
  5. `resolve-library-id` is called with the arguments the current API requires; the statusline reports the model's real context window rather than a hardcoded value; `audit-open` on a fixture holding more open items than the display cap reports the true total; and the context monitor invoked inside a subagent reports that subagent's usage, not the parent session's.
**Plans**: TBD
**PR shape**: **PR-1** the graphify chain (`4-4` → `4-3` → `4-3b`, shared surface, must stay together) · **PR-2** the glab migration · **PR-3** the small independents (4.2, 4.6, 4.7).
**Note**: `port-4-2`, `port-4-6`, `audit-open` and the context monitor have no shared surface with anything in this milestone and no upstream dependency — they sit here because this is the remainder bucket, and may be pulled forward at any point as filler. The glab migration is the largest `ship.md` change and goes last to minimise conflicts with Phase 5's routing sweep.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Instruments before repairs | 0/TBD | Not started | - |
| 2. Workstream resolution refuses rather than misroutes | 0/TBD | Not started | - |
| 3. STATE.md write integrity | 0/TBD | Not started | - |
| 4. Shell fences that run under the login shell | 0/TBD | Not started | - |
| 5. Workflow files routed through resolved workstream paths | 0/TBD | Not started | - |
| 6. Port campaign remainder and reporting correctness | 0/TBD | Not started | - |

## Coverage

All 32 v1.12 requirements map to exactly one phase. No orphans, no duplicates.

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | INST-01, INST-02, INST-04, INST-05, INSTALL-01, INSTALL-02 | 6 |
| 2 | WS-01 … WS-08 | 8 |
| 3 | STATE-01 | 1 |
| 4 | SHELL-01 … SHELL-04, INST-03 | 5 |
| 5 | ROUTE-01, ROUTE-02, ROUTE-03, REPORT-03 | 4 |
| 6 | PORT-01 … PORT-06, REPORT-01, REPORT-02 | 8 |
| **Total** | | **32** |

`WS-F01`, `WS-F02`, `TOOL-F01` and `TOOL-F02` are Future Requirements — deferred past v1.12 and
deliberately unmapped.
