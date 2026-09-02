# Project Research Summary

**Project:** gsd-core (faffi fork) — milestone v1.12 "Fix the blockers, finish the port campaign"
**Domain:** Defect repair in a mature, heavily-tested TypeScript/Node CLI toolchain that is also a fork feeding single-concern PRs upstream
**Researched:** 2026-08-24
**Confidence:** HIGH

> **This is a defect-fix milestone.** 22 captured todos, no new product features. "Features"
> throughout means *correct expected behaviour* — what the fix must restore — not new scope.
> The roadmap question is therefore **sequencing and prevention placement**, not feature selection.

---

## Adjudications carried forward (do not re-open)

The four research files disagree in three places. The orchestrator adjudicated each against the
evidence. These verdicts are binding on the roadmap; a 2-of-4 majority does **not** override them.

### ADJ-1 — the workstream-mode predicate. ARCHITECTURE is right; FEATURES is superseded.

FEATURES §1.1 recommends widening the guard to `fs.existsSync('.planning/workstreams')`.
**That recommendation is superseded.** Both files reproduced a real trigger and each saw only half
the space:

| Trigger | Mechanism | `existsSync` reads | Guard fires today? |
|---|---|---|---|
| **T1 — directory removed** (ARCHITECTURE §C2) | `cmdWorkstreamComplete` `src/workstream.cts:337` `rmdirSync(wsRoot)` removes `.planning/workstreams/` on the last completion | **false** — in the exact case that produces the bug | no |
| **T2 — directory survives holding only a dotfile** (FEATURES §1.1) | `.DS_Store` present → `rmdirSync` throws `ENOTEMPTY` into `catch { /* ignore */ }` → directory survives with zero subdirectories | true | no |

Both triggers produce `listAvailableWorkstreams(cwd).length === 0`, which is what disarms the guard.
`existsSync` covers T2 and is **false exactly in T1**. The predicate that covers both, and the one
the roadmap must carry:

```
inWorkstreamFailSafeScope  ==  listAvailableWorkstreams(cwd).length > 0
                               || diagnoseUnresolvedActiveWorkstream(cwd).present
```

It is a **monotone disjunction** — strictly additive, it can only add firing, never remove it — so
no currently-green test can turn red by construction. Verified against seven scenarios
(ARCHITECTURE §Q1); two rows flip from `false` to `true` (`workstreams/` empty + dangling pointer;
`workstreams/` absent + dangling pointer) and five are unchanged.

**Both T1 and T2 are in scope.** FEATURES' `.DS_Store` path is a real second trigger and must not
be dropped because its recommended predicate was rejected — it carries its own defect
(`reverted_to_flat: true` reported about a directory that still exists) which no predicate change
repairs.

**One unmeasured cell, flagged rather than assumed:** no research file called
`diagnoseUnresolvedActiveWorkstream` in the post-`.DS_Store` state. The closest evidence is
ARCHITECTURE's end-to-end T1 repro, which measured `shared marker file exists? YES -> 'solo'`
(`cmdWorkstreamComplete:302-303` clears through **one** adapter only), so the marker most likely
survives and the disjunction fires on T2 as well. Treat this as a **phase verification item**, not
a coverage gap.

### ADJ-2 — the shell-lint substrate. STACK's final revision is authoritative.

**`web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1`, NOT `sh-syntax`.** An earlier draft of
STACK.md recommended `sh-syntax`; a stale copy survives at
`.planning/.cache/research-backup/STACK.md.orig` — **ignore it entirely**. Recorded here so a later
phase does not re-derive the rejected option.

Carry the *reasons* precisely — a summariser that records "rejected for lacking zsh" would be
propagating a falsehood:

- **`sh-syntax` is rejected because its JSON AST is positional-only.** Measured: parsing `echo foo`
  yields `Stmt.Cmd === { Pos, End }` — no node type, no `Args`, `Word.Lit === ""`. No lint rule is
  expressible against it. It **does** parse zsh (mvdan/sh v3.13.0, 2026-03-09, added `LangZsh`;
  `sh-syntax@0.6.0` pins v3.13.1 and exposes `LangVariant.LangZsh === 16`, measured). It remains
  the only Node-reachable zsh 5.9 *validator*; it is not a rule substrate.
- **`shellcheck` is rejected on two independent kills.** (i) No zsh dialect in any release —
  `-s` accepts `sh`, `bash`, `dash`, `ksh`, `busybox`; the CHANGELOG records *"Zsh support has been
  removed."* (ii) Structurally blind even if zsh returned: **all six/seven mechanisms are valid,
  correct bash**, and shellcheck is a fixed rule set with no way to add "this correct bash behaves
  differently under zsh."
- **A bash-only PARSER is correct even though a bash-only LINTER is not.** The parser's only job is
  to locate `${ARR[0]}` / `BASH_REMATCH` / `read -ra` / `PIPESTATUS` / glob-array assignment /
  bare `$VAR` in a `for` word-list / `grep -oP` in the source. Every one of those is written in bash
  and appears in the bash parse. The knowledge that zsh 1-indexes, populates `$match`, aborts on
  NOMATCH and rejects `read -a` lives in the **rule**. A zsh grammar would add nothing.

### ADJ-3 — build output currently lies, and this gates all empirical work.

ARCHITECTURE §C1 and FEATURES §0 found this independently: `gsd-core/bin/lib/state.cjs` contains an
`advance-plan` workstream guard that `src/state.cts` does **not** have. It is gitignored build
output left from compiling the unmerged WIP branch `local/state-advance-plan-fallback-fix`
(`f72f1534`, whose own message says *"KNOWN INCOMPLETE, 1 test RED … do not port upstream as-is"*),
and `gsd-core/bin/ensure-runtime-build.cjs` rebuilds it **only when absent**.

Executed proof: with a dangling pointer, `node gsd-core/bin/gsd-tools.cjs query state advance-plan`
printed the guard error and exited 1, while the source it is supposedly built from has no such guard.

**Any before/after measurement in this tree measures a phantom.** `npm run build:lib` (or deleting
`gsd-core/bin/lib/`) MUST be the first task of the first phase. This is a hard sequencing
constraint, not advice.

---

## Executive Summary

