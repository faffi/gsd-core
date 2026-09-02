# Architecture Research — v1.12 defect campaign

**Domain:** Mature TypeScript/Node CLI toolchain (gsd-core 1.11.0, faffi fork) — defect
integration, not greenfield design
**Researched:** 2026-08-24
**Confidence:** HIGH for questions 1–3 (every load-bearing claim reproduced against the
built CLI in this tree); MEDIUM for the question-4 ordering (derived from todo frontmatter
`files:` plus source reads; the graphify and installer chains were read from todos, not
executed)

> **Read the Scope Corrections first.** Two premises in the research brief do not survive
> contact with the tree. One changes what the roadmapper should plan; the other changes
> which fix is correct.

---

## Scope Corrections

### C1 — `src/state.cts` on HEAD carries no guard. The third copy is unmerged WIP.

The brief describes the guard as "copy-pasted into `init.cts:2926`, `phase.cts:2212` and
(newly) `state.cts`." On HEAD (`local/track-planning-history`, `f0a50b04`) there are **two**
copies, not three:

```
$ grep -rn "listAvailableWorkstreams" src/ | grep -v planning-workspace.cts
src/init.cts:99      src/init.cts:2926
src/phase.cts:86     src/phase.cts:2212
```

The third copy lives on `local/state-advance-plan-fallback-fix` at commit `f72f1534`, whose
own message reads *"wip(state): workstream fail-safe guard for advance-plan — KNOWN
INCOMPLETE, 1 test RED … NOT a finished fix — do not port upstream as-is."*

A live `state advance-plan` in this tree **does** emit the guard error — but only because
`gsd-core/bin/lib/state.cjs` is gitignored build output (`.gitignore:316`) left over from a
build of that WIP branch. **Source and build output disagree on HEAD.** Any phase that
starts by "reading the existing state.cts guard" will find nothing; any phase that starts by
running the CLI will find a guard that no committed source produces.

**Roadmapper impact:** the state-advance-plan work is *new code plus a WIP branch to
reconcile*, not a third edit of existing code. Sequence a `npm run build` (or equivalent)
early so the build output stops lying.

### C2 — The precondition is dead in a *narrower* case than stated, and `existsSync` does not fix it

The brief says `availableWorkstreams.length > 0` "is false when `.planning/workstreams/`
exists but is empty, so none of them fire in exactly the reported failure." Half right.

The reported repro (`.planning/todos/pending/2026-08-21-state-advance-plan-…md`) does
`mv .planning/workstreams/tenant-vpc-reach .planning/workstreams/tenant-vpc-reach.bak` —
which leaves a *directory* under `workstreams/`, so `listAvailableWorkstreams` returns
length 1 and **the guard does fire.** Reproduced:

```
==================== workstreams/ = sibling ====================
-- state advance-plan:
Error: state advance-plan requires a workstream in workstream mode — the active-workstream
marker names 'ghost-ws', but it did not resolve: … Available workstreams: other-ws
```

The genuinely dead case is **pointer present + `workstreams/` empty or absent**:

```
==================== workstreams/ = empty ====================     (and = absent)
-- current_plan before: **Plan:** 1 of 3
-- state advance-plan:  true   exit=0
-- current_plan AFTER : **Plan:** 2 of 3      ← root STATE.md silently advanced
-- pointer file still present: YES
-- (running twice more) {"advanced": true, "previous_plan": 2, "current_plan": 3}
```

**And the codebase generates that state itself.** `cmdWorkstreamComplete`
(`src/workstream.cts:285-347`) does two things that combine into the trap:

- `:302-303` — `const active = getActiveWorkstream(cwd); if (active === name)
  setActiveWorkstream(cwd, null)`. `getActiveWorkstream` resolves through the **chain**
  (session pointer, then shared marker fallback), but `setActiveWorkstream` writes through
  `pickActiveWorkstreamAdapter` — **one** adapter, the session pointer when a session key
  exists. So a session-keyed process that resolved `active` from the *shared* marker clears
  its own empty session pointer and leaves the shared marker intact.
- `:337` — `if (remainingWs === 0) fs.rmdirSync(wsRoot)`. Completing the last workstream
  **removes `.planning/workstreams/` entirely** (`reverted_to_flat: true`).

Reproduced end to end:

```
before: shared marker = solo
{"completed": true, "workstream": "solo", "remaining_workstreams": 0, "reverted_to_flat": true}
after : shared marker file exists? YES -> 'solo'
after : .planning/workstreams exists? NO
```

That is precisely the dead-guard state, produced by a supported command on its happy path.

**Consequence for the fix:** the WIP commit's own suggestion — adopt
`fs.existsSync('.planning/workstreams')`, the definition at `src/workstream.cts:78` — **also
fails**, because `:337` just deleted that directory. See §1 for the predicate that works.

---

## Existing Architecture (as it bears on these fixes)

Three seams matter. All three already exist; none is being introduced.

### Seam A — workstream resolution (`src/active-workstream-store.cts`)

