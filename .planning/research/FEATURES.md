# Feature Research — v1.12 Defect-Fix Milestone

**Domain:** Expected behaviour of four subsystems under repair in the faffi fork of gsd-core (TypeScript/Node CLI toolchain, upstream 1.11.0)
**Researched:** 2026-08-24
**Confidence:** HIGH for clusters 1, 3, 4 — source-read at every cited line, plus executed reproductions in this repo (the Class A verb table, the empty-`workstreams/` state, the `workstream get` pointer deletion, the stale-build trap, and the `detect-custom-files` run). HIGH for cluster 2's git and kubectl citations (primary source read verbatim); the one terraform sub-claim that is undocumented is labelled as undocumented rather than asserted.

> "Features" here means **correct expected behaviour**, so the 22 captured defect fixes restore intent rather than cement the bug. Everything below is derived from reading `src/*.cts` and from executed reproductions in throwaway trees under `$TMPDIR`, not from recall.

---

## 0. READ FIRST — an environment trap that invalidates before/after testing

`gsd-core/bin/lib/*.cjs` is **gitignored build output** (`.gitignore:325`), and `gsd-core/bin/ensure-runtime-build.cjs` rebuilds it **only when it is absent** (an `existsSync` check). A `git checkout` of `src/` therefore leaves a stale compiled tree in place.

In this working tree, right now:

| File | Contains the `state advance-plan` workstream guard? |
|---|---|
| `src/state.cts` | **No** — `grep listAvailableWorkstreams src/state.cts` → no match |
| `gsd-core/bin/lib/state.cjs` (mtime 16:29, older than `src/state.cts` at 16:54) | **Yes** — `:439`, `:443` |

Executed proof: with a dangling pointer, `node gsd-core/bin/gsd-tools.cjs query state advance-plan` printed
`Error: state advance-plan requires a workstream in workstream mode — no active workstream is set…` and exited **1**, while the source it is supposedly built from has no such guard.

**Consequence for the roadmap:** any phase that "verifies the defect reproduces" or "verifies the fix works" must run `npm run build:lib` (or delete `gsd-core/bin/lib/`) first, or it will measure a phantom. This belongs in the *first* phase of the workstream cluster, not as a late verification step.

---

## 1. Cluster 1 — Workstream fail-safe semantics

### 1.1 The two mode predicates genuinely disagree, and the disagreement is reachable

Two definitions of "workstream mode" exist:

| Definition | Site | Predicate |
|---|---|---|
| Directory-presence | `src/workstream.cts:77`, `cmdWorkstreamGet` (`:380`), `cmdWorkstreamList` via inventory | `fs.existsSync('.planning/workstreams')` |
| At-least-one-subdirectory | `listAvailableWorkstreams` (`src/planning-workspace.cts:151-161`) — consumed by both fail-safe guards | `readdirSync(...).filter(isDirectory).length > 0` |

`listAvailableWorkstreams`'s own docstring (`planning-workspace.cts:148-150`) claims to be "single source of truth for the 'workstream mode' detection" — while `workstream.cts:77` already defines it differently. There are **two claimed sources for one concept**.

**Concrete trigger, executed:** `cmdWorkstreamComplete` (`workstream.cts:334-338`) counts only *directories* in `workstreams/`, and on zero calls `fs.rmdirSync(wsRoot)` inside `catch { /* ignore */ }`. One non-directory entry — and this repo's own CLAUDE.md names `.DS_Store` under these trees as a live hazard — makes the count 0, `rmdirSync` throw `ENOTEMPTY`, and the catch eat it.

```
$ touch .planning/workstreams/.DS_Store
$ gsd-tools workstream complete default --raw
{ "completed": true, ..., "remaining_workstreams": 0, "reverted_to_flat": true }   ← FALSE

$ ls -a .planning/workstreams            → .  ..  .DS_Store        (directory survives)
$ gsd-tools workstream get               → { "active": null, "mode": "workstream" }
$ gsd-tools workstream list              → { "mode": "workstream", "workstreams": [], "count": 0 }
$ node -e 'listAvailableWorkstreams(R)'  → []                       (guards believe FLAT)
$ gsd-tools init.progress --raw          → proceeds, reports stale ROOT data, exit 0
```

**The tool tells the caller it is in workstream mode while the guards believe it is flat, and `workstream complete` reports `reverted_to_flat: true` when it did not revert.** Three defects in one state.

**Recommended predicate:** make the guards agree with `existsSync` (the *broader* side), not the reverse. Rationale: the broad side is what the user-facing verbs already report, so narrowing mode detection would make `workstream get` lie in the opposite direction. Check the blast radius of the `existsSync` side before committing — `listAvailableWorkstreams` is also the source of the "Available workstreams: …" hint in both error messages, and that list is legitimately empty here.

### 1.2 The refuse/proceed boundary is NOT read-vs-write

The lead's framing ("MUTATING should refuse, READING must not") is disproved by the codebase's own two guards:

| Verb | Declared `mutation` | Refuses today? | Guard's own stated reason |
|---|---|---|---|
| `init.progress` | **false** | **yes** (`init.cts:2932`) | "silently **reporting** a stale root milestone" |
| `phase.complete` | true | yes (`phase.cts:2218`) | "would **write** … into the shared root that other workstreams read" |

The shared axis is **silent substitution of root-scoped data for workstream-scoped data that the caller cannot detect** — which covers writes (corruption) *and* authoritative reads that drive a downstream decision. Three classes, not two.

Second disproof, verified in source: `workstream.progress` is `mutation: true` and it **does** write — `listWorkstreamInventories` → `writeVerificationLedger` (`workstream-inventory.cts:408-435`) writes `.verification-ledger.json` into each workstream dir. But it enumerates those dirs **by name from `planningRoot`**, never through the pointer. It writes and still cannot misroute. Mutation is the wrong axis; **pointer-resolution is the right one.**