This milestone repairs 22 captured defects in a fork of gsd-core, and all four research streams
converged on the same meta-finding: **these are not 22 unrelated bugs — they are instances of one
shape.** A verification surface (a test, a guard, a count, a reported field, an issue tracker)
reports on a *proxy* for the thing that matters, and the proxy agrees with reality in every case
anyone has looked at. The fence test executes under `bash`, a proxy for the login shell (`/bin/zsh`,
5.9, measured). The workstream guard counts *directories*, a proxy for "a workstream is in play."
`workstream complete` reports `reverted_to_flat` from what it *attempted*, a proxy for what the
filesystem now holds. The subprocess timeout bounds *one PID*, a proxy for the process tree.
Upstream's tracker records *symptoms*, a proxy for causes — which is how the same fence defect
survived four fix rounds (#2770 → #2962 → #3300 → #3409), each shipping green. Every prevention
below is one move: **replace the proxy with a direct observation, and make the harness run where the
code runs.**

The recommended approach is therefore **instruments before repairs**. Four items fix no reported
defect and must land first: rebuild `gsd-core/bin/lib/` so the CLI stops disagreeing with `src/`
(ADJ-3); fix the orphaned-grandchild leak before the spawn seam is asked to carry double load;
parameterize the fence harness over `{bash 3.2.57, zsh 5.9}` and expect it to go **RED** against the
11 unfixed sites — that redness is the deliverable; and land the installer/local-artifact fix so the
work survives `make install`. Only then does repair begin: one extracted `requireResolvedWorkstream`
predicate in `src/planning-workspace.cts` (ADJ-1) applied to the 41 pointer-resolved mutating verbs,
a conditional `workstream_resolution` notice on the universal `output()` seam for the read verbs,
then the STATE.md write path, then the fence sites and their ratchet lint, then the workflow-markdown
routing sweep, then the port campaign remainder. Two devDependencies are the entire dependency delta
(ADJ-2); everything else is stdlib or already declared.

The dominant risks are all "looks done but isn't." A fence fix verified under bash proves nothing
about the shell that runs it. A guard fixed in place at each call site produces the (N+1)th copy —
this codebase has a name for that, **DEFECT.GENERATIVE-FIX**, and three copies of a wrong rule is
this milestone's headline defect. An isolation flag shipped without a survivor assertion regresses
silently at the next refactor; the assertion *is* the deliverable. A guard tightened without a
characterization test cannot be distinguished from a regression by the agents that call these verbs
unattended. And the single likeliest wrong turn is structural: PROJECT.md's own wording — *"one
shared precondition across `state advance-plan`, `init.progress` and `phase.complete`"* — reads as an
invitation to hoist the guard into `dispatchHostCommand`. Both FEATURES and ARCHITECTURE reject that
independently: it kills every structurally-immune diagnostic (`workstream get`, `list`, `set`) at
exactly the moment they are needed, leaving the broken state both undiagnosable and unrepairable
from the CLI. Extract the **predicate**; call it from each mutating verb.

---

## Key Findings

### Recommended Stack

**Two of the three tooling questions need zero new dependencies. One needs two devDependencies,
both MIT, both dev-only.** The existing stack (`src/*.cts` → `gsd-core/bin/lib/*.cjs`, Node >=24,
`node:test`, ESLint + `local/*` AST rules) is not under review and is not proposed for replacement
anywhere.

| Question | Verdict | New dependency |
|---|---|---|
| Shell-fence portability | Split: execution harness = none; static lint = a real bash CST parser | `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1` (dev only) |
| Subprocess lifecycle | Stdlib only — the correct answer is "do not create a process tree", not "kill one" | none |
| CI blindness / invariant deletion | Three layers, all from packages already in `devDependencies` | none |

**Core technologies:**

- **`web-tree-sitter@0.26.13`** — pure-WASM tree-sitter runtime. MIT, **zero dependencies**, no
  native build, dual CJS/ESM (`exports.require` → `web-tree-sitter.cjs`), so a `.cjs` lint script can
  `require()` it. Verified working in this tree.
- **`tree-sitter-bash@0.25.1`** — the bash grammar. MIT; ships a prebuilt **`tree-sitter-bash.wasm`
  (1.36 MB)** inside the npm tarball, which is the only file consumed. **Never
  `require('tree-sitter-bash')`** — that path is the native binding and pulls `node-addon-api` +
  `node-gyp-build` into a real compile on three CI OSes including `windows-latest`. Load the `.wasm`
  by path.
- **`--test-isolation=none`** (stdlib, Node ≥23.6.0, well under the `engines.node >=24` floor) —
  added to `buildNodeTestArgs` at `src/prohibition-enforcement.cts:220-222`. Removes the extra
  process level rather than chasing it, so the hang runs in the direct child that `execFileSync`'s
  `timeout` actually signals.
- **Already declared, no install:** `espree ^10.4.0` (invariant-title lock), `fast-check ^4.8.0`
  (strengthen `arbGraph`), `@stryker-mutator/core ^9.6.1` (graphify mutation shard),
  `node:test` + `child_process` (stdlib).

**Measured evidence — 1,052 shell-tagged fences from 431 files** (`agents/`,
`gsd-core/workflows/**`, `gsd-core/references/`, `commands/**`, `skills/**`), each written to a temp
file and parse-checked:

| Parser | Parsed | Rate |
|---|---|---|
| `/bin/bash` 3.2.57 (macOS system bash) | 1035 / 1052 | 98.4% |
| `/bin/zsh` 5.9 | 1033 / 1052 | 98.2% |
| `/bin/sh` | 1031 / 1052 | 98.0% |
| `sh-syntax@0.6.0` `LangBash` / `LangZsh` | 1027 / 1030 | 97.6% / 97.9% |
| `web-tree-sitter` + `tree-sitter-bash`, no `ERROR` node | **1033 / 1052** | **98.2%** |

All 17 `bash -n` failures are illustrative pseudo-code (`<files the fix touched>` placeholder argv,
`Task(subagent_type=…)` tool-call syntax), not executable fences. Of the 8 fences `sh-syntax` rejects
that `bash -n` accepts, **6 are `${a.b}`-shaped prompt interpolation** — which is
**ADR-3409's entire stated blocker, measured at 6 of 1052 fences (0.6%)**. A 0.6% enumerable
exclusion list is a config constant, not grounds for rejecting a parser. **ADR-3409's premise is
empirically overstated and should be amended in this milestone**, alongside the lint, so the next
round does not re-derive the same rejection.

*(Note: 1,052 is STACK's fence count measured today across shell-tagged fences. The todo's own
exhaustive sweep cites 1,048 fences / 6,413 lines. Two different exercises, two counts — carried
separately rather than blended.)*

**All seven rule shapes are directly expressible in the CST** — measured node-by-node against the
real defect shapes: `${ARR[0]}` yields `expansion → subscript` with a **named field `index:` typed
`number`**, distinguishable from `${_CTX[@]}` whose `index:` is `(word)` «@»; `BASH_REMATCH` and
`PIPESTATUS` yield `subscript name: (variable_name)` with exact text; `read -ra` and `grep -oP`
yield `command name: (command_name) argument: (word)`; NOMATCH-abort yields a `variable_assignment`
whose `value:` is an `array` containing a glob `word`; and word-splitting on a bare `$VAR` yields
`for_statement value: (simple_expansion (variable_name))`, **structurally distinct** from
`(command_substitution)` — which is what keeps the six retracted `$(…)` sites retracted.

**Known limits, to state in the ADR rather than discover in a phase:** `Parser.init()` and
`Language.load()` are async, so the lint's home is `scripts/lint-*.cjs`, **not** an ESLint rule
(`create()` is synchronous); tree-sitter *recovers* rather than throws, so `rootNode.hasError` means
"needs a human", never an automatic violation; the ~19 pseudo-code fences must be an explicit
enumerated exclusion list, not a wildcard skip.

**Bonus finding — a seventh mechanism (M7).** `grep -oP` / `grep -P` at **5 shipped-fence sites**
(`gsd-core/workflows/pause-work.md:18,21,24`; `sync-skills.md:33,40`). `-P` is a GNU grep extension;
**BSD grep on macOS rejects it**, so the captured variable is silently empty — the same
fails-in-the-safe-looking-direction shape as M1–M6, and precisely the class
`scripts/lint-portable-timeout.cjs` (#2351) exists to ban.

**Headline do-NOT-add:** `shellcheck` (ADJ-2); `sh-syntax` / `mvdan-sh` (ADJ-2); `bash-parser`
(unmaintained since 2017); `tree-sitter-bash`'s native binding; any regex-per-mechanism lint
(directly against ADR-1703); `tree-kill` / `ps-tree` / `execa` (all need an async call site — see
below); a new coverage tool (`c8` is present and **line coverage cannot see a deleted assertion**).

**Q2's decisive constraint, which also decides the deferred sweep:** `detached` is **not a
documented option** for `spawnSync` or `execFileSync` — it is documented only for `spawn()` and
`fork()`. `process.kill(-pid)` requires a process-group leader, which only `detached: true` creates.
`options.signal` is async-only. Node documents the leak itself: *"On Linux, child processes of child
processes will not be terminated when attempting to kill their parent."* Windows has no documented
answer at all. **At a synchronous call site there are exactly two cures: remove the tree, or convert
to async.** For every site the deferred sweep finds, that is the whole question — there is no third
option and no library that supplies one.

### Expected Features (correct behaviour to restore)

#### The four-class verb classification — the milestone's main scoping instrument

The classification key is the **path-resolution mechanism at the call site**, because that is the
defect mechanism. The lead's original framing (*"MUTATING should refuse, READING must not"*) is
disproved by the codebase's own two guards: `init.progress` is `mutation: false` and **refuses**
today; `workstream.progress` is `mutation: true`, genuinely **writes** (`writeVerificationLedger`),
and **cannot misroute** because it enumerates by name from `planningRoot`. Mutation is the wrong
axis; **pointer-resolution is the right one.**

| Class | Definition | Count | Verdict |
|---|---|---|---|
| **A — pointer-resolved MUTATING** | Output path from `planningDir()` / `planningPaths()`, which read `process.env.GSD_WORKSTREAM`. A wrong resolution writes *a different file than the caller named* | **41 verbs** (`state.*` alone is 19) | **MUST REFUSE** |
| **B — pointer-resolved AUTHORITATIVE READ** | Same resolver, no write, but the output drives a downstream decision (workflow routing, phase selection, gate verdicts) | **≈25 verbs** | **CONTESTED BAND** — do not refuse in v1.12; surface the fallback instead |
| **C — root-scoped / structurally immune** | Resolves only via `planningRoot()`, or enumerates workstreams by name. Cannot misroute | the **seven `workstream` verbs** (`get`, `list`, `status`, `progress`, `set`, `create`, `complete`) + `init.map-codebase` + shared-root readers | **MUST NEVER REFUSE** |
| **D — hardcoded root path** | Bypasses the resolver entirely (`path.join(cwd, '.planning', …)`). Wrong in workstream mode *unconditionally*, pointer or no pointer | 3 sites | **A guard cannot reach these** — separate path fixes |

Every Class A row was verified by reading the resolving call in the function body; none is inferred.
Two carry caveats that do not move them out of Class A: **`config-set`** writes the workstream copy
*correctly by design* (`config-loader.cts:672-712` overlays workstream config on a root base), so a
misroute silently promotes a workstream-local setting to the project-wide config every workstream
inherits — a *higher*-severity member than its name suggests. **`todo.complete`** and all six other
todo sites resolve `todos/` through `planningDir`, so a misroute writes the root `todos/completed`.

**Class C is the answer to the diagnosability question.** The seven `workstream` verbs never consult
`planningDir` — they are structurally immune. The undiagnosability risk materialises **only if the
guard is hoisted** to the dispatcher.

Class D sites: **D-1** `quick-tasks-append` (`gsd-core/bin/gsd-tools.cjs:1148`) always writes root
`STATE.md` even when a workstream resolves correctly; **D-2** `WAITING.json` split-brain —
`state.signal-waiting` **writes** to `planningDir(cwd)/WAITING.json` (`state.cts:3793`) while
`init.progress` **reads** `path.join(cwd, '.planning', 'WAITING.json')` (`init.cts:2526`), so in
workstream mode the signal is written where nothing reads it; **D-3**
`hooks/gsd-context-monitor.js:133` concludes GSD is inactive when root `STATE.md` is absent.

**Do not adopt `command-aliases.cts`'s `mutation` field as the guard predicate.** It is unenforced —
its only consumer anywhere is a `typeof entry.mutation === 'boolean'` assertion at
`tests/commands.test.cjs:4021` — and it carries four disagreements and two absences across ~120
aliases (`state.complete-phase`, a mutating verb, is absent from `STATE_COMMAND_ALIASES` entirely;
`phases.archive` is declared but the router refuses to route it). Making it load-bearing is a
**differentiator for v1.13+**, not the v1.12 mechanism.

**Must have (table stakes — the fix is wrong without these):**

- **Build the runtime before measuring anything** — ADJ-3. Every other verification is untrustworthy.
- **One mode predicate** — ADJ-1's monotone disjunction, replacing two claimed sources for one
  concept (`listAvailableWorkstreams`'s docstring claims to be the "single source of truth" while
  `workstream.cts:77` already defines it differently).
- **Extract the guard predicate into `planning-workspace.cts`** and call it from each Class A verb.
  It is copy-pasted at `init.cts:2926-2955` and `phase.cts:2212-2240`;
  `describeUnresolvedWorkstreamReason` was extracted to stop the *messages* drifting while the
  *predicate* was left duplicated. A third copy is DEFECT.GENERATIVE-FIX.
- **`workstream complete` must not report `reverted_to_flat: true` when the directory survives** —
  derive the field from a post-operation observation, not from what was attempted.
- **`workstream get` must use `peekActiveWorkstream`.** Executed: `cmdWorkstreamGet` calls the
  *mutating* `getActiveWorkstream`, so the primary diagnostic **deletes the pointer on first
  invocation** and reports `active: null` — byte-identical to "nothing was ever set". The broken
  state becomes undiagnosable *after the first look*. `peekActiveWorkstream` exists for exactly this
  (added by #3579) and is simply not used here.
- **The new guard uses `error()` / exit 1** with a typed `ERROR_REASON`. Already sanctioned by
  ADR-2980 and matching `phase.complete` / `init.progress`; a precondition refusal is a fault, not a
  degraded result.
- **Do NOT touch `cmdStateAdvancePlan`'s existing exit-0 paths** — ADR-2980 declined normalization on
  measured blast radius (60 sites, nine modules, 170 direct `output` callers, *"no `/v2/` for `$?`"*).
- **Machine-readable fallback field in the stdout payload**, reusing
  `diagnoseUnresolvedActiveWorkstream`'s exact `{ present, value, reason }` shape so it cannot drift
  from the resolution predicate.
- **The three local-only artifacts into the repo** (`skills/gsd-review-concurrent/`,
  `skills/gsd-graph/`, `agents/gsd-prd-reviewer.md`).
- **`make install` pre-flight via `detect-custom-files`** — the machinery already exists and is
  simply unreachable from `make install`.

**Should have (differentiators):** `workstream_resolution` surfaced on Class B reads too; D-1 and
D-2 path fixes; the installer naming what it removed instead of counting it
(`✓ Removed N stale GSD skill(s)` — a count, not names, exiting 0 having destroyed work).

**Defer (v1.12.x / v1.13+):** the Class A tail (`config-*`, `template.fill`, `scaffold`,
`todo.complete`, `estimate-calibrate`, `audit acknowledge`); making `mutation` / a new
`pointer_scoped` load-bearing with a CI lint; a manifest-driven wipe in `install.js` (upstream PR
with its own blast radius); a `local/` overlay convention for fork-only artifacts.

**The local-artifact diagnosis needs one correction.** The claim that the installer "has no notion of
user content" is not accurate — the repo already ships three of the four protection patterns
(`gsd-file-manifest.json`, per-entry checksums + `saveLocalPatches`, and
`detect-custom-files` / `restore-custom-files` with never-clobber semantics). **The safety net is
simply not wired to `make install`**: `backup_custom_files` / `restore_custom_files` are steps in the
`/gsd-update` **workflow prose**, and `install.js` never invokes either. Executed read-only against
the live installed tree, `detect-custom-files --config-dir "$HOME/.claude"` returned 7 entries and
**named all three lost artifacts by path**. Two incidentals from that run: `manifest_version` is
**1.10.0** while the repo tracks 1.11.0, so a pre-flight must tolerate a stale manifest; and most of
the 7 entries are benign, so it must **name** them rather than refuse on a bare count.

**External corroboration (each read at primary source):** kubectl is the decisive citation *for* a
typed field — it refuses at the setting boundary (`config use-context` → *"no context exists with
the name: %q"*) **and** exports `IsContextNotFound(err) bool` so consuming callers branch
programmatically rather than grepping prose. git is the decisive citation *against* a stderr-only
warning, in its own words: advice messages *"are intended to help human users… output to the
standard error"* and subprocess callers are told to set `GIT_ADVICE=0` to squelch them. This tool's
caller is an agent parsing stdout JSON — exactly the case git's docs tell you not to signal through.
Terraform's `workspace select` requires the workspace to exist and gates creation behind an opt-in
`-or-create` flag; what happens when a *selected* workspace later disappears is **undocumented** and
is not asserted here.

### Architecture Approach

Three seams already exist; none is being introduced. **Seam A** — workstream resolution
(`src/active-workstream-store.cts`): `resolveActiveWorkstream` over an adapter chain, with three
read variants that share `resolvesToExistingWorkstream` so they *cannot* disagree —
`getActiveWorkstream` (self-heals), `peekActiveWorkstream` (never clears),
`diagnoseUnresolvedActiveWorkstream` (read-only, reports *why*). **Seam B** — path composition
(`src/planning-workspace.cts`): `planningDir(cwd, ws?)` reads `process.env['GSD_WORKSTREAM']` when
`ws` is undefined; everything downstream composes from it. **Seam C** — CLI entry bootstrap
(`gsd-core/bin/gsd-tools.cjs:4136-4157`): resolves once with `getStored: peekActiveWorkstream`
(deliberate, per #3579 — a 14-line comment explains the bootstrap is *"a check, not the consuming
read"*), then injects `GSD_WORKSTREAM` before dispatch.

**The defect's shape:** Seam C resolves a dangling pointer to `null`, does not set
`GSD_WORKSTREAM`, and Seam B therefore composes root `.planning/`. **Nothing between them records
that a pointer was named and did not resolve.** The two guards are a per-command patch over a gap in
the seam.

**Major components:**

1. **`requireResolvedWorkstream()`** — NEW, exported from `src/planning-workspace.cts` adjacent to
   `describeUnresolvedWorkstreamReason`. Owns `listAvailableWorkstreams`, the resolution, the ADJ-1
   disjunction, the two-arm branch, both message templates and both `ERROR_REASON` codes. Each call
   site collapses from ~30 lines to one; per-verb strings stay parameters so no message text is lost.
   **This is conformance, not scope creep** — the same file already holds four instances of the
   pattern (`quickDirFrom` #2142, `findContextMdIn` #3739, `describeUnresolvedWorkstreamReason`
   #3579, and `listAvailableWorkstreams` itself, *already extracted for these two guards, for this
   reason*). The extraction was simply drawn at the wrong boundary — it factored out the *list* and
   left the *predicate* duplicated.
2. **`setWorkstreamResolutionNotice()` + a conditional field on `output()`** — NEW, in `src/io.cts`
   near the existing `setJsonErrorMode` process-flag pattern. **`output()` (`src/io.cts:144-165`) is
   the seam**: every verb's JSON crosses it and there is no competing universal decorator
   (`withProjectRoot` is init-local — 30 uses in `init.cts`, 2 in `docs.cts`, zero elsewhere).
   Capture **non-resolution, not clearing**: the entry no longer clears (#3579), and a dangling
   *shared marker* read as a fallback is never cleared but is exactly as dangerous.
3. **`detectShells()` helper** — NEW in `tests/helpers/`, lifted from
   `tests/review-build-prompt-optional-sections.test.cjs:52-62` (bash unconditional, zsh probed and
   skipped where absent). `tests/unreachable-shell-guard.test.cjs:149` consumes it, parameterizing
   over `SHELLS`. `runHook`'s `interpreter` is **already an explicit parameter** documented as
   *"EXPLICIT, never inferred"* — no seam change needed.
4. **`scripts/lint-portable-glob-guard.cjs` / `lint-shell-fence-portability.cjs`** — NEW, mirroring
   `scripts/lint-unreachable-guard-drift.cjs:374` (four scan dirs, zero baseline, no allowlist
   escape) and reusing `scripts/lib/drift-scan.cjs` for the tree walk, per ADR-3409 Decision 3
   (*"a guard that copies the scanner turns the family into the ad hoc engine"*). **It must operate
   per-fence, not per-file** — `complete-milestone.md` has a shim at `:331` protecting a loop at
   `:335` while the glob-array at `:369` is a *different fence* and unprotected; a file-level
   "has the shim?" check gives a false pass.

**Patterns to follow:** extract the *predicate*, not just the data; give every new resolution
question a read-only diagnostic sibling rather than a re-derivation; ship ratchet lints with their
fix (#2351 precedent); keep tests bound to the shipped artifact (extracting live fences from shipped
`.md` is right — only the interpreter is wrong).

**Anti-patterns named in the codebase itself:** DEFECT.GENERATIVE-FIX; testing against a shell
nobody runs; **fixing by imitation** — `gsd-tools.cjs:1166-1167` justifies itself by citing
`cmdStateAddBlocker` and `cmdStateAddDecision` as exemplars, and **both cited exemplars carry the
defect**; fail-safes at the dispatcher.

**PR decomposition (one concern each):** PR-A = helper extraction + corrected precondition at the two
live sites + a regression test for the empty/absent case (type `Fixed`). PR-B = apply to
`state advance-plan`; supersedes WIP `f72f1534`; do not bundle. PR-C = `cmdWorkstreamComplete`
clearing the adapter it actually resolved from — the *generator* of the dangling state; a fix here
reduces how often the guard is needed but does not replace it (renames and manual archives still
dangle pointers).

### Critical Pitfalls

PITFALLS assigns each pitfall to a **phase topic**, and three of them constrain phase *order* rather
than phase content. Those assignments are preserved verbatim in the phase table below — the point is
to build prevention **into** phases, not bolt it on at review.

1. **The harness diverges from production in exactly the dimension under test** (Pitfall 1 —
   *ordering constraint*, phase topic: **Cross-shell test harness**). `unreachable-shell-guard.test.cjs`
   extracts live fences from shipped `.md` — the right instinct — then runs them under a hardcoded
   `interpreter: 'bash'`. Production runs them under the login shell (measured this session:
   `$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset). **57 call sites across `tests/` pass
   `interpreter: 'bash'`.** The repo already contains the contradiction in writing:
   `tests/policy-shell-pinning.test.cjs` enforces `shell: zsh` on macOS CI jobs. Sharpest evidence:
   **CI already runs three `macos-latest` shards with `shell: 'zsh {0}'` (`test.yml:452-462`) and is
   still blind** — that sets the shell for the CI *step*; the test then explicitly spawns bash.
   *Avoid:* parameterize the fence harness only (not all 57 sites — that violates one-concern-per-PR
   and doubles CI), and **prove the harness can fail** — RED under zsh on the unfixed fence, GREEN
   under bash. A cross-shell harness green on both before the fix is measuring nothing.
2. **N copies of a guard share one untested precondition — and the site with *no* copy is worse**
   (Pitfall 2 — *ordering constraint*, phase topic: **Workstream fail-safe precondition**). Two
   copies (`init.cts:2926`, `phase.cts:2212`, the latter commented *"Mirror the #1912 guard"* — a
   clone announcing itself) plus `cmdStateAdvancePlan` with **no precondition at all**, which is
   *why* `advance-plan` is the verb that silently falls through to root. Juergens et al., ICSE 2009,
   assessed ~900 clone groups and confirmed **107 developer-acknowledged faults** from inconsistent
   changes, naming the *inconsistent bug fix* as the most dangerous shape. *Avoid:* **extract before
   you fix**; test the predicate as a contract over a `[3 call sites] × [5 pointer states]` matrix,
   asserting the **`ERROR_REASON` code**, not prose.
3. **A swallowed cleanup failure composed into a later correctness decision** (Pitfall 3, phase
   topic: **Workstream fail-safe precondition** — same phase, because the two defects compose).
   Measured: with a single `.DS_Store` in `wsRoot`, `rmdirSync` throws **`ENOTEMPTY`**, the throw is
   swallowed, the directory survives — while the count that decided the outcome is **0**. The defect
   is **not the swallow** — cleanup paths are the documented exception (Chen, *"Since clean-up
   functions can't fail, you have to soldier on"*) and `eslint.config.mjs` sets
   `allowEmptyCatch: true` in three places, so a lint change is maintainer-owned config and a
   **separate concern**. The defect is that a swallowed cleanup failure became an input to a
   correctness decision *and* to a reported field. *Avoid:* assert the postcondition and report the
   observation; narrow the catch (`ENOTEMPTY` is information, `ENOENT` is already-done); surface
   residue as a **new** JSON field; never infer mode from filesystem residue.
4. **The test that proves the bound works asserts the wrong side of the boundary** (Pitfall 8 —
   *ordering constraint*, phase topic: **Bounded-subprocess / test infrastructure**).
   `tests/prohibition-enforcement.test.cjs:698-699` asserts `result.status !== 'green'` and
   `result.located === true`. Both pass; the parent's verdict is genuinely correct. **Nothing in
   ~30,600 tests ever looks for a survivor**, so the suite is green while leaking a core on every
   run — measured 2026-08-22: two orphans at **~90% of a core each for 34 hours**, killed instantly
   by a plain `SIGTERM` (the signal was never *delivered*, not ignored). Then the evidence erases
   itself: `t.after(cleanup)` deletes the temp directory while the orphan still holds it as `cwd`;
   only `lsof -p <pid>` reveals it. *Avoid:* **the survivor assertion is the deliverable** and lands
   before or with the isolation flag — revert the flag and the test must go RED. Order cleanup after
   the survivor check.
5. **Tightening a guard so it refuses where it previously proceeded** (Pitfall 5 — *ordering
   constraint*, phase topic: **Workstream fail-safe precondition**). Every refusal is
   indistinguishable at the call site from a regression, and agents call these verbs unattended — a
   wrongly-armed guard produces a *stalled workflow*, not a bug report. The predicate must arm
   **more** often *and* not arm where it currently does not, and both directions are decided by the
   same expression. *Avoid:* **characterization tests before the change** — pin today's behaviour
   across the matrix, then flip the intended cells' expectations in the same commit; the diff of that
   test file **is** the blast radius. Grep every caller before arming
   (`grep -rn "state advance-plan\|init.progress\|phase.complete" gsd-core/workflows agents commands skills`).
   Record fail-closed as a deliberate decision so a future reader does not "fix" the refusal.

**Also carried:** *"Verified" that does not cover bash 3.2 / zsh 5.9 / POSIX sh* (Pitfall 6) —
macOS `/bin/sh` reports `BASH_VERSION=3.2.57`, i.e. **bash in sh-emulation mode, not a POSIX sh**, so
the POSIX leg is not verifiable on this machine at all; real `dash` exists only on the ubuntu lane.
*Four symptoms, one cause* (Pitfall 4) — split by *"does this want the same edit?"*, never by
*"is this the same file?"*, and answer the cause-completeness question (*"if this cause were fully
fixed, which captured symptoms would still reproduce?"*) before closing.
*Upstream PR shape decided too late* (Pitfall 9) — decide **carried-vs-contributed per defect in the
phase plan**, before writing the diff; CONTRIBUTING.md's issue-first rule and PROJECT.md's standing
decision against filing issues are in direct tension, and resolving it late wastes the shaping work.

---

## Implications for Roadmap

Six phases plus an unblocked-anytime bucket. **Ordering is justified by dependency, not by
severity** — several blockers land late because they are gated, and two minors land early because
they unblock others.

### Phase 1: Instruments before repairs

**Rationale:** Nothing here fixes a reported defect. Every item makes a later fix **honest** (1),
**survivable** (4), or **verifiable** (2, 3). Item 3 cannot be reordered after the site fixes without
the site fixes being unverified — that is precisely how four upstream rounds each shipped green.

**Delivers:**
1. **`npm run build:lib`** (or delete `gsd-core/bin/lib/`) so build output stops disagreeing with
   `src/` — **ADJ-3, hard gate on all empirical work in this milestone.**
2. **Subprocess leak fix** — `--test-isolation=none` in `buildNodeTestArgs`
   (`src/prohibition-enforcement.cts:220-222`), **plus the survivor assertion, which lands before or
   with the flag.** Sequenced here because the spawn seam is about to carry double load from item 3.
3. **Cross-shell harness** — lift `detectShells()` into `tests/helpers/`, parameterize
   `unreachable-shell-guard.test.cjs:149` over `SHELLS`. **Expect RED against the 11 unfixed sites;
   that redness is the deliverable.**
4. **`bin/install.js` local-artifact survival** — the three files into the repo, plus the
   `make install` pre-flight via `detect-custom-files`.

**Addresses:** build-before-measure; three local-only artifacts; `make install` pre-flight.
**Avoids:** Pitfall 1 (harness divergence), Pitfall 7 (timeout bounds one PID), Pitfall 8 (bound's
own test asserts the wrong side).
**Re-verify as part of the fix, not after:** with isolation `none` the target file is *imported into
the runner process* and shares globals — confirm the `GSD_PROHIB_SUBJECT` convention (#1279) and
`childEnv()`'s `NODE_TEST_CONTEXT` / `NODE_OPTIONS` stripping still behave. That stripping exists to
stop an ambient runner context corrupting the verdict, and this change moves the wall it guards.

### Phase 2: The workstream resolution chain

**Rationale:** The helper must exist before anything cites it, and the notice's verb-class split only
makes sense once the guard defines the mutating class.

**Delivers:**
5. `requireResolvedWorkstream` helper with **ADJ-1's disjunction**, applied at `init.cts:2926` and
   `phase.cts:2212` (**PR-A**), with a regression test for the empty/absent case.
6. Apply to `state advance-plan` (**PR-B**); reconcile and supersede WIP `f72f1534`.
7. `output()` non-resolution notice — conditional field on the JSON branch, stderr line on `--raw`.
8. `cmdWorkstreamComplete` honesty: derive `reverted_to_flat` from a post-operation observation,
   report residue, and clear the adapter actually resolved from (**PR-C**).

**Addresses:** the mode predicate; extracted guard predicate + Class A `state`/`phase`/`roadmap`
writers; exit-1 fault contract; `workstream_resolution` payload field; `workstream get` → peek.
**Avoids:** Pitfall 2 (N copies + the site with none), Pitfall 3 (swallowed cleanup composed into a
correctness check), Pitfall 5 (guard tightening indistinguishable from a regression).
**Sequencing note on item 8:** PITFALLS assigns Pitfall 3 to this phase and is explicit that fixing
only the guard leaves `workstream complete` still lying — so it stays here, not in the anytime
bucket. But **ADJ-1's monotone disjunction removes the hard *sequencing* dependency** that FEATURES'
graph asserts: the predicate handles the state whether or not the generator is fixed. Item 8 remains
in scope as (a) the generator of the dangling state and (b) a reported-field defect in its own right.
**Class A scope for v1.12** is `state.*` + `phase.*` + `roadmap.*`; the Class A tail
(`config-*`, `template.fill`, `scaffold`, `todo.complete`, `estimate-calibrate`, `audit acknowledge`)
is v1.12.x. **Class B gets the field, never a refusal.**

### Phase 3: STATE.md write path

**Rationale:** Strictly after item 6 — `state.cts:657` (guard) and `:679` (resync arg) are the **same
function**. Also visible in the Phase-1 repro: the same silent `advance-plan` call that mutated root
STATE.md **also** rewrote its `progress` block to `total_phases: 1, total_plans: 0,
completed_plans: 0` from a disk scan. Both defects fire in one call; fixing the write path before the
routing would mean correctly resyncing the wrong file.

**Delivers:** `{ resync: false }` on the five body-only appenders (`state.cts:868, 1086, 1154, 1259,
1344`) plus `gsd-tools.cjs:1172`; a decision on the three `{ divergedFields }` sites including
`cmdStateAdvancePlan:679`.
**Addresses:** PROJECT.md's *"STATE.md writes that do not resync stale frontmatter from disk."*

### Phase 4: Fence portability sites and ratchet

**Rationale:** After Phase 1 item 3 — the harness must be able to see the difference. The sites do
**not** want one mechanism, so they split into three concerns.

**Reconciling the three site counts in circulation, because they measure different things:**
**11** is the fence-idiom subset this phase fixes (9 content reads + 1 VERIFICATION + 1
`PIPESTATUS`) and is the number the harness goes RED against. **25** is PROJECT.md's wider
affected-site inventory across all 6 mechanisms, whose remainder lands in Phase 5's routing
sweep and the M7 `grep -oP` item. **1,052** is the whole shell-tagged fence corpus the lint
scans. None of these supersedes another.

**Delivers:**
11. The **9 content-read sites** — portable glob idiom (shim + `${#ARR[@]} -gt 0`, or the
    `while IFS= read -r … < <(find …)` form; both measured 8/8 across bash 3.2.57 and zsh 5.9).
12. `agents/gsd-verifier.md:85-86` → the existing `verification resolve-file` verb.
13. `gsd-core/workflows/audit-fix.md:145` `PIPESTATUS` — a different mechanism, carved out.
14. `scripts/lint-portable-glob-guard.cjs` — the per-fence ratchet, using
    `web-tree-sitter` + `tree-sitter-bash` (**ADJ-2**), wired into `lint:ci`, **with an ADR amending
    ADR-3409's premise** (measured at 0.6%, not a blocker).
15. `port-4-10` (mempalace recall line) — explicitly blocked on item 11.

**Uses:** `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1` — the milestone's entire dependency
delta.
**Avoids:** Pitfall 4 (four symptoms one cause — update
`.planning/reference/shell-fence-portability.md` **in the same commit**), Pitfall 6 (define
"verified" as a named matrix in the plan, and state the POSIX leg's evidence source explicitly),
M1 (`skills/` is outside every generator and lint surface — diff the
`commands/gsd/X.md` ↔ `skills/gsd-X/SKILL.md` twin in the same change), M3 (`--pick` on an array
comma-joins; the `@file:` >50KB spill guard is JSON-branch-only, so any new verb returns **paths,
never contents**).
**Byte-budget gate:** `agents/gsd-verifier.md` is **49,150 bytes against a 49,152 cap** — **2 bytes
of headroom**. Any net-additive fence fix there fails the build; the `verification resolve-file` swap
is 7 bytes *shorter* and is the only known compliant option. `wc -c` every touched agent file.
**CI note:** the fence lane must be macOS-gated (bash 3.2.57 exists only on macOS; `windows-latest`
has neither shell), must pass **absolute** interpreter paths (`/bin/bash`, `/bin/zsh`, `/bin/sh` —
a bare `'bash'` resolves through `PATH`, where Homebrew bash 5.x may precede `/bin/bash` on GitHub
macOS runners, reproducing the exact defect being fixed), and **must NOT copy `full_only: true`**
from the `install-smoke.yml` precedent — that flag skips the lane on `pull_request`, which is
precisely the condition under which four upstream rounds each shipped clean. Scope it to a narrow
`shell-fences` job rather than a full macOS matrix entry (billing multiplier).

### Phase 5: Workflow markdown routing

**Rationale:** After Phase 4 — several of these files are fence edits and must land on a tree where
the harness can see them. After Phase 2 — the routing sweep consumes resolved paths whose correctness
Phase 2 establishes.

**Delivers:** `route-workflow-files-through-resolved-workstream-paths` (27 sites, 8 files);
`pause-work` phase glob + dead gate (overlaps the routing sweep at `:67`); the `quick.md` pair —
`escape-description` then `reconcile-hash-column`, which share `src/markdown-table.cts` at adjacent
lines and must be sequenced or merged.
**Addresses:** PROJECT.md's *"workflow files resolved through workstream paths rather than root."*
**Note:** the Class D path fixes (D-1 `quick-tasks-append`, D-2 `WAITING.json`) belong to this target
feature and are v1.12.x differentiators — a guard cannot reach them.

### Phase 6: Port campaign remainder

**Rationale:** Strict internal order forced by a shared interface; the installer dependency is
already cleared by Phase 1.

**Delivers:**
19. `port-4-4` (`ExpandResult` interface — it owns the change) → `port-4-3` (scoring, consumes it) →
    `port-4-3b` (seed-floor invariant + the CI blind spot). Same file, same interface, no reordering.
20. `port-4-8` (convergence routing) — unblocked by Phase 1 item 4.
21. `port-4-7` (review-lane timeouts, incl. `review.md:295-300`) — after Phase 4's `review.md` work.
22. `migrate-the-glab-forge-port` — the largest `ship.md` change; last, to minimise conflicts with
    Phase 5's routing sweep.

**The `port-4-3b` CI blindness needs three layers, not one** — distinguish two failures the graphify
case conflates. *Violation with blind tests:* `applyBudget` could stop honouring the seed floor and
`tests/graphify-query.test.cjs:560`/`:587` still pass, because `arbGraph` produced **≥2 seeds in 0 of
200 runs** at the pinned `numRuns: 200, seed: 42`. *Deletion:* someone removes those lines and
nothing notices.
- **Layer 1 (the direct answer):** an **espree** invariant-title lock — a registry of required test
  titles plus a test that parses the file and asserts each is still present.
  ⚠ **`scripts/lint-removed-but-needed.cjs` does not cover this** — it keys on deleted *files*
  (`git diff --name-status`, status `D`); a deleted assertion inside a surviving file is invisible to
  it. Say so, or a phase will assume it is handled. `scripts/lib/allowlist-ratchet.cjs` already
  implements the wanted semantics; do not hand-roll a third.
- **Layer 2:** strengthen `arbGraph` to reliably generate ≥2 differentiated-quality seeds, and add
  the already-written counterexample RED test from
  `.planning/runbooks/porting-local-patches-assets/graphify/4.3b-seedfloor-counterexample.cjs`.
- **Layer 3:** add `graphify` to `COVERED` in `scripts/mutation-matrix.cjs`. **The `COVERED` entry
  alone is inert** — `.github/workflows/mutation.yml:15-25` gates the workflow on an `on.paths`
  allow-list that `tests/graphify-query.test.cjs` matches **none of** (neither `.property.` nor
  `.unit.`, and not one of the three named files), so a PR touching only that file never starts the
  workflow. **Both files must change in one commit.** And even correctly wired, a mutation score is a
  threshold, not an identity lock — floors are set at "measured minus 1–2 points", so deleting one
  assertion can drop the score by less than the margin and pass. That is the durable reason Layer 1
  stays. **Floors must come from a CI run** — local runs count timeouts as kills and inflate scores
  (measured: `prompt-budget` 99.6% local vs 68.3% CI).

### Anytime — no shared surface, parallelisable

`audit-open-counts-todos` (`src/audit.cts` only) · `port-4-2` (agent markdown call signatures) ·
`port-4-6` (`hooks/gsd-statusline.js`) · `context-monitor-misattributes`
(`hooks/gsd-context-monitor.js`) · `build-a-handoff-skill` (new file).

### Phase Ordering Rationale

- **ADJ-3 gates everything empirical.** Build output currently contains a guard the source does not.
  Any phase that "verifies the defect reproduces" or "verifies the fix works" before the rebuild
  measures a phantom.
- **Instruments before repairs.** Under a bash-only harness, all 11 broken fence sites pass *before*
  the fix and pass *after* it — the instrument's reading is identical either way. Fixing sites first
  is round five of #2770 → #2962 → #3300 → #3409.
- **Extraction before call-site fixes.** Two copies exist and a third site has none. Fixing them in
  place produces a third copy and a fourth divergence — the codebase's own DEFECT.GENERATIVE-FIX.
- **The survivor assertion before or with the isolation flag.** Shipped the other way round, the fix
  regresses silently at the next refactor of `buildNodeTestArgs` — the same shape as the bug.
- **Characterization tests before the guard tightening.** The predicate flips in both directions at
  once; the test-file diff is the only reviewable blast radius.
- **Hard same-function sequences:** `state.cts:657` (guard) before `:679` (resync);
  `port-4-4` before `port-4-3` before `port-4-3b`; the installer fix strictly before `port-4-8`
  (its own frontmatter says it *blocks the routing half*); the leak fix before the harness that
  doubles the number of spawned shells.
- **Shared-file collisions to sequence, not parallelise:** `pause-work.md` (2 todos, overlapping
  lines) · `quick.md` (3 todos, two of which also share `src/markdown-table.cts`) · `review.md`
  (3 todos — fence fix first, it is the reference implementation) · `ship.md` (routing sweep vs the
  large glab rewrite).

### Research Flags

**Phases needing `--research-phase` during planning:**

- **Phase 4 (fence portability / ratchet)** — the tree-sitter rule-writing spike. STACK is
  MEDIUM-HIGH here: 1033/1052 fences parse error-free and all seven rule shapes are confirmed
  expressible, **but the rules themselves have not been written and run against the corpus.** A
  one-day spike closes it. Same phase also carries the process-substitution-vs-pipe decision (below),
  which must be settled before any `sh` lane is added.
- **Phase 3 (STATE.md write path)** — the `{ divergedFields }` three-site decision is a genuine open
  design question, not a mechanical fix (ARCHITECTURE says so explicitly). Needs its own discussion
  before item 10.
- **Phase 6 (`port-4-3b`)** — the mutation floor must be set from a **CI** measurement, so the phase
  needs a measurement step planned, not a number assumed.

**Phases with standard patterns (skip research):**

- **Phase 1 items 1, 2, 4** — the build step is mechanical; `--test-isolation=none` is settled by
  Node v24 docs with the constraint fully characterised (no `detached` on sync call sites); the
  installer pre-flight uses a verb that already exists and was executed against the live tree.
- **Phase 2** — the predicate is measured against a seven-scenario table, the seam is identified, the
  PR decomposition is written, and four in-repo precedents establish the pattern.
- **Phase 5** — a mechanical routing sweep once Phase 2 establishes the resolved paths; the only
  research content is the collision map, which is already written.

**Process question, not research:** will maintainers accept a knowingly-RED harness PR? That decides
whether Phase 1 item 3 and Phase 4 item 11 are one PR or two. **Flag it; do not guess.** If they will
not, plan a temporary skip-list or land harness+sites together.

### Anti-features — the wrong turns this milestone invites

| Tempting | Why it is harmful | Do instead |
|---|---|---|
| **Hoist the guard to `dispatchHostCommand` / the CLI entry** — the literal reading of PROJECT.md's *"one shared precondition across three commands"*; one site instead of 41 | Kills every Class C diagnostic (`workstream get`, `list`, `set`) at exactly the moment they are needed: the state becomes undiagnosable **and** unrepairable from the CLI. Also re-creates #3579 (the entry's own 14-line comment says a decision made there *was* the bug), and changes the exit status of every verb — reviewed upstream as a feature, not a fix | Extract the **predicate** into `planning-workspace.cts`; call it from each Class A verb |
| **stderr warning as the only fallback signal** | git's own docs say advice is human-facing and tell subprocess callers to squelch it; this tool's caller is an agent parsing stdout JSON, and `--json-errors` does not govern payloads | Named field in the payload; stderr line as an *additional* human affordance on the `--raw` path |
| **Normalize `cmdStateAdvancePlan`'s exit-0 paths "for consistency"** | Re-opens ADR-2980 with 60 sites and 170 `output` callers of blast radius. Hyrum's Law with no `/v2/` for `$?` | New guard exits 1; existing paths untouched |
| **Refuse on every Class B read** | Turns a defect fix into a ~25-verb behaviour change and makes the workflow unusable during exactly the failure it detects | Refuse Class A; surface on Class B |
| **Patch `install.js` to skip unknown `gsd-*` dirs** | Wipe-then-replace-from-source is *correct*; the defect is that the three files were never in the source. Skipping unknown dirs strands genuinely stale artifacts forever | Files into the repo + `make install` pre-flight |
| **Add the three artifacts to `USER_OWNED_ARTIFACTS`** | Perpetuates the named-special-case pattern, and that allowlist is scoped inside `gsd-core/`, not to sibling `skills/`/`agents/` | Manifest-based detection, which already covers those dirs |
| **A new "is this verb safe" registry** | A third source of truth alongside `mutation` and the resolver — DEFECT.GENERATIVE-FIX again | Reuse `mutation` (after fixing it) or derive from the resolver |
| **Convert all 57 `interpreter: 'bash'` sites** | Violates one-concern-per-PR and doubles CI; most test bash-specific hooks that legitimately run under their own shebang | Scope to the fence-extraction harness only |
| **A regex lint per mechanism** | Directly against ADR-1703, which exists *because* an attempted regex extension silently could not match `deepStrictEqual` | One CST lint, seven rules |
| **`emulate -L sh` preamble across the fence corpus** | Fixes 3 of 6 mechanisms in one line but changes far more than three behaviours across every shipped fence; unreviewable under one-concern-per-PR | Targeted per-site fixes + the lint as ratchet |
| **A shared *included* fence snippet** | No include mechanism exists (a new concept), and the byte budget forbids net additions where they are most needed | Push the rule into the CLI as a verb (`verification resolve-file`) where one is available |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | Every load-bearing claim is a doc citation or a measurement run in this repo today: 1,052-fence probes across four parsers; `sh-syntax`'s positional-only AST reproduced in three lines; all seven CST rule shapes emitted with named fields; `mutation.yml`'s `paths:` filter read in-tree. **MEDIUM-HIGH** on one item — tree-sitter grammar sufficiency for a *production* lint (rules confirmed expressible, never run against the corpus). **MEDIUM** on Homebrew bash preceding `/bin/bash` on GitHub macOS runners (not measured on a runner; the mitigation is free and correct regardless, so the risk is priced out). |
| Features | **HIGH** | Source-read at every cited line for clusters 1, 3, 4, plus executed reproductions: the Class A verb table, the empty-`workstreams/` state, the `workstream get` pointer deletion, the stale-build trap, and the `detect-custom-files` run. HIGH for cluster 2's git and kubectl citations (primary source read verbatim). **The one terraform sub-claim that is undocumented is labelled as undocumented, not asserted.** |
| Architecture | **HIGH** for Q1–Q3 — every load-bearing claim reproduced against the built CLI in this tree, including the seven-scenario predicate table and the end-to-end `workstream complete` repro. **MEDIUM-HIGH** for the (b)-vs-(c) portability argument (four in-repo precedents + `CONTRIBUTING.md:52`; maintainer reception is a judgement). **MEDIUM** for the Q4 collision map — derived from todo frontmatter `files:` plus targeted source reads; the graphify and installer chains were read from todos, **not executed**. |
| Pitfalls | **HIGH** for the mechanism claims — every one measured in this repo or cited to current official docs (`ENOTEMPTY` with `isDirectory` count 0; 57 `interpreter: 'bash'` sites; the 2-byte agent budget; `/bin/sh` on macOS reporting `BASH_VERSION=3.2.57`; Node v24 `child_process` and test-runner docs via context7). **MEDIUM** for the process/triage recommendations (ITIL problem-vs-incident, validation-strengthening rollout practice) — industry practice, not measurable here. |

**Overall confidence:** **HIGH**

### Gaps to Address

- **`diagnose().present` after the `.DS_Store` (T2) path — unmeasured.** No file called
  `diagnoseUnresolvedActiveWorkstream` in that state. The closest evidence (ARCHITECTURE's T1 repro:
  `shared marker file exists? YES`, and `cmdWorkstreamComplete:302-303` clearing through one adapter
  only) suggests the marker survives and the disjunction fires. *Handle:* a Phase 2 verification cell
  in the call-site matrix, not a scoping change.
- **Process substitution vs pipe — mutually exclusive, and the reference doc currently asserts
  both.** The chosen `< <(find …)` form is bash/zsh-only; it is 4 of the `/bin/sh -n` failures.
  `.planning/reference/shell-fence-portability.md`'s *"12/12 … and POSIX `sh`"* row measured the
  **pipe** form, a different construct with different loop-variable semantics. *Handle:* decide
  before any `sh` lane goes in — either drop `sh` from the shell matrix, or ship the form that
  survives it.
- **Tree-sitter rules written but never run against the corpus** (STACK's one MEDIUM-HIGH row).
  *Handle:* a one-day spike in Phase 4 before the lint is wired into `lint:ci`.
- **`{ divergedFields }` — three sites, a genuine open design question.** *Handle:* its own
  discussion before Phase 3 item 10.
- **Knowingly-RED harness PR — a maintainer question, not a technical one.** *Handle:* ask before
  Phase 1 item 3 ships; plan a skip-list or a combined PR as the fallback.
- **ARCHITECTURE row 6 — `workstreams/` present-but-empty with *no* pointer.** Anomalous but
  currently permitted, and deliberately left unchanged; extending scope to it is a second concern
  needing its own message branch for the empty list. *Handle:* confirm that is the intent.
- **zsh availability on `ubuntu-latest`.** The probe skips gracefully, but if Linux lanes silently
  skip every zsh row, coverage rests on the three macOS shards alone. *Handle:* verify in Phase 1.
  *(Note: this is not decision-relevant to the **bash** half — bash 3.2.57 exists only on macOS, so
  a macOS lane is required regardless.)*
- **`skills/` is excluded from three scanners** (`sync-runtime-launcher.cjs`,
  `no-hardcoded-home-gsd-tools.test.cjs`, and the new lint) with no `commands/` ↔ `skills/` parity
  check — which is why two byte-identical copies of the broken `review-backlog` fence shipped
  undetected. **Not yet a captured todo.** *Handle:* capture it; out of scope for the fence PR.
- **`gsd_run` call sites can name verbs that do not exist** — `agents/gsd-plan-checker.md:758,760`
  calls `phase.list-artifacts`, which runtime rejects as `Unknown phase subcommand`, and nothing
  catches it. *Handle:* its own backlog item.
- **`migrateToWorkstreams` never moves `todos/` into the workstream dir** (`workstream.cts:81-86`),
  so after migration a workstream's todo paths point at a directory migration did not create.
  *Handle:* separate observation, not this milestone.
- **Environment baseline must be stated with every failure count.** `GSD_AGENTS_DIR` in the ambient
  environment fails 12 tests; a stray `.DS_Store` under `gsd-core/` fails 20; local Node here was
  measured at **v22.23.2** against a documented `>=24` floor, and npm treats `engines` as advisory.
  Node 24 also changed the default reporter from TAP to spec, so `# fail` greps match nothing.
  *Handle:* every phase's verification section states the baseline (3 environment-caused failures out
  of 30,612 at Node 24 with a clean tree) before quoting a count, and any gate that reads test output
  parses a machine format or pins the reporter.
- **Upstream contribution mechanics are a per-fix decision, not a phase.** CONTRIBUTING.md's
  issue-first rule vs PROJECT.md's standing decision against filing issues is unresolved tension;
  `scripts/changeset/lint.cjs` **evaluates nothing without `GITHUB_BASE_REF`**, so a green local run
  proves nothing (use `GITHUB_BASE_REF=next`); a tests-only harness PR needs **no** changeset while
  PRs touching `agents/`, `gsd-core/`, `commands/` need `--type Fixed`; rebase **last**, immediately
  before pushing, because `next` is strict-status and a rebase invalidates the sha-bound pass marker.
  *Handle:* carried-vs-contributed stated in each phase plan's opening, not its review.

---

## Sources

### Primary (HIGH confidence)

**Measured in this repo / on this machine, 2026-08-24 (macOS arm64):**
- 1,052-fence parse probes across `/bin/bash` 3.2.57, `/bin/zsh` 5.9, `/bin/sh`, `sh-syntax@0.6.0`
  (`LangBash`/`LangZsh`), and `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1`; per-mechanism CST
  shape extraction for M1–M7; `sh-syntax` positional-AST reproduction
- Executed reproductions in throwaway `$TMPDIR` trees: the empty-`workstreams/` disagreement
  (`reverted_to_flat: true` while the directory survives); `workstream get` deleting the session
  pointer and reporting `none`; the stale-build trap (`gsd-core/bin/lib/state.cjs` carrying a guard
  absent from `src/state.cts`); the seven-scenario predicate table against the built
  `planning-workspace.cjs`; the end-to-end `workstream complete` → dead-guard state
- `node gsd-core/bin/gsd-tools.cjs detect-custom-files --config-dir "$HOME/.claude"` (read-only) —
  named all three lost artifacts
- `fs.rmdirSync` on a directory containing only `.DS_Store` → `ENOTEMPTY` while
  `readdirSync(…).filter(isDirectory).length` → 0
- Login shell of the agent Bash tool: `$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset;
  `/bin/sh -c 'echo $BASH_VERSION'` → 3.2.57
- `agents/gsd-verifier.md` = 49,150 bytes; `LARGE_CAP` = 49,152

**In-repo source, read at the cited line:** `src/planning-workspace.cts`,
`src/active-workstream-store.cts`, `src/workstream.cts`, `src/init.cts`, `src/phase.cts`,
`src/state.cts`, `src/io.cts`, `src/command-aliases.cts`, `src/workstream-inventory.cts`,
`src/install-engine.cts`, `src/user-artifact-staging.cts`, `src/prohibition-enforcement.cts`,
`bin/install.js`, `gsd-core/bin/gsd-tools.cjs`, `tests/unreachable-shell-guard.test.cjs`,
`tests/prohibition-enforcement.test.cjs`, `tests/policy-shell-pinning.test.cjs`,
`tests/helpers/process-seam.cjs`, `tests/agent-size-budget.test.cjs`,
`scripts/mutation-matrix.cjs`, `scripts/lint-unreachable-guard-drift.cjs`,
`scripts/changeset/lint.cjs`, `.github/workflows/test.yml`, `.github/workflows/mutation.yml`,
`.github/workflows/install-smoke.yml`, `eslint.config.mjs`

**In-repo ratified decisions:** `docs/adr/2980-payload-carried-error-is-a-degraded-result.md`
(Accepted 2026-08-09) · `docs/adr/1703-portability-enforcement-architecture.md` ("AST, not regex") ·
`docs/adr/3409-unreachable-shell-guard-arms.md` (**premise measured at 0.6% — amend this
milestone**) · `docs/json-errors.md` · `CONTRIBUTING.md` · `.planning/PROJECT.md`

**Official documentation:** Node v24 `child_process` (option lists for `spawnSync`/`execFileSync`;
*"Signal propagation limitations in shell processes"*; `subprocess.kill()` grandchild note), `fs`
(`rmdirSync` non-recursive, `recursive` deprecated DEP0147), `test` / `cli` (`--test-isolation`
defaults to `'process'`, `'none'` imports into the runner and forces concurrency 1, renamed in
v23.6.0) · mvdan/sh v3.13.0 and v3.13.1 release notes + `syntax/parser.go` (`LangZsh`, experimental,
follows zsh 5.9) · ShellCheck `shellcheck.1.md` `-s` dialect list, wiki SC1071/SC1103, CHANGELOG
(*"Zsh support has been removed"*) · kubectl `pkg/cmd/config/use_context.go` and client-go
`tools/clientcmd/validation.go` · git `Documentation/config/advice.adoc`

### Secondary (MEDIUM confidence)
- Juergens, Deissenboeck, Hummel & Wagner, *"Do code clones matter?"*, ICSE 2009 — ~900 clone groups,
  **107 confirmed faults** from inconsistent changes; the *inconsistent bug fix* is the dangerous
  shape (HIGH as a citation; MEDIUM as generalisation to this repo)
- MITRE CWE-390; Google Error Prone `EmptyCatch` + Google Java Style §6.2; R. Chen, *"Since clean-up
  functions can't fail, you have to soldier on"* (2014) — the cleanup-path exception that makes the
  *composition*, not the swallow, the defect
- ITIL problem-vs-incident management (Atlassian ITSM, Rootly) — explicit numeric escalation
  triggers, Known Error Database, the documented failure of informal triggers
- Validation-strengthening rollout practice — MongoDB `validationAction: warn` → `error`; Microsoft
  APM `enforcement: warn` → `block`; Khorikov on strengthening requirements for pre-existing data
- ShellSpec — cross-shell BDD harness selecting the shell with `-s/--shell`: the precedent for
  parameterizing a harness over interpreters
- Terraform `workspace select` / `cli/workspaces` (HashiCorp Developer, 2025-11-19)

### Tertiary (LOW confidence / needs validation)
- The Q4 collision map's graphify and installer chains — derived from todo frontmatter, **not
  executed**. Validate at phase-plan time.
- `arbGraph` yielding ≥2 seeds in 0/200 runs — measured by port validation on 2026-08-20 and
  inherited, **not re-measured** in this research round.
- The fence site-fix idioms' 8/8 cross-shell result — inherited from the todo's measurement, not
  re-measured here.
- **Superseded, do not consult:** `.planning/.cache/research-backup/STACK.md.orig` (the `sh-syntax`
  draft — see ADJ-2).

---
*Research completed: 2026-08-24*
*Ready for roadmap: yes*