```
--ws flag ─┐
GSD_WORKSTREAM env ─┼─> resolveActiveWorkstream (:446-478)
stored pointer ─────┘         │
                              ├─> pickActiveWorkstreamAdapterChain (:242-275)
                              │      chain[0] = "owned"  (session pointer, or shared when keyless)
                              │      chain[1..] = read-only fallbacks (shared marker)
                              │
                              ├─> resolveFromChain (:300-319)
                              │      owned present-but-bad -> clear() if selfHeal, return null
                              │      owned absent -> consult fallbacks read-only
                              │
                              └─> resolvesToExistingWorkstream (:283-286)
                                     valid name AND workstreams/<name> exists
```

Read variants: `getActiveWorkstream` (self-heals, `:358`), `peekActiveWorkstream`
(never clears, `:375`), `diagnoseUnresolvedActiveWorkstream` (read-only, reports *why*,
`:340-356`).

### Seam B — path composition (`src/planning-workspace.cts`)

`planningDir(cwd, ws?, project?)` (`:124-141`) reads `process.env['GSD_WORKSTREAM']` when
`ws` is `undefined`. Everything downstream (`planningPaths`, `:185-202`) composes from it.

### Seam C — CLI entry bootstrap (`gsd-core/bin/gsd-tools.cjs:4136-4157`)