### 1.3 THE VERB CLASSIFICATION — the deliverable

Classification key is the **path-resolution mechanism at the call site**, because that is the defect mechanism:

- **Class A — pointer-resolved MUTATING.** Output path comes from `planningDir()` / `planningPaths()`, which read `process.env.GSD_WORKSTREAM`. A wrong resolution writes a *different file than the caller named*. → **MUST REFUSE.**
- **Class B — pointer-resolved AUTHORITATIVE READ.** Same resolver, no write, but the output drives a downstream decision (workflow routing, phase selection, gate verdicts). → **CONTESTED BAND** — decide per verb; see 1.5.
- **Class C — root-scoped / structurally immune.** Resolves only via `planningRoot()`, or enumerates workstreams by name. Cannot misroute. → **MUST NEVER REFUSE.**
- **Class D — hardcoded root path.** Bypasses the resolver entirely (`path.join(cwd, '.planning', …)`). Wrong in workstream mode *unconditionally*, pointer or no pointer. → **separate fix; a guard cannot help these.**

#### Class A — pointer-resolved MUTATING (should refuse)

| Verb | Implementation | Path mechanism |
|---|---|---|
| `state.update` | `cmdStateUpdate` `state.cts:575` | `planningPaths(cwd).state` |
| `state.patch` | `cmdStatePatch` `:519` | `planningPaths(cwd).state` |
| `state.begin-phase` | `cmdStateBeginPhase` `:3712` | `planningPaths(cwd).state` |
| **`state.advance-plan`** | `cmdStateAdvancePlan` `:656` | `planningPaths(cwd).state` — **the reported defect** |
| `state.record-metric` | `cmdStateRecordMetric` `:721` | `planningPaths(cwd).state` |
| `state.update-progress` | `cmdStateUpdateProgress` `:925` | `.state` + `.phases` |
| `state.add-decision` | `cmdStateAddDecision` `:1050` | `planningPaths(cwd).state` |
| `state.add-blocker` | `cmdStateAddBlocker` `:1135` | `planningPaths(cwd).state` |
| `state.add-roadmap-evolution` | `cmdStateAddRoadmapEvolution` `:1201` | `planningPaths(cwd).state` |
| `state.resolve-blocker` | `cmdStateResolveBlocker` `:1337` | `planningPaths(cwd).state` |
| `state.record-session` | `cmdStateRecordSession` `:1383` | `planningPaths(cwd).state` |
| `state.planned-phase` | `cmdStatePlannedPhase` `:4012` | `planningPaths(cwd).state` |
| `state.milestone-switch` | `cmdStateMilestoneSwitch` `:4080` | `planningPaths(cwd).state` |
| `state.sync` | `cmdStateSync` `:4400` | `.state`, `.phases`, `planningDir/ROADMAP.md` |
| `state.prune` | `cmdStatePrune` `:4586` | `planningPaths(cwd).state` |
| `state.rebuild` | `cmdStateRebuild` `:4691` | `.state` + `<planning>/phases` |
| `state.complete-phase` | `cmdStateCompletePhase` `:4883` | `planningPaths(cwd).state` |
| `state.signal-waiting` | `cmdSignalWaiting` `:3792` | `planningDir(cwd)/WAITING.json` (see D-2) |
| `state.signal-resume` | `cmdSignalResume` `:3817` | `planningDir(cwd)/WAITING.json` |
| `phase.add` | `cmdPhaseAdd` `phase.cts` | `planningDir(cwd)` |
| `phase.add-batch` | `cmdPhaseAddBatch` | `planningDir(cwd)` |
| `phase.insert` | `cmdPhaseInsert` | `planningDir(cwd)` |
| `phase.remove` | `cmdPhaseRemove` | `planningDir(cwd)` |
| **`phase.complete`** | `cmdPhaseComplete` `:2200` | `planningDir(cwd)` ROADMAP/STATE/phases — **already guarded** |
| `phases.clear` | `cmdPhasesClear` `milestone.cts:1159` | `planningPaths(cwd).phases` — **destructive `rmSync` of phase dirs** |
| `milestone.complete` | `cmdMilestoneComplete` `milestone.cts:549` | `planningPaths(cwd)` `.roadmap` `.requirements` `.state` `.planning` `.phases` (`:563-573`) |
| `milestone.archive-quick` | `cmdQuickArchive` `milestone.cts:1683` | `planningPaths(cwd).state` `:1694`, `.planning` `:1695` |
| `requirements.mark-complete` | `cmdRequirementsMarkComplete` `milestone.cts:129` | `planningPaths(cwd).requirements` `:146` |
| `requirements.revert-phase` | `cmdRequirementsRevertPhase` `milestone.cts:450` | `planningPaths(cwd).requirements` `:463` |
| `roadmap.update-plan-progress` | `cmdRoadmapUpdatePlanProgress` `roadmap.cts:755` | `planningPaths(cwd).roadmap` `:760` |
| `roadmap.annotate-dependencies` | `cmdRoadmapAnnotateDependencies` `roadmap.cts:1076` | `planningPaths(cwd).roadmap` `:1081` |
| `roadmap.upgrade` | `roadmap-upgrade.cts` | `planningDir(cwd)/ROADMAP.md` |
| `scaffold` (`context`/`uat`/`verification`/`phase-dir`) | `cmdScaffold` `commands.cts:2170` | phase dir via `findPhaseInternal` → `planningPaths(cwd).phases` |
| `todo.complete` | `cmdTodoComplete` `commands.cts:2143` | `path.join(planningDir(cwd), 'todos', 'pending'\|'completed')` `:2148-2149`; also `planningPaths(cwd).phases` `:2211` — see note T below |
| `template.fill` | `cmdTemplateFill` `template.cts:106` | `planningDir(cwd)` `:186` |
| `config-set` | `config.cts:578` | `planningDir(cwd)/config.json` — see note C below |
| `config-ensure-section` | `cmdConfigEnsureSection` `config.cts:472` | `planningDir(cwd)` `:441` |
| `config-set-model-profile` | `config.cts:611` / `:654` | `planningDir(cwd)/config.json` |
| `config-new-project` | `cmdConfigNewProject` `config.cts:398` | `planningDir(cwd)` `:398` |
| `estimate-calibrate` | `cmdEstimateCalibrate` `estimate-cli.cts:281` | `path.join(planningDir(cwd), CALIBRATION_FILENAME)` `:285` |
| `audit acknowledge` | `cmdAuditAcknowledge` `audit.cts:1529` | `planningDir(cwd)` `:1544`, then `todos/pending/<file>` `:1641` |

