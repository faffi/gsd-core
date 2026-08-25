# Requirements: gsd-core (faffi fork) — Milestone v1.12

**Defined:** 2026-08-24
**Core Value:** Every local divergence from upstream is either deliberately carried (recorded,
with a reason) or on its way upstream (as a fix with a test) — never silently accumulating as
drift that the next `make install` destroys.

> **Requirement voice.** The "user" of this project is a developer or a Claude session driving
> `gsd-tools` and the GSD workflows. Requirements are written from that operator's seat.
> Derived from `.planning/research/SUMMARY.md` (2026-08-24) and the 22 todos in
> `.planning/todos/pending/`.

## v1.12 Requirements

### Instruments — measurement that can fail

- [ ] **INST-01**: A developer running any before/after check in this tree measures committed
      source, not stale build output — `gsd-core/bin/lib/*.cjs` never disagrees with `src/*.cts`
- [ ] **INST-02**: A shell fence extracted from agent/command/workflow markdown is executed by the
      test harness under **every** shell it can meet in production (bash 3.2.57, zsh 5.9, POSIX sh),
      not a single hardcoded interpreter
- [ ] **INST-03**: The cross-shell harness is proven able to fail — it lands **RED** against the
      unfixed sites on `local/*` before any site fix, and reaches upstream green, carrying the
      harness and the fixes in one PR. A skip list or expected-failure marker does NOT satisfy this:
      that is precisely how a suite stays green while the bug is live, which is the condition that
      hid this defect through four upstream rounds
- [ ] **INST-04**: A hung `node --test` check terminates its whole process tree; no orphaned
      grandchild survives to spin a core
- [ ] **INST-05**: A test asserting a subprocess bound asserts the **survivor** side — that nothing
      outlived the bound — not merely that the parent returned

### Workstream resolution — refuse rather than write the wrong file

- [ ] **WS-01**: A state-mutating verb refuses, with a non-zero exit, when a workstream pointer is
      present but unresolvable — instead of silently advancing root `.planning/STATE.md`
- [ ] **WS-02**: The refusal fires for **both** paths into the dangling state: the workstream
      directory removed entirely, and the directory surviving empty because a `.DS_Store` made
      `rmdirSync` throw into a swallowing catch
- [ ] **WS-03**: One shared predicate serves every guarded verb — a caller cannot find two verbs
      disagreeing about whether the project is in workstream mode. Scope for v1.12 is the three
      guard sites only (`init.progress`, `phase.complete`, `state advance-plan`); the predicate
      lives in `planning-workspace.cts` so the fail-safe paths cannot drift, per #2028's precedent
- [ ] **WS-04**: The refusal names which marker failed and why, in machine-readable JSON, so a
      calling agent can branch on it without parsing prose
- [ ] **WS-05**: A pointer-resolved authoritative **read** reports the non-resolution as a field
      rather than refusing — the broken state stays diagnosable from the CLI
- [ ] **WS-06**: `workstream get` no longer destroys the evidence — inspecting a dangling pointer
      does not delete it, so "never set" and "set but broken" remain distinguishable
- [ ] **WS-07**: `workstream complete` reports `reverted_to_flat` from what actually happened, and
      clears the adapter it actually resolved from
- [ ] **WS-08**: A flat, non-workstream project is unaffected — no new refusal reaches a project
      that never adopted workstreams

### STATE.md write integrity

- [ ] **STATE-01**: A body-only append to STATE.md leaves the `progress` frontmatter alone — it does
      not resync counters from a disk scan and overwrite good values with a stale reading

### Shell fence portability

- [ ] **SHELL-01**: A glob guard in a shipped fence behaves correctly under the login shell on both
      paths — it neither aborts when the glob matches nothing nor silently skips when it matches
- [ ] **SHELL-02**: All affected sites are fixed together as one root cause, not filed as separate
      symptoms
- [ ] **SHELL-03**: A lint rejects the unsafe idioms so a fixed site cannot silently regress, and
      new fences cannot reintroduce them
- [ ] **SHELL-04**: The lint is built on a substrate that can actually express the rules — a parser
      exposing named CST fields, not a positional-only AST

### Workflow path routing

- [ ] **ROUTE-01**: A workflow writing a planning file in workstream mode writes it to the resolved
      workstream path, not a hardcoded root path
- [ ] **ROUTE-02**: `pause-work`'s phase glob matches real phase directories, and its gate is live
      rather than dead
- [ ] **ROUTE-03**: A writer and its reader agree on scope — no file written workstream-scoped and
      read root-hardcoded

### Local artifact survival

- [ ] **INSTALL-01**: `make install` does not destroy locally-authored skills and agents
- [ ] **INSTALL-02**: The install pre-flight detects user-authored files before overwriting, using
      the manifest and checksum machinery the repo already ships

### Port campaign completion