Resolves the workstream **once**, with `getStored: peekActiveWorkstream` (deliberate, per
#3579 — the bootstrap must not consume the self-heal), then
`applyResolvedWorkstreamEnv(workstreamContext, process.env)` at `:4155` injects
`GSD_WORKSTREAM` before dispatch. Every verb inherits routing from env.

**The defect's shape:** Seam C resolves a dangling pointer to `null`, does not set
`GSD_WORKSTREAM`, and Seam B therefore composes root `.planning/`. Nothing between them
records that a pointer *was named and did not resolve*. The two guards are a per-command
patch over a gap in the seam.

---

## Q1 — Where the workstream fail-safe belongs

### Recommendation: **(b) — one shared helper in `planning-workspace.cts`, with a corrected precondition.**

Not (a), not (c). Reasoning below, then the exact predicate.

### Why not (c) — push into the resolution layer / CLI entry

Three independent blockers, each sufficient:

1. **Read-only verbs must survive a dangling pointer.** The brief names this constraint and
   it is real: `workstream get`, `workstream list`, `audit`, and the statusline hook all
   need to run against broken state so it stays diagnosable. #2850 added
   `peekActiveWorkstream` for exactly this — a read-only consumer "must never mutate
   persistent, possibly cross-session state as a side effect of drawing a screen"
   (`src/active-workstream-store.cts:363-374`). A CLI-entry hard-fail inverts that.
2. **The CLI entry deliberately does not decide.** `:4141-4149` is a 14-line comment
   explaining that the bootstrap is *"a check, not the consuming read"* and that a decision
   made there was the #3579 bug. Putting the fail-safe there re-creates the defect the
   comment documents.
3. **Upstream portability.** A guard at the entry point changes the exit status of every
   verb. That is a behavioural change to the dispatcher, reviewed as a feature, not a fix.
   `CONTRIBUTING.md:52` — an enhancement *"does not add new commands, new workflows, or new
   concepts"*; a global refusal policy is a new concept.

### Why not (a) — three one-line precondition fixes

The one-line fix is not one line. The corrected predicate needs
`diagnoseUnresolvedActiveWorkstream` hoisted *above* the branch (it is currently called
inside it), so each site changes by ~4 lines in two places. Triplicating a 4-line
correction across three files reproduces the exact failure this codebase has a name for.
From `src/planning-workspace.cts:180`: *"Without this shared helper, adding the `quick` key
would leave TWO composers … the **DEFECT.GENERATIVE-FIX** shape the `debug` key (#3149) was
introduced to eliminate."*

### Why (b) is conformance, not scope creep — the portability argument

This is the load-bearing point for the upstream constraint, so it is worth being explicit:
**extracting a shared predicate is the house pattern, and the same file already contains
three instances of it.**

| Precedent | Location | What it consolidated |
|---|---|---|
| `quickDirFrom` | `planning-workspace.cts:181-183` | #2142 — two composers of `<planning>/quick` |
| `findContextMdIn` | `planning-workspace.cts:453-469` | #3739 — *"the 5-site duplication … across init.cjs, roadmap.cjs, core.cjs, gap-checker.cjs"* |
| `describeUnresolvedWorkstreamReason` | `planning-workspace.cts:432-435` | #3579 — *"so the two error messages describe the same failure the same way instead of drifting"* |
| `listAvailableWorkstreams` | `planning-workspace.cts:151-161` | its own docstring: *"Single source of truth for the 'workstream mode' detection shared by the #1912/#2028 fail-safe guards … so the two paths cannot drift"* |

That last row is decisive. `listAvailableWorkstreams` was **already extracted for these two
guards, for this reason.** The extraction was simply drawn at the wrong boundary — it
factored out the *list* but left the *predicate* duplicated. Widening an existing helper to
cover the predicate it was created to serve reads to a reviewer off `next` as finishing
#1912/#2028, not as a refactor bundled with a fix. A reviewer who objects to (b) is
objecting to a pattern the module's own docstrings advocate four times.

### The predicate — verified against seven scenarios

Use a **strictly additive disjunction**. `availableWorkstreams.length > 0` stays; the
diagnostic's `present` flag is OR'd in:

```
inWorkstreamFailSafeScope  ==  listAvailableWorkstreams(cwd).length > 0
                               || diagnoseUnresolvedActiveWorkstream(cwd).present
```

Measured (`node` against the built `planning-workspace.cjs`, session env cleared):

| Scenario | current | proposed | verdict |
|---|---|---|---|
| flat, no `workstreams/`, no pointer | false | **false** | unchanged — flat projects keep working |
| `workstreams/` has dirs, no pointer | true | **true** | unchanged (NONE_ACTIVE arm) |
| `workstreams/` has a sibling + dangling pointer | true | **true** | unchanged (MARKER_UNRESOLVED arm) |
| `workstreams/` **empty** + dangling pointer | false | **true** | **FIXED** |
| `workstreams/` **absent** + dangling pointer | false | **true** | **FIXED** |
| `workstreams/` empty, no pointer | false | **false** | unchanged (deliberate — see below) |
| `workstreams/` has dirs + valid pointer | true | **true** | unchanged |

The disjunction is **monotone**: it can only add firing, never remove it. No currently-green
test can turn red by construction — which matters, because the only coverage of these guards
lives in `tests/workstream.test.cjs:430-464` and every fixture there is a `sibling`-shaped
case that still passes.

Two rejected alternatives, both worse:

- **`diagnosis.present` alone.** Drops the `WORKSTREAM_MODE_NONE_ACTIVE` arm entirely
  (workstreams exist, no pointer at all → `present` is false). Regresses #1912.
- **`fs.existsSync('.planning/workstreams')`** (the WIP commit's suggestion, matching
  `src/workstream.cts:78`). Reads false after `cmdWorkstreamComplete:337` rmdir's the
  directory — i.e. false in the exact case that produces the bug. Also flips row 6 to
  `true`, firing with an empty `Available workstreams:` list and no reported defect behind
  it.

**Open judgement call for the roadmapper (row 6):** `workstreams/` present-but-empty with no
pointer is anomalous but currently permitted. The recommendation leaves it alone — extending
scope to it is a second concern and would need its own message branch for the empty list.

### Shape of the shared helper (NEW)

Export from `src/planning-workspace.cts`, adjacent to `describeUnresolvedWorkstreamReason`:

```
requireResolvedWorkstream(cwd, {
  verb: 'state advance-plan',
  consequence: "Root STATE.md (likely stale or a different milestone's) would be advanced",
  runtime,
}) -> void   // returns cleanly, or calls error() with the right ERROR_REASON
```

It owns: `listAvailableWorkstreams`, the `peekActiveWorkstream`/env resolution, the
disjunction, the two-arm branch, both message templates, and both `ERROR_REASON` codes
(`src/io.cts:199-200`). Each call site collapses from ~30 lines to one. The per-verb strings
stay parameters — `init.progress` says "reported", `phase.complete` says
"STATE.md/ROADMAP.md … written", `state advance-plan` says "advanced" — so no message text is
lost in the consolidation.

### PR decomposition (upstream, one concern each)

- **PR-A** — helper extraction + corrected precondition at the two live sites
  (`init.cts:2926`, `phase.cts:2212`) + a regression test for the empty/absent case. Type
  `Fixed`. This is a bug fix with a shared-predicate extraction — the shape `#3739` and
  `#3149` already landed as.
- **PR-B** — apply the helper to `state advance-plan`. New coverage for a verb that has
  none. Separate PR; do not bundle. Supersedes `f72f1534`.
- **PR-C** (optional, separate) — `cmdWorkstreamComplete:302-303` should clear the marker it
  actually resolved from, not whichever adapter `pickActiveWorkstreamAdapter` picks. This is
  the *generator* of the dangling state and is the "scope check" the advance-plan todo asks
  for. Independent of A and B; a fix here reduces how often the guard is needed but does not
  replace it (renames and manual archives still dangle pointers).

---

## Q2 — Fence portability

### Recommendation: **(ii) harness first, then (i) the sites, then (iii) the lint. Reject (iv).**

And yes — **the harness fix must land before the site fixes.** Not as process hygiene; because
without it there is no instrument that can distinguish a fixed site from an unfixed one.

### Why harness-first is forced, not preferred

`tests/unreachable-shell-guard.test.cjs:149` does the hard half correctly — it extracts
**live fences from shipped `.md`**, never a hand-copied duplicate — and then runs them
through `runHook(scriptPath, [], { interpreter: 'bash', ...options })`. The interpreter is
hardcoded. Under bash every one of the 11 broken sites passes. Apply the fix, and every one
of the 11 sites *still* passes. **The instrument's reading is identical before and after.**

The sharpest evidence that this is a harness problem and not a coverage problem:

> **CI already runs on macOS with zsh and still cannot see it.**
> `.github/workflows/test.yml:452-462` — three `macos-latest` shards with `shell: 'zsh {0}'`.
> That sets the shell for the CI *step*; the test then explicitly spawns `bash`. The zsh
> lanes exist, run, and are blind by construction.

Upstream's own trail (#2770 → #2962 → #3300 → #3409) is four rounds of fixing "the shape that
was visible under bash." Fixing sites without fixing the instrument is round five.

### The harness fix is an extraction, not an invention — and the precedent is in the same file family

`tests/review-build-prompt-optional-sections.test.cjs:52-62`:

```js
// bash is unconditional (GitHub's windows-latest lanes ship Git Bash …). zsh is probed —
// it is the second dialect the shim targets, but it is absent on windows lanes, so its
// rows skip rather than fail there.
function detectShells() {
  const shells = [{ name: 'bash', cmd: 'bash' }];
  const probe = spawnSync('zsh', ['-c', 'exit 0'], { timeout: PROBE_TIMEOUT_MS, windowsHide: true });
  if (!probe.error && probe.status === 0) shells.push({ name: 'zsh', cmd: 'zsh' });
  return shells;
}
const SHELLS = detectShells();
```

This suite tests `gsd-core/workflows/review.md` — **the same file that holds the only
fully-correct fence idiom in 1048 fences** (`review.md:248-273`, per the todo's exhaustive
sweep). So both the correct pattern *and* the correct harness shape were built, once, for
the same file, and neither propagated. The architectural defect is not "we don't know how";
it is that both artifacts stayed file-local.

**Scope the harness PR narrowly:** lift `detectShells()` into `tests/helpers/` and make
`unreachable-shell-guard.test.cjs` consume it, parameterizing its `runBashScript` over
`SHELLS`. **Do not sweep the 20 other files that hardcode `interpreter: 'bash'`** — most
test bash-specific hooks that legitimately run under their own shebang. `runHook` already
takes `interpreter` as an explicit parameter (`tests/helpers/process-seam.cjs:235-241`,
documented as *"EXPLICIT, never inferred"*), so no seam change is needed.

Expected outcome: **the harness PR lands RED-then-GREEN on nothing** — it makes the 11 sites
fail under the zsh rows, which is the correct signal. Plan for a temporary skip-list or land
harness+sites together in a single PR *if* the maintainers will not take a knowingly-red
harness. That is a maintainer question, not a technical one; flag it, don't guess.

### Why (iv) — a shared included snippet — is not available

1. **No include mechanism exists.** Fences are extracted and executed standalone; there is no
   `source` of a shipped fragment that survives the extraction. Introducing one is a new
   concept (`CONTRIBUTING.md:52`).
2. **The size budget forbids net additions where they are most needed.**
   `agents/gsd-verifier.md` is **49,150 bytes against a 49,152 cap** (`tests/agent-size-budget.test.cjs:66`,
   tier LARGE). Two bytes of headroom. Any shared preamble fails the build.
3. **The correct "shared snippet" already exists and is a verb, not text.**
   `gsd_run query verification.resolve-file "$PHASE_DIR" --raw` (`src/verification.cts:834-853`,
   added by #3357/PR #3513 for exactly this class). Routing `gsd-verifier.md:85-86` through
   it is **7 bytes shorter** — which is what makes it viable under the cap. Push the rule
   into the CLI where a rule is available; use the portable idiom where it is not.

### Ordering within (i), and why the fixes split

The todo's own analysis establishes the sites do **not** want one mechanism — 9 × `cat`,
1 × `ls -la`, 2 × `ls -d`, plus one unrelated `PIPESTATUS` bug. Three separate concerns:

| Group | Sites | Fix |
|---|---|---|
| Content reads | 9 | shim + `${#ARR[@]} -gt 0`, or the `while IFS= read -r … < <(find …)` form (both measured 8/8 across bash 3.2.57 and zsh 5.9) |
| VERIFICATION | 1 | route through the existing `verification resolve-file` verb — no new idiom, and it fits the byte cap |
| `PIPESTATUS` | 1 (`audit-fix.md:145`) | `${PIPESTATUS[0]:-${pipestatus[1]}}` — different mechanism, carve out |

`complete-milestone.md` is the trap the todo flags: a shim at `:331` protects the loop at
`:335`, but the glob-array at `:369` is a **different fence** and unprotected. A file-level
"has the shim?" check gives a false pass. The lint (iii) must operate per-fence.

### (iii) the lint, last

`scripts/lint-unreachable-guard-drift.cjs:374` already scans
`['gsd-core/workflows', 'commands', 'agents', 'skills']` with a zero baseline and no
allowlist escape — the right surface and the right ratchet shape. A new
`lint-portable-glob-guard.cjs` should mirror it (precedent: #2351 shipped
`lint-portable-timeout.cjs` in the same PR as its fix). It lands last because a lint written
before the sites are fixed either starts non-zero or needs an allowlist that then has to be
unwound.

**Structural gap worth a separate item:** the todo documents that
`scripts/sync-runtime-launcher.cjs` and `tests/no-hardcoded-home-gsd-tools.test.cjs` scan
only `agents/` + `gsd-core/workflows/` — **`skills/` is in neither**, and nothing enforces
`commands/gsd/X.md` ↔ `skills/gsd-X/SKILL.md` body parity. That is why two byte-identical
copies of the broken `review-backlog` fence shipped undetected. Out of scope for the fence
PR; capture it.

---

## Q3 — The seam for surfacing a present-but-unresolvable pointer

### The seam is `output()` in `src/io.cts:144-165`.

Every verb's JSON goes through it. There is no competing universal decorator:
`withProjectRoot` (`src/init.cts:319`) is init-local — 30 uses in `init.cts`, 2 in
`docs.cts`, zero elsewhere. `output` is the only chokepoint every command already crosses.

### Data flow

```
CLI entry (gsd-tools.cjs:4150)
  resolveActiveWorkstream(..., { getStored: peekActiveWorkstream })
        │
        │  ws === null  BUT  diagnoseUnresolvedActiveWorkstream(cwd).present === true
        ▼
  [NEW] setWorkstreamResolutionNotice({ value, reason })   ← module-level, in io.cts
        │   (mirrors the existing setJsonErrorMode/_jsonErrorMode
        │    process-flag pattern at src/io.cts:246-254)
        ▼
  … dispatch … any verb … no plumbing …
        ▼
  output(result, raw, rawValue)  ← reads the notice, decorates
        │
        ├─ JSON branch:  result.workstream_unresolved = { value, reason }
        └─ raw  branch:  String(rawValue) unchanged  +  one stderr warning line
```

### Why capture at the CLI entry rather than at the self-heal

The todo frames this as *"when `resolveActiveWorkstream` self-heals … the response should
carry `workstream_pointer_cleared`."* Capture **non-resolution**, not clearing. Three
reasons:

1. **The entry no longer clears.** Since #3579 it passes `getStored: peekActiveWorkstream`
   (`:4151`) precisely so the bootstrap does not mutate. There is no clear event to observe
   there.
2. **Clearing is the wrong signal anyway.** `resolveFromChain:300-319` clears only
   `chain[0]`; a dangling *shared marker* read as a fallback is never cleared but is exactly
   as dangerous. `workstream_pointer_cleared` would be silent in the shared-marker case,
   which is the case my `workstream.complete` repro produces.
3. **`diagnoseUnresolvedActiveWorkstream` is already the right shape** — read-only,
   `{ present, value, reason }`, and it reuses `resolvesToExistingWorkstream` so *"this can
   never disagree with the actual resolution predicate"* (`active-workstream-store.cts:337-339`).

### Three constraints on the implementation

- **The field must be conditional.** Present only on actual non-resolution. Unconditional
  addition changes every exact-shape JSON assertion in a ~30,600-test suite.
- **`--raw` needs a separate path.** `output`'s raw branch emits `String(rawValue)` with no
  JSON envelope (`:146-149`). Raw callers — the majority of shell fences — need a stderr
  warning, not a field.
- **Do not route through the `@file:` spill.** The `>50000` redirection at `:152-158` is
  JSON-branch-only; a notice must not push a payload across that boundary. It won't (it is a
  two-field object), but state it so nobody adds the full diagnostic text later.

### Relationship to the fail-safe (§1)

These are complements, not alternatives, and they serve different verb classes:

| Verb class | Mechanism |
|---|---|
| **Mutating** (`state advance-plan`, `phase.complete`, `init.progress`) | §1 fail-safe — refuse |
| **Read-only** (`workstream get/list`, `audit`, statusline) | §3 notice — proceed, report |

That split is what makes (c) unnecessary in §1: the universal coverage (c) was reaching for
is delivered here, at the layer where it is non-destructive.

**Observability note carried over from the resync todo:** the same argument applies to
`readModifyWriteStateMd`'s derived writes. *"Emitting `progress: completed_phases 2 -> 3
(derived)` would turn a silent corruption into an obvious event, even when resync is
legitimately on."* Same seam, same shape, same PR family — worth planning as one
observability concern rather than two.

---

## NEW vs MODIFIED

### NEW

| Component | Location | Purpose | From |
|---|---|---|---|
| `requireResolvedWorkstream()` | `src/planning-workspace.cts` (near `:432`) | Shared fail-safe: predicate + two-arm branch + both messages | Q1 |
| `detectShells()` helper | `tests/helpers/` (new or existing helper file) | Cross-shell parameterization, lifted from `review-build-prompt-optional-sections.test.cjs:56-62` | Q2 |
| `scripts/lint-portable-glob-guard.cjs` | `scripts/` | Per-fence ratchet, modelled on `lint-unreachable-guard-drift.cjs` | Q2 |
| `setWorkstreamResolutionNotice()` / notice field | `src/io.cts` (near `:246-254`) | Non-resolution signal on the universal output seam | Q3 |
| `skills/gsd-handoff/SKILL.md` | `skills/` | Handoff-merge skill (does not exist yet) | todo `build-a-handoff-skill` |
| `skills/gsd-review-concurrent/`, `skills/gsd-graph/`, `agents/gsd-prd-reviewer.md` | repo | Local-only artifacts to be **imported** into the repo, not authored | todo `local-only-skills-destroyed` |

### MODIFIED

| Component | Location | Change |
|---|---|---|
| `cmdInitProgress` | `src/init.cts:2926-2956` | ~30-line guard → one helper call |
| `cmdPhaseComplete` | `src/phase.cts:2212-2242` | same |
| `cmdStateAdvancePlan` | `src/state.cts:658` | gains the helper call (supersedes WIP `f72f1534`) |
| `cmdWorkstreamComplete` | `src/workstream.cts:302-303` | clear the adapter actually resolved from (separate PR) |
| CLI entry | `gsd-core/bin/gsd-tools.cjs:4150-4155` | set the resolution notice on non-resolution |
| `output()` | `src/io.cts:144-165` | conditional decoration + raw-branch stderr |
| `readModifyWriteStateMd` callers | `src/state.cts:868, 1086, 1154, 1259, 1344`; `gsd-tools.cjs:1172` | `{ resync: false }` on body-only appenders |
| `unreachable-shell-guard.test.cjs` | `tests/` `:149` | `interpreter: 'bash'` → parameterized over `SHELLS` |
| 11 fence sites | `agents/`, `gsd-core/workflows/`, `commands/`, `skills/` | portable glob idiom |
| `agents/gsd-verifier.md` | `:85-86` | route through `verification resolve-file` (net −7 bytes) |
| `gsd-core/workflows/audit-fix.md` | `:145` | `PIPESTATUS` fallback |
| 27 flat-literal sites | 8 `gsd-core/workflows/*.md` | resolved workstream paths |
| `bin/install.js` | `:10820-10829` | stop the stale-skills wipe destroying local-only artifacts |

> **Tracked vs generated (re C1).** `gsd-core/bin/gsd-tools.cjs` is the **tracked** CLI entry
> and a legitimate edit target — both rows above that name it are correct.
> `gsd-core/bin/lib/*.cjs` is **generated** build output (`.gitignore:316`) and must never be
> hand-edited; it changes only by rebuilding from `src/*.cts`.

### UNCHANGED BY DESIGN

- `resolveFromChain`, `pickActiveWorkstreamAdapterChain`, `peekActiveWorkstream` — the
  resolution semantics are correct; the defect is that nothing *reports* the outcome.
- CLI-entry dispatch policy — no global refusal. (See Q1, rejection of (c).)
- `runHook`'s `interpreter` parameter — already the right seam.

---

## Q4 — Coupling and build order

### Collision map (derived from every pending todo's `files:` frontmatter, then source-read)

| Shared surface | Todos that touch it | Sequencing |
|---|---|---|
| **`cmdStateAdvancePlan`** — `state.cts:657` (guard) and `:679` (resync arg) | `state-advance-plan-fallback`, `body-only-state-md-writes-resync` | **Same function.** Hard sequence. Guard first (it gates whether the write happens at all), resync second. |
| **`planning-workspace.cts` / workstream resolution** | `state-advance-plan-fallback`, `route-workflow-files-through-resolved-workstream-paths` | Helper must exist before the workflow-routing sweep starts citing it. |
| **`gsd-core/workflows/pause-work.md`** | `fix-pause-work-s-broken-phase-glob` (12 sites), `route-workflow-files` (`:67`) | Same file, overlapping lines. Sequence. |
| **`gsd-core/workflows/quick.md`** | `escape-description-in-quick-md-7c`, `reconcile-hash-column-contract`, `route-workflow-files` (`:150`, `:469`) | Three todos, one file. The two `quick.md` table todos also share `src/markdown-table.cts` — merge or sequence. |
| **`gsd-core/workflows/review.md`** | `zsh-array-index-guards` (`:269-273`), `route-workflow-files`, `port-4-7` (`:295-300`) | Three-way. Fence fix first (it is the reference implementation). |
| **`gsd-core/workflows/ship.md`** | `route-workflow-files` (`:510,513`), `migrate-the-glab-forge-port` (`:90,364,461,497`) | Different regions but a large glab rewrite will conflict with a routing sweep. |
| **`src/markdown-table.cts`** | `escape-description-in-quick-md-7c` (`:701-707`), `reconcile-hash-column-contract` (`:710-716,737,762,765`) | Adjacent lines, same contract. Sequence or merge. |
| **`src/graphify.cts` `ExpandResult:280-285`** | `port-4-3`, `port-4-4` (both explicitly *"MUST be extended"*) | Same interface. **4.4 first** — it owns the interface change; 4.3 consumes it. |
| **`src/graphify.cts` `applyBudget`** | `port-4-3b` | Depends on 4.3 + 4.4 landing; it is the behaviour-changing commit of the block. |
| **`bin/install.js` stale-skills wipe** | `local-only-skills-destroyed` → **explicitly blocks** `port-4-8` (its own frontmatter: *"BLOCKS the routing half"*) | Installer fix strictly first. |
| **Fence harness** | gates the *verification* of `zsh-array-index-guards`, `port-4-10` (blocked on it), and any fence edit in `route-workflow-files` / `pause-work` | Strictly first among all fence work. |
| **`tests/helpers/process-seam.cjs` spawn seam** | `node-test-timeout-leaks-orphaned-grandchild`, plus every new cross-shell test (`local/no-unbounded-spawn` requires routing through it) | Leak fix should precede a harness that doubles the number of spawned shells. |

### Independent — parallelisable, no shared surface

`audit-open-counts-todos` (`src/audit.cts` only) · `port-4-2` (agent markdown call
signatures) · `port-4-6` (`hooks/gsd-statusline.js`) · `context-monitor-misattributes`
(`hooks/gsd-context-monitor.js`) · `build-a-handoff-skill` (new file).

### Recommended build order

Justified by the dependencies above — **not** by severity. Several `blocker`s land late
because they are gated; two `minor`s land early because they unblock others.

**Phase 1 — Instruments before repairs**
1. Build the tree so `gsd-core/bin/lib/*.cjs` stops disagreeing with `src/` (C1).
2. `node-test-timeout` subprocess-leak fix — the spawn seam is about to carry double load.
3. **Cross-shell harness**: lift `detectShells()`, parameterize
   `unreachable-shell-guard.test.cjs:149`. Expect it to go red against the 11 sites; that is
   the deliverable.
4. `bin/install.js` stale-skills wipe + import the three local-only artifacts.

*Rationale: nothing here fixes a reported defect. Every item makes a later fix verifiable
(3), survivable (4), or honest (1). Item 3 in particular cannot be reordered after the site
fixes without the site fixes being unverified.*

**Phase 2 — The workstream resolution chain**
5. `requireResolvedWorkstream` helper + corrected precondition at `init.cts:2926` and
   `phase.cts:2212` (PR-A).
6. Apply to `state advance-plan` (PR-B); reconcile/supersede WIP `f72f1534`.
7. `output()` non-resolution notice (Q3 seam).
8. *(Optional, independent)* `cmdWorkstreamComplete` marker-clearing fix (PR-C).

*Rationale: 5 before 6 — the helper must exist. 7 after 5-6 — the notice complements the
guard and its verb-class split only makes sense once the guard defines the mutating class.
8 is independent and can float.*

**Phase 3 — STATE.md write path**
9. `resync: false` on the five body-only appenders + `gsd-tools.cjs:1172`.
10. Decide the three `{ divergedFields }` sites, including `cmdStateAdvancePlan:679`.

*Rationale: strictly after 6 — same function. Also visible in my Phase-1 repro output: the
same silent `advance-plan` call that mutated root STATE.md **also** rewrote its `progress`
block to `total_phases: 1, total_plans: 0, completed_plans: 0` from a disk scan. Both
defects fire in one call; fixing the write path before the routing would mean correctly
resyncing the wrong file.*

**Phase 4 — Fence portability (harness is green-capable from Phase 1)**
11. The 9 content-read sites — portable glob idiom.
12. `gsd-verifier.md:85-86` → `verification resolve-file` verb.
13. `audit-fix.md:145` `PIPESTATUS` (separate concern, separate PR).
14. `scripts/lint-portable-glob-guard.cjs` ratchet.
15. `port-4-10` (mempalace recall line) — explicitly blocked on 11.

**Phase 5 — Workflow markdown routing**
16. `route-workflow-files-through-resolved-workstream-paths` (27 sites, 8 files).
17. `pause-work` phase glob + dead gate (overlaps 16 at `:67`).
18. The `quick.md` pair — `escape-description` then `reconcile-hash-column` (shared
    `markdown-table.cts`).

*Rationale: after Phase 4 — several of these files are fence edits and must land on a tree
where the harness can see them. After Phase 2 — the routing sweep consumes resolved paths
whose correctness Phase 2 establishes.*

**Phase 6 — Port campaign remainder**
19. `port-4-4` (`ExpandResult` interface) → `port-4-3` (scoring) → `port-4-3b` (seed-floor
    invariant + the CI blind spot). Strict order; same file, same interface.
20. `port-4-8` (convergence routing) — unblocked by Phase 1 item 4.
21. `port-4-7` (review-lane timeouts, incl. `review.md:295-300`) — after Phase 4's
    `review.md` fence work.
22. `migrate-the-glab-forge-port` — largest `ship.md` change; last to minimise conflicts
    with Phase 5's routing sweep.

**Anytime — no dependencies**
`audit-open-counts-todos` · `port-4-2` · `port-4-6` · `context-monitor-misattributes` ·
`build-a-handoff-skill`.

---

## Patterns to follow

**Extract the predicate, not just the data.** `listAvailableWorkstreams` was extracted for
these two guards and still left the predicate duplicated — which is how the same wrong
precondition reached three files. When consolidating for a fail-safe, the unit is the whole
decision.

**Read-only diagnostic siblings.** `peekActiveWorkstream` / `diagnoseUnresolvedActiveWorkstream`
sit beside `getActiveWorkstream` and share `resolvesToExistingWorkstream` so they *cannot*
disagree. Any new resolution question gets a sibling, never a re-derivation.

**Ratchet lints ship with their fix.** #2351 shipped `lint-portable-timeout.cjs` in the same
PR. `lint-unreachable-guard-drift.cjs:374` is the shape to copy — four scan dirs, zero
baseline, no allowlist escape.

**Tests bind to the shipped artifact.** `unreachable-shell-guard.test.cjs` extracting live
fences is right and should be preserved; only the interpreter is wrong.

## Anti-patterns to avoid

**DEFECT.GENERATIVE-FIX / Generative Fix Divergence** — the codebase's own name (see
`planning-workspace.cts:180`, `:429-431`). Two copies of a rule diverge. Three copies of a
*wrong* rule is this milestone's headline defect.

**Testing against a shell nobody runs.** The bug survived four upstream fix rounds because
the instrument was bound to the deployed contract but validated against the wrong dialect.
Generalizes: verify the *runtime*, not a convenient stand-in.

**Fixing by imitation.** `gsd-tools.cjs:1166-1167` — *"This mirrors the pattern every other
STATE.md-mutating case in state.cts uses (e.g. `cmdStateAddBlocker`, `cmdStateAddDecision`)"*
— both cited exemplars carry the defect. When a comment cites siblings as justification,
check the siblings.

**Fail-safes at the dispatcher.** Refusal belongs where the mutation happens. A read-only
verb must survive broken state so the state stays diagnosable (#2850).

---

## Confidence

| Area | Level | Basis |
|---|---|---|
| C1 (state.cts has no guard on HEAD) | HIGH | `grep`, `git show f72f1534`, `git check-ignore` |
| C2 (which case is dead) + `workstream.complete` generator | HIGH | Three-mode fixture + end-to-end repro against the built CLI, output quoted |
| Q1 predicate (7-scenario table) | HIGH | Executed against built `planning-workspace.cjs` |
| Q1 (b) vs (c) portability argument | MEDIUM-HIGH | Four in-repo precedents + `CONTRIBUTING.md:52`; maintainer reception is a judgement |
| Q2 harness-first | HIGH | `test.yml:452-462` zsh lanes + `:149` hardcoded bash + the `detectShells` precedent |
| Q2 site-fix idioms | MEDIUM-HIGH | Inherited from the todo's 8/8 cross-shell measurement; not re-measured here |
| Q3 seam | HIGH | `output()` is the sole universal emitter; `withProjectRoot` usage counted |
| Q4 collision map | MEDIUM | Todo frontmatter + targeted source reads; graphify and installer chains not executed |

## Gaps for phase-level research

- **Will maintainers accept a knowingly-red harness PR?** Determines whether Q2 items 3 and
  11 are one PR or two. Process question.
- ~~Changeset type for a test-only PR.~~ **Answered.** `scripts/changeset/lint.cjs:30-40`
  lists `USER_FACING_PREFIXES` as `bin/ gsd-core/ src/ agents/ commands/ hooks/`, with the
  comment *"Test/CI/docs/lock files do not"* require a fragment. **A tests-only harness PR
  needs no changeset.** Site-fix PRs touching `agents/`, `gsd-core/`, `commands/` do —
  `--type Fixed` (`Fixed` is absent from `TRIGGERING_TYPES`, `scripts/lint-docs-required.cjs:37`,
  so the docs-required gate is a no-op).
- **zsh availability on `ubuntu-latest`.** The probe skips gracefully, but if Linux lanes
  silently skip every zsh row the coverage rests on the three macOS shards alone. Verify.
- **The `{ divergedFields }` decision** (three sites) is a genuine open design question, not
  a mechanical fix. Needs its own discussion before Phase 3 item 10.
- **Row 6 of the Q1 table** — `workstreams/` present-but-empty, no pointer. Left unchanged;
  confirm that is the intent.
- **`skills/` excluded from three scanners** (`sync-runtime-launcher.cjs`,
  `no-hardcoded-home-gsd-tools.test.cjs`, and the lint) with no `commands/` ↔ `skills/`
  parity check. Not yet a captured todo.