**Count: 41 verbs.** `state.*` alone is 19 of them — which is why the milestone's "one shared precondition" framing is right in intent and wrong if implemented as 41 copies of the guard.

Every row above was verified by reading the resolving call in the function body; none is inferred. Two rows carry a caveat that does **not** move them out of Class A but is worth knowing before scoping:

- **Note T — `todos/`.** `todo.complete` resolves `todos/pending` and `todos/completed` through `planningDir(cwd)`, and so do *all six* other todo sites (`commands.cts:236`, `:2015`, `:2148-2149`, `init.cts:2072/2099/2121-2122`, `audit.cts:693/1641`). The resolution is internally consistent, so a misroute writes the **root** `todos/completed` — genuinely Class A. Separate observation, not this milestone: `migrateToWorkstreams` (`workstream.cts:81-86`) never moves `todos/` into the workstream dir, so after migration a workstream's todo paths point at a directory migration did not create.
- **Note C — `config.json` is deliberately two-tier.** `config-loader.cts:672-712` reads the **root** config as a base and overlays `planningDir(cwd, ws)/config.json`, reporting `CONFIG_REASON.WORKSTREAM_FALLBACK` when only the root exists. So `config-set` writing the workstream copy is correct by design, and a misroute silently promotes a workstream-local setting to the project-wide config every workstream inherits. That makes it a *higher*-severity Class A member than its name suggests, not a lower one.

#### Class B — pointer-resolved AUTHORITATIVE READ (contested band)

| Verb | Implementation | Refuses today? | Recommendation |
|---|---|---|---|
| `init.progress` | `cmdInitProgress` `init.cts:2926` | **yes** | Keep refusing — precedent #1912; its output routes the whole workflow |
| `init.execute-phase`, `init.plan-phase`, `init.verify-work`, `init.phase-op`, `init.transition`, `init.resume`, `init.manager`, `init.debug`, `init.todos`, `init.discuss-phase-assumptions`, `init.milestone-op`, `init.new-milestone`, `init.quick` | `init.cts` | no | **Do not add refusals in v1.12.** Same substitution risk as `init.progress`, but 13 more refusal sites is a behaviour change far past a defect fix. Emit the surfaced-fallback field (cluster 2) instead |
| `state.load`, `state.json`, `state.get`, `state.validate`, `state-snapshot` | `state.cts:405/3614/456/4208/1806` | no | **Do not refuse.** These are the diagnostics an operator uses to *see* the broken state. Surface the fallback in the payload |
| `roadmap.get-phase`, `roadmap.analyze`, `roadmap.milestone-scope`, `roadmap.validate` | `roadmap.cts` | no | Do not refuse; surface |
| `phases.list`, `phase.list-plans`, `phase.next-decimal`, `find-phase`, `phase-plan-index` | `phase.cts` | no | Do not refuse; surface |
| `validate.consistency`, `validate.health`, `verify.schema-drift`, `verify.codebase-drift` | `verify.cts` | no | Do not refuse; surface |
| `check.decision-coverage-*`, `check.ui-plan-gate`, `check.api-coverage.verify-pre` | `check-command-router.cts` | no | Gate verdicts — highest-value members of this band. Flag for a later milestone |
| `stats.json`, `progress.bar`, `list-todos`, `list-seeds`, `history-digest`, `todo.match-phase`, `config-get`, `config-path`, `estimate-check`, `audit uat` | various | no | Do not refuse; surface |

#### Class C — root-scoped, structurally immune (must never refuse)

| Verb | Implementation | Why immune |
|---|---|---|
| `workstream get` | `cmdWorkstreamGet` `workstream.cts:377` | `planningRoot(cwd)` only |
| `workstream list` | `cmdWorkstreamList` `:225` | inventory over `planningRoot/workstreams` |
| `workstream status` | `cmdWorkstreamStatus` `:250` | `planningRoot(cwd)` + explicit name arg |
| `workstream progress` | `cmdWorkstreamProgress` `:383` | enumerates by name; writes only into each named ws dir |
| `workstream set` | `cmdWorkstreamSet` `:351` | `planningRoot` + explicit name; **this is the repair verb** |
| `workstream create` | `cmdWorkstreamCreate` `:114` | `planningRoot` + explicit name |
| `workstream complete` | `cmdWorkstreamComplete` `:285` | `planningRoot` + explicit name |
| `init.map-codebase` | `init.cts` | `planningRoot` only |
| `learnings.*`, `intel.*`, `graphify.*`, `research-store`, `broken-windows`, `git base-branch`, `profile-output` readers | various | Read shared root artifacts (`PROJECT.md`, `codebase/`, `research/`, `todos/`, `milestones/`) that migration deliberately leaves at root (`workstream.cts:60-66`) |

**This is the answer to the lead's diagnosability question.** `workstream get`/`list` are *structurally* immune — they never consult `planningDir`. The undiagnosability risk materialises **only if the guard is hoisted** to `dispatchHostCommand` or the CLI entry (see anti-features).

**But there is a separate, real diagnosability defect, executed:**