- [ ] **PORT-01**: The graphify seed-floor invariant is restored, and its **deletion** fails CI —
      not merely its violation
- [ ] **PORT-02**: `context7 resolve-library-id` is called with the arguments the current API
      requires
- [ ] **PORT-03**: The statusline reports against the model's real context window
- [ ] **PORT-04**: graphify scores seeds by match quality, and budget-cliff uses per-edge hop distance
- [ ] **PORT-05**: The glab forge port is live rather than inert, and runs on 1.11.0
- [ ] **PORT-06**: Review-lane timeouts and convergence routing carry their intended values rather
      than being inert as specified

### Reporting correctness

- [ ] **REPORT-01**: `audit-open` reports the true count, not the display cap
- [ ] **REPORT-02**: The context monitor reports a subagent's own context usage, not the parent
      session's
- [ ] **REPORT-03**: The `#` column has one writer with one contract

## Future Requirements

Deferred past v1.12. Tracked, not in this roadmap.

### Workstream resolution — Class A tail

- **WS-F01**: The remaining Class A verbs (`config-*`, `template.fill`, `scaffold`, `todo.complete`,
  `estimate-calibrate`, `audit acknowledge`) adopt the shared predicate — v1.12.x
- **WS-F02**: The Class B gate verbs (`check.decision-coverage-*`, `check.ui-plan-gate`,
  `check.api-coverage.verify-pre`) move from field to refusal — highest-value contested band, but a
  behaviour change rather than a defect fix

### Tooling

- **TOOL-F01**: The `mutation` metadata becomes load-bearing with a CI lint — currently a
  near-complete but unenforced classification with four disagreements and two absences
- **TOOL-F02**: A handoff skill that merges rather than regenerates (SEED-001, promoted)

## Out of Scope

| Excluded | Reason |
|---|---|
| Guarding `roadmap.*` | Zero `planningDir(cwd)` sites in `src/roadmap.cts` and no reproduced defect. With no defect evidence it reclassifies from fix to **enhancement**, triggering the `approved-enhancement` pre-approval gate at `CONTRIBUTING.md:54-62` — a materially heavier path for no measured benefit |
| Guarding the remaining `state.*` / `phase.*` verbs in v1.12 | No issue describes the verb *families*, so it would breach `CONTRIBUTING.md:199` ("scope matches the approved issue"). Upstream has guarded exactly two verbs in four months, one per PR |
| Hoisting the guard into the CLI dispatcher | Would refuse in read-only `workstream` verbs, making a dangling pointer undiagnosable from the CLI. Top-ranked anti-feature in the research |
| Adding refusals to all ~25 Class B verbs | A behaviour change, not a defect fix — they get the surfaced field instead |
| Normalising `cmdStateAdvancePlan`'s existing exit-0 paths | ADR-2980 declined it on measured blast radius: 60 sites, 170 `output` callers. The mixed contract is ratified, not accidental |
| `shellcheck` as the portability lint | No zsh dialect in any release, and structurally blind regardless — every mechanism is *valid bash* |
| `sh-syntax` / `mvdan-sh` as the lint substrate | Positional-only JSON AST: no node type, no `Args`, empty `Word.Lit`. No rule is expressible against it. Rejected for the AST, **not** for lacking zsh — it has zsh |
| Patching `bin/install.js` directly | Per the todo's own verdict; the general fix wires the Makefile to machinery that already exists |
| Splitting the shell-fence mechanisms into separate todos | Would repeat upstream's #2770 → #2962 → #3300 → #3409 fragmentation of one root cause |
| Marking the 11 unfixed fence sites as expected-failure/skip | Keeps the suite green while the bug is live — the exact condition that hid this through four rounds. See INST-03 |

## PR boundaries

A phase is a unit of context and sequencing; a PR is a unit of review. They are not the same, and
the roadmapper must not collapse them — one phase emitting one giant PR is the churn this milestone
is trying to avoid. Where a phase spans independent surfaces, split it:

| Phase | PR split |
|---|---|
| Workstream resolution | **PR-A** the corrected predicate in `planning-workspace.cts` + all three guard sites (`init.cts:2926`, `phase.cts:2212`, `state advance-plan`; supersedes WIP `f72f1534`) — ONE concern, three sites, matching `51dfa683` (#2028) · **PR-C** `workstream complete` honesty, a separate concern per `CONTRIBUTING.md:195` |
| Port campaign | **PR-1** graphify chain (`4-4` → `4-3` → `4-3b`, shared surface, must stay together) · **PR-2** glab migration · **PR-3** small independents (4.2, 4.6, 4.7) |
| Fence portability | **PR-1** harness (red locally) + the 11 site fixes, green on arrival · **PR-2** the ratchet lint |

## Traceability

Filled during roadmap creation.

| Requirement | Phase | Status |
|---|---|---|
| (pending roadmap) | — | — |