```
pointer file → "delta"
$ mv .planning/workstreams/delta .planning/workstreams/delta.bak
$ cat $TMPDIR/gsd-workstream-sessions/<id>/<session>   → delta
$ gsd-tools workstream get --raw                        → none
$ cat $TMPDIR/gsd-workstream-sessions/<id>/<session>   → No such file or directory
```

`cmdWorkstreamGet` calls the **mutating** `getActiveWorkstream` (`workstream.cts:378`), so the primary diagnostic **deletes the pointer on first invocation** and reports `active: null` — byte-identical to "nothing was ever set". `peekActiveWorkstream` exists precisely for this (`planning-workspace.cts:396-409`, added by #3579) and is not used here. **Table stakes.**

#### Class D — hardcoded root path (a guard cannot fix these)

| Site | Defect |
|---|---|
| **D-1 `quick-tasks-append`** — `gsd-core/bin/gsd-tools.cjs:1148` | `path.join(cwd, '.planning', 'STATE.md')`. **Always writes root STATE.md**, even when a workstream resolves correctly. Unconditional workstream-routing bug |
| **D-2 `WAITING.json` split-brain** | `state.signal-waiting` **writes** to `planningDir(cwd)/WAITING.json` (`state.cts:3793`); `init.progress` **reads** from `path.join(cwd, '.planning', 'WAITING.json')` (`init.cts:2526`). In workstream mode the signal is written where nothing reads it |
| D-3 `hooks/gsd-context-monitor.js:133` | `isGsdActive` = `existsSync(cwd/.planning/STATE.md)`. In workstream mode root STATE.md may not exist → the hook concludes GSD is inactive |

These map directly onto PROJECT.md's target feature *"workflow files resolved through workstream paths rather than root"*.

### 1.4 Cross-check against the existing `mutation` metadata

`src/command-aliases.cts` already carries a `mutation: boolean` on every alias — 22 state verbs, 9 phase, 3 phases, 7 roadmap, 27 init, 43 non-family. **It is unenforced:** the only consumer anywhere in `src/`, `tests/`, `hooks/`, `commands/`, `agents/` is a `typeof entry.mutation === 'boolean'` assertion at `tests/commands.test.cjs:4021`.

Disagreements found (all are reasons **not** to adopt it as the guard predicate):

| Verb | `mutation` | Reality | Verdict |
|---|---|---|---|
| `init.progress` | false | refuses today | Class B, refusal is correct |
| `workstream.progress` | true | writes, but by-name — cannot misroute | Class C |
| `workstream.get`, `workstream.status` | **absent from the alias table** | Class C | table is incomplete |
| `state.load` / `state.json` / `state.get` | false | Class B | correct but insufficient |
| `state.complete-phase` | **absent from `STATE_COMMAND_ALIASES`** | Class A (`cmdStateCompletePhase` `state.cts:4883`) | routed via `state-command-router.cts:81`, which has to re-add it by hand — a **mutating** verb with no classification at all |
| `phases.archive` | true | **not a CLI verb** — `phases-command-router.cts:49-51` filters it out of `PHASES_SUBCOMMANDS` (#2684, "internal") | the table declares a verb the router refuses to route |

Four disagreements and two absences across ~120 aliased verbs is a table nobody is maintaining, which is exactly what an unenforced field becomes.

**Differentiator, not table stakes:** making `mutation` load-bearing (or adding a sibling `pointer_scoped: boolean`) turns a near-complete decorative table into the single source the guard reads, and gives the roadmapper a lint that fails when a new verb is added without a classification.

### 1.5 Where the boundary should sit — recommendation

1. **Refuse** for all Class A. One extracted predicate, called from each verb.
2. **Do not refuse** for Class B in v1.12; surface the fallback instead (cluster 2). `init.progress` keeps its existing refusal — removing it would be a regression of #1912.
3. **Never refuse** for Class C, and fix `workstream get` to peek rather than self-heal.
4. **Class D is separate scope** — path-resolution fixes, not guard fixes.

---

## 2. Cluster 2 — Surfacing a self-heal

### 2.1 What a caller sees today

With a dangling pointer and the guard absent (i.e. `src/` as committed): exit 0, `stderr` empty, root STATE.md silently advanced — the todo's own reproduction. With the guard present (the stale build): exit 1 and a prose message, but **no machine-readable field naming the pointer that was cleared**. Under `--json-errors` the fault envelope does carry `marker_value` / `marker_reason` as `extra` (`io.cts:246`, passed at `phase.cts:2233`) — that is the right shape, and it exists **only on the fault path**, so no Class B/C verb can ever emit it.

### 2.2 In-repo precedents (these outrank any external survey)

- **ADR-2980 prescribes the shape**: a *named field plus a reason*, not an overloaded `error` key — `{"updated": false, "reason": "Progress field not found in STATE.md"}`.
- **`cmdWorkstreamList` already solved this exact problem class** — `workstream.cts:238-241`: *"#2562: a refused shipped marker must reach the surface. Projecting `status` without it renders the refusal invisible at the CLI, which is the silent-collapse defect this issue is about."*
- **`diagnoseUnresolvedActiveWorkstream`** (`active-workstream-store.cts:340-356`) already computes exactly the payload needed — `{ present, value, reason: 'invalid_name' | 'missing_workstream_dir' | null }` — read-only, no self-heal. Nothing outside the two guards consumes it.

### 2.3 Comparable tools — corroboration

| Tool | Behaviour | Evidence |
|---|---|---|
| **kubectl**, *setting* path | `config use-context` **validates and refuses** a nonexistent context — `fmt.Errorf("no context exists with the name: %q", o.contextName)` | `kubernetes/kubectl` `pkg/cmd/config/use_context.go`, `useContextOptions.validate` (read directly) |
| **kubectl**, *consuming* path | Returns a typed `errContextNotFound` — `"context was not found for specified context: %v"` — and **exports `IsContextNotFound(err) bool`** so callers branch programmatically rather than grepping prose | `kubernetes/client-go` `tools/clientcmd/validation.go` (read directly) |
| **git `advice.*`** | Hints are for humans, go to **stderr**, and subprocess callers are told to turn them off wholesale | git's own `Documentation/config/advice.adoc`, verbatim: *"As they are intended to help human users, these messages are output to the standard error. When tools that run Git as a subprocess find them disruptive, they can set `GIT_ADVICE=0` in the environment to squelch all advice messages."* |
| **terraform** | `terraform workspace select NAME` — *"The named workspace must already exist."* Creating on demand requires opt-in `-or-create` (default `false`). Refusal is the default; silent creation is a flag | `terraform workspace select` command reference, HashiCorp Developer (2025-11-19) |
| terraform, *consuming* path | The current workspace is stored "locally in the ignored `.terraform` directory", but **the docs do not state what happens if the selected workspace no longer exists in the backend**. Not asserted here | `terraform/cli/workspaces` |

**kubectl is the decisive citation for a typed field.** It refuses at the setting boundary *and* hands consuming callers an exported predicate — a machine channel, not a string to grep. That is precisely the `workstream set` (already refuses, `workstream.cts:368`) + `workstream_resolution` field split recommended below.

**git is the decisive citation against a stderr-only warning**, and it is unusually direct: git's own documentation states that advice messages exist for *human* users, go to stderr for that reason, and that **tools running git as a subprocess should squelch them entirely**. This tool's caller is an agent parsing stdout JSON — the exact case git's own docs tell you not to signal through.

### 2.4 Recommendation

**A named field in the stdout payload is table stakes; a stderr warning is a human-only affordance on top; no exit-code change on read paths.**

```jsonc
"workstream_resolution": {
  "requested": "tenant-vpc-reach",   // the name the pointer/env/--ws named
  "resolved":  null,                  // what routing actually used
  "reason":    "missing_workstream_dir",
  "self_healed": true                 // the pointer was cleared
}
```

Emitted by every Class A verb that proceeds and every Class B verb. It reuses `diagnoseUnresolvedActiveWorkstream`'s exact return shape, so it cannot drift from the resolution predicate. **`--json-errors` explicitly does not apply to payloads** (`docs/json-errors.md`), so a stderr-only signal is invisible to the tool's actual consumer — that is the anti-feature.

---

## 3. Cluster 3 — Exit-code contract

**The mixed contract is defensible and already ratified.** `docs/adr/2980-payload-carried-error-is-a-degraded-result.md` (Accepted, 2026-08-09) and `docs/json-errors.md` settle this; no external research is warranted.

The separating rule, quoted from the ADR:

> A JSON result on **stdout** carrying an `error` key, with **exit 0**, means the command **ran to completion and is reporting a condition through its result**. It is not a process failure.

versus a **fault** — `error(message, reason)` → stderr, exit 1, structured envelope under `--json-errors`. And a third path: `ExitError` → plain text, its own exit code, for usage errors.

**Applied to the new guard: exit 1 is correct and already sanctioned.** A precondition refusal is not a determination the command completed; it is the command declining to act. The ADR states directly: *"New code should prefer the fault path, or a named-field result… it is not a license to add a 61st site."* `phase.complete` and `init.progress` already use `error()` + a typed `ERROR_REASON` (`workstream_mode_none_active`, `workstream_mode_marker_unresolved`); `state advance-plan` matching them is consistency, not a new contract.

**Explicitly out of scope — do not scope a sweep.** `cmdStateAdvancePlan`'s existing exit-0 paths (`{"error": "STATE.md not found"}` at `state.cts:658`, `{"error": "Cannot parse Current Plan or Total Plans in Phase from STATE.md"}` at `:703`) stay exactly as they are. ADR-2980 declined normalization on measured Hyrum's-Law blast radius: 60 call sites across nine modules, `output` itself has 170 direct callers, and *"a CLI's exit code has no versioning escape hatch — there is no `/v2/` for `$?`."* A mixed contract inside one function is the ratified state.

---

## 4. Cluster 4 — Local-artifact survival

### 4.1 The todo's diagnosis is right about the mechanism and wrong about the coverage

`bin/install.js:10819-10829` is exactly as reported: `readdirSync(<targetDir>/skills)`, filter to directories starting with `gsd-`, `rmSync` each, then replace from this repo. A `gsd-*` artifact with no in-repo counterpart is deleted and never restored.

But the claim that the installer "has no notion of user content" is **not accurate**. This repo already ships **three** of the four patterns the survey asked about:

| Pattern | Implementation | Status |
|---|---|---|
| **Manifest of owned paths** | `gsd-file-manifest.json` (`MANIFEST_NAME`, `bin/install.js:9355`) — every shipped file keyed by relative path | Written by `install.js` on every install |
| **Checksums** | `fileHash(path)` per manifest entry; `saveLocalPatches()` diffs installed vs manifest to detect user *modifications* → `gsd-local-patches/` → `/gsd:update --reapply` | Working |
| **Detect + backup + restore of user-*added* files** | `gsd-tools detect-custom-files --config-dir` scans `GSD_WHOLE_MANAGED_DIRS` (`gsd-core`, `commands/gsd`) and `GSD_PREFIX_MANAGED_DIRS` (**`agents`, hooks, `skills`** — `gsd-*` prefixed entries only) for paths absent from the manifest; `restore-custom-files [--apply]` copies them back with never-clobber semantics (`RESTORE_OUTCOME` taxonomy, `gsd-tools.cjs:2645-2660`) | Working |
| **`local/` overlay directory** | none. Closest is `USER_OWNED_ARTIFACTS` (`install-engine.cts:91`) — a hardcoded allowlist, currently `['USER-PROFILE.md']`, backed by 812 lines of durable staging in `user-artifact-staging.cts` | This is the "named special case" that saves `gsd-dev-preferences` |

**`detect-custom-files` finds all three lost artifacts — verified by execution, not inference.** Run read-only against the live installed tree on 2026-08-24:

```console
$ node gsd-core/bin/gsd-tools.cjs detect-custom-files --config-dir "$HOME/.claude"
{
  "custom_files": [
    "gsd-core/USER-PROFILE.md",
    "gsd-core/bin/lib/capability-registry.cjs.bak-540s",
    "gsd-core/bin/lib/review-lane-descriptor.cjs.bak-540s",
    "agents/gsd-prd-reviewer.md",              <-- destroyed by make install
    "skills/gsd-dev-preferences/SKILL.md",
    "skills/gsd-graph/SKILL.md",               <-- destroyed by make install
    "skills/gsd-review-concurrent/SKILL.md"    <-- destroyed by make install
  ],
  "custom_count": 7,
  "manifest_found": true,
  "manifest_version": "1.10.0"
}
```

All three are named, by path, by a verb this toolchain already ships. `gsd-core/USER-PROFILE.md` is a true `USER_OWNED_ARTIFACTS` member and correctly reported. `gsd-dev-preferences/SKILL.md` is the special-cased survivor and is a benign false positive (shipped, but not under that manifest key). The `.bak-540s` files are local debris.

Two incidental facts the run surfaced: `manifest_version` is **1.10.0** while this repo tracks 1.11.0 — the installed tree is a version behind, so any pre-flight must tolerate a stale manifest; and the pre-flight would report 7 entries, most of them benign, so it must **name** them for the operator rather than refuse on a bare count.

### 4.2 So why were they destroyed? The safety net is not wired to `make install`

`backup_custom_files` and `restore_custom_files` are **steps in the `/gsd-update` workflow prose** (`gsd-core/workflows/update.md:291`, `:495-559`), not calls inside `install.js`. Grep confirms `install.js` never invokes either verb. `make install` runs `node bin/install.js --claude --global` directly, so the wipe executes with **none** of the protection the toolchain already owns.

That reframes the fix:

- The todo's **robust fix stands and is still correct**: put the three files in their real homes (`skills/gsd-review-concurrent/`, `skills/gsd-graph/`, `agents/gsd-prd-reviewer.md`) on a `local/*` branch. Once in-repo, wipe-then-replace-from-source protects them by the same mechanism as the other 71 skills. Its "do NOT patch install.js" verdict is sound.
- But **that fix is per-artifact and does not generalise.** The *next* locally-authored `gsd-*` skill is destroyed identically. The general answer is not new machinery — it is **routing `make install` through the pre-flight that already exists.**

### 4.3 Expected behaviour of a tool that installs into a directory the user also writes to

1. **Never delete without a durable copy.** `install.js` already honours this for `USER_OWNED_ARTIFACTS` via `stageUserArtifacts` → `restoreStagedUserArtifacts` (the `record.json` commit point). The `gsd-*` skills wipe honours none of it.
2. **Report what was removed.** The installer prints `✓ Removed N stale GSD skill(s)` — a count, not names. It exits 0 having destroyed work. Same failure class as the rest of this milestone: reports success while silently destroying.
3. **A prefix is not ownership.** `startsWith('gsd-')` is a naming convention the user also follows; the manifest is the actual ownership record and is already available at that call site.

**Recommended fix, in ascending cost:**

| # | Fix | Cost | Upstream-portable? |
|---|---|---|---|
| 1 | The todo's own fix — the three files into the repo | trivial | n/a (fork-local content) |
| 2 | Make `make install` run `detect-custom-files --config-dir ~/.claude`, **print the entries by name**, and refuse unless `FORCE=1` — proven above to name all three | ~10 lines in the untracked `Makefile` | fork-only, zero upstream risk |
| 3 | Name the removed entries in the installer's output instead of counting them | small | yes, single-concern PR |
| 4 | Cross-check the wipe list against `gsd-file-manifest.json` and stage anything absent from it | medium | yes, but touches the staging call tree — a separate PR |

---

## Table Stakes (the fix is wrong without these)

| Feature | Why the fix is wrong without it | Complexity | Depends on |
|---|---|---|---|
| **Build the runtime before measuring anything** (`npm run build:lib` / delete `gsd-core/bin/lib/`) | The current tree's CLI already contains a guard `src/state.cts` does not. Every before/after observation is a phantom otherwise | LOW | — |
| **Extract the guard predicate into `planning-workspace.cts`** and call it from each Class A verb | The predicate is copy-pasted at `init.cts:2926-2955` and `phase.cts:2212-2240`; `describeUnresolvedWorkstreamReason` was extracted to stop the *messages* drifting while the *predicate* was left duplicated. Adding a third copy is this repo's own **Generative Fix Divergence** anti-pattern (cited at `planning-workspace.cts:179`, `:431`) | LOW | mode-predicate decision |
| **One mode predicate** — reconcile `existsSync('.planning/workstreams')` with `listAvailableWorkstreams().length > 0` | Reproduced: guards silently disabled in a state the tool itself reports as workstream mode | MEDIUM | `workstream complete` cleanup fix |
| **`workstream complete` must not report `reverted_to_flat: true` when the directory survives** | It creates the exact state that disables the guards, and reports the opposite | LOW | — |
| **`workstream get` must use `peekActiveWorkstream`** | Executed: the primary diagnostic deletes the pointer and reports `none`, indistinguishable from "never set". The broken state becomes undiagnosable *after* the first look | LOW | `peekActiveWorkstream` (exists) |
| **Guard on `state advance-plan` uses `error()` / exit 1** | ADR-2980: a precondition refusal is a fault. Matches `phase.complete`/`init.progress` incl. typed `ERROR_REASON` | LOW | ADR-2980 (ratified) |
| **Do NOT touch `cmdStateAdvancePlan`'s existing exit-0 paths** | ADR-2980 declined normalization on measured blast radius; a sweep re-opens a closed decision | ZERO | — |
| **Machine-readable fallback field in the stdout payload** | A stderr-only warning is invisible to the agent consuming JSON; `--json-errors` does not apply to payloads | LOW | `diagnoseUnresolvedActiveWorkstream` (exists) |
| **The three local-only artifacts into the repo** | The blocker as filed; blocks port concern 4.8's routing half | LOW | — |
| **`make install` pre-flight via `detect-custom-files`** | Without it, the next locally-authored `gsd-*` artifact dies the same way. The machinery already exists and is simply unreachable from `make install` | LOW | `detect-custom-files` (exists) |

## Differentiators (worth doing, not required)

| Feature | Value | Complexity | Notes |
|---|---|---|---|
| Make `mutation` (or a new `pointer_scoped`) load-bearing in `command-aliases.cts` + a lint | Turns a decorative, unenforced table into the single source the guard reads; a new verb without a classification fails CI | MEDIUM | Must fix `workstream.progress`, add `workstream.get`/`.status` first |
| Surface `workstream_resolution` on Class B reads too | Makes the split-brain visible from `state.load` / `init.*` without any refusal | LOW | Depends on the field existing |
| Fix D-1 `quick-tasks-append` root-hardcoded STATE.md | Unconditional workstream bug, independent of the pointer | LOW | PROJECT.md target feature |
| Fix D-2 `WAITING.json` write/read split-brain | The signal is written where nothing reads it in workstream mode | LOW | Same target feature |
| Installer names removed skills instead of counting them | Turns silent destruction into a visible one | LOW | Upstream-portable single-concern PR |
| Wipe list cross-checked against `gsd-file-manifest.json` | Generalises artifact survival past named special cases | MEDIUM | Touches the staging call tree |
| A `local/` overlay convention for fork-only artifacts | Removes the class of defect rather than the instances | HIGH | Defer past v1.12 |

## Anti-Features (tempting, actively harmful)

| Feature | Surface appeal | Why problematic | Do instead |
|---|---|---|---|
| **Hoist the guard to `dispatchHostCommand` / the CLI entry** | The literal reading of "one shared precondition across three commands"; one site instead of 41 | Kills every Class C diagnostic — `workstream get`, `workstream list`, `workstream set` — at exactly the moment they are needed. The state becomes undiagnosable *and* unrepairable from the CLI | Extract the *predicate* into `planning-workspace.cts`; call it from each Class A verb |
| **stderr warning as the only fallback signal** | The todo's own first option; cheap; matches git's `advice.*` | git's docs treat advice as human-facing and tell subprocess callers to set `GIT_ADVICE=0`. This tool's caller is an agent parsing stdout JSON; `--json-errors` does not govern payloads | Named field in the payload; stderr warning as an *additional* human affordance |
| **Normalize `cmdStateAdvancePlan`'s exit-0 paths to exit 1 "for consistency"** | Mixed contract inside one function looks like a defect | Re-opens ADR-2980 with 60 sites and 170 `output` callers of blast radius. Hyrum's Law with no `/v2/` for `$?` | New guard exits 1; existing paths untouched |
| **Refuse on every Class B read** | Symmetry; "if it can misroute, refuse" | Turns a defect fix into a 25-verb behaviour change and makes the workflow unusable during exactly the failure it detects | Refuse Class A; surface on Class B |
| **Patch `install.js` to skip unknown `gsd-*` dirs** | Directly stops the deletion | The todo is right: wipe-then-replace-from-source is correct behaviour; the defect is that the three files were never in the source. Skipping unknown dirs strands genuinely stale artifacts forever | Files into the repo + `make install` pre-flight |
| **Add the three artifacts to `USER_OWNED_ARTIFACTS`** | An allowlist already exists and already saves `gsd-dev-preferences` | Perpetuates the named-special-case pattern the todo correctly identifies as "not a general protection", and `USER_OWNED_ARTIFACTS` is scoped inside `gsd-core/`, not to sibling `skills/`/`agents/` | Manifest-based detection, which already covers those dirs |
| **A new "is this verb safe" registry** | Clean; explicit | A third source of truth alongside `mutation` and the resolver. This repo's Generative Fix Divergence pattern, again | Reuse `mutation`, or derive from the resolver |

## Feature Dependencies

```
Build the runtime before measuring
    └──gates──> every empirical step in the workstream cluster

Reconcile the mode predicate
    └──requires──> workstream complete: don't lie about reverted_to_flat
                       (that bug creates the state the predicate must handle)
    └──enables──> Extract the shared guard predicate
                       └──enables──> Guard on Class A verbs (41)
                                          └──requires──> exit-1 fault contract (ADR-2980, already ratified)

diagnoseUnresolvedActiveWorkstream (exists)
    └──enables──> workstream_resolution payload field
                       └──enables──> Surface on Class B reads
                       └──enables──> workstream get uses peek (reports WHY, not just null)

detect-custom-files (exists)  ──enables──> make install pre-flight
Three artifacts into the repo ──unblocks──> port concern 4.8 routing half

Class D path fixes (quick-tasks-append, WAITING.json)
    ──independent of──> the guard work    (a guard cannot fix a hardcoded path)
```

## MVP Definition

### Launch with (v1.12)

- [ ] Build-before-measure step — every other verification is untrustworthy without it
- [ ] One mode predicate + `workstream complete` cleanup honesty — the guards are currently defeatable
- [ ] Shared guard predicate extracted into `planning-workspace.cts`, applied to Class A `state.*` + `phase.*` + `roadmap.*` writers
- [ ] `error()` / exit 1 on the new guard; existing exit-0 paths untouched
- [ ] `workstream_resolution` named field on the affected verbs
- [ ] `workstream get` → `peekActiveWorkstream` + report the reason
- [ ] Three local-only artifacts into the repo
- [ ] `make install` pre-flight via `detect-custom-files`

### Add after validation (v1.12.x)

- [ ] Class A tail: `config-*`, `template.fill`, `scaffold`, `todo.complete`, `estimate-calibrate`, `audit acknowledge`
- [ ] `workstream_resolution` on Class B reads
- [ ] D-1 / D-2 path fixes
- [ ] Installer names what it removed

### Future consideration (v1.13+)

- [ ] `mutation` / `pointer_scoped` made load-bearing with a CI lint
- [ ] Manifest-driven wipe in `install.js` (upstream PR, own blast radius)
- [ ] `local/` overlay convention

## Feature Prioritization Matrix

| Feature | Value | Cost | Priority |
|---|---|---|---|
| Build-before-measure | HIGH | LOW | P1 |
| One mode predicate + `reverted_to_flat` honesty | HIGH | MEDIUM | P1 |
| Extracted guard predicate + Class A `state`/`phase`/`roadmap` | HIGH | MEDIUM | P1 |
| exit-1 fault contract on the new guard | HIGH | LOW | P1 |
| `workstream_resolution` payload field | HIGH | LOW | P1 |
| `workstream get` → peek | HIGH | LOW | P1 |
| Three artifacts into the repo | HIGH | LOW | P1 |
| `make install` pre-flight | HIGH | LOW | P1 |
| Class A tail (config/template/scaffold/todo/estimate/audit) | MEDIUM | MEDIUM | P2 |
| `workstream_resolution` on Class B | MEDIUM | LOW | P2 |
| D-1 / D-2 path fixes | MEDIUM | LOW | P2 |
| Installer names removals | MEDIUM | LOW | P2 |
| `mutation` load-bearing + lint | MEDIUM | MEDIUM | P3 |
| Manifest-driven wipe | MEDIUM | HIGH | P3 |
| `local/` overlay | LOW | HIGH | P3 |

## Sources

**In-repo primary (HIGH confidence — read directly at the cited line):**
- `src/planning-workspace.cts` — `planningDir` `:124`, `listAvailableWorkstreams` `:151`, `planningPaths` `:185`, `peekActiveWorkstream` `:396`, `diagnoseUnresolvedActiveWorkstream` `:420`, `describeUnresolvedWorkstreamReason` `:432`
- `src/active-workstream-store.cts` — `resolveFromChain` `:300`, `diagnoseUnresolvedActiveWorkstream` `:340`, `getActiveWorkstream` `:358`, `peekActiveWorkstream` `:375`
- `src/workstream.cts` — flat-mode definition `:77`, `cmdWorkstreamComplete` cleanup `:334-338`, `cmdWorkstreamGet` `:377`, #2562 surfacing comment `:238-241`
- `src/init.cts` — #1912 guard `:2926-2955`, `WAITING.json` root read `:2526`
- `src/phase.cts` — #2028 guard `:2200-2240`
- `src/state.cts` — `cmdStateAdvancePlan` `:656`, `cmdSignalWaiting` `:3792`, plus the 19 Class A entries in the table
- `src/command-aliases.cts` — the `mutation` metadata (`STATE_/PHASE_/INIT_/ROADMAP_/NON_FAMILY_COMMAND_ALIASES`)
- `src/workstream-inventory.cts:408-435` — `writeVerificationLedger`
- `src/io.cts:246` — `error()` → stderr + `process.exit(1)`, with typed `extra`
- `bin/install.js:9355` (`MANIFEST_NAME`), `:10819-10829` (the `gsd-*` skills wipe)
- `gsd-core/bin/gsd-tools.cjs:1148` (`quick-tasks-append`), `:2544-2628` (`detect-custom-files`), `:2633+` (`restore-custom-files`), `:4131-4155` (CLI workstream bootstrap)
- `src/install-engine.cts:91` (`USER_OWNED_ARTIFACTS`), `src/user-artifact-staging.cts` (durable staging)
- `gsd-core/workflows/update.md:291`, `:495-559` — where `backup_custom_files` / `restore_custom_files` actually run

**In-repo ratified decisions (HIGH):**
- `docs/adr/2980-payload-carried-error-is-a-degraded-result.md` (Accepted, 2026-08-09)
- `docs/json-errors.md` — "Degraded results vs faults"

**Executed reproductions (HIGH — run 2026-08-24 in throwaway trees under `$TMPDIR`):**
- Empty-`workstreams/` disagreement: `workstream complete` reporting `reverted_to_flat: true` while the directory survives; `workstream get` → `mode: workstream` vs `listAvailableWorkstreams()` → `[]`; `init.progress` proceeding on root data
- `workstream get` deleting the session pointer file under a dangling pointer and reporting `none`
- Stale build: `gsd-core/bin/lib/state.cjs` carrying a guard absent from `src/state.cts`
- `node gsd-core/bin/gsd-tools.cjs detect-custom-files --config-dir "$HOME/.claude"` (read-only) naming all three lost artifacts

**External (MEDIUM — official docs/source, fetched 2026-08-24):**
- git `advice.*` — <https://github.com/git/git/blob/master/Documentation/config/advice.adoc> (primary source, read verbatim; rendered as the `advice.*` section of <https://git-scm.com/docs/git-config>)
- kubectl — <https://github.com/kubernetes/kubectl/blob/master/pkg/cmd/config/use_context.go>; <https://github.com/kubernetes/client-go/blob/master/tools/clientcmd/validation.go>
- terraform — <https://developer.hashicorp.com/terraform/cli/commands/workspace/select> (2025-11-19); <https://developer.hashicorp.com/terraform/cli/workspaces>

---
*Feature research for: v1.12 defect-fix milestone, faffi fork of gsd-core*
*Researched: 2026-08-24*
