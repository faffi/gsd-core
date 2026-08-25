# Pitfalls Research

**Domain:** defect-fixing in a mature, heavily-tested TypeScript/Node CLI toolchain that is also a
fork feeding single-concern PRs upstream
**Researched:** 2026-08-24
**Confidence:** HIGH for the mechanism claims (every one measured in this repo or cited to current
official docs); MEDIUM for the process/triage recommendations (industry practice, not measurable here)
**Milestone:** v1.12 — 22 captured defects, gsd-core 1.11.0, ~30,600 tests

---

## How to read this document

Four failure modes have **already happened in this project**. They are not hypotheticals, and they
are not four unrelated mistakes — they are four instances of one meta-pattern:

> **A verification surface (a test, a guard, a count, an issue tracker) reports on a proxy for the
> thing that matters, and the proxy agrees with reality in every case anyone has looked at.**

- the fence test executes under `bash`, a **proxy** for the login shell (verified this session: the
  Bash tool runs `/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset)
- the workstream guard counts **directories**, a proxy for "a workstream is in play"
- `workstream complete` reports `reverted_to_flat` from what it **attempted**, a proxy for what the
  filesystem now holds
- upstream's issue tracker records **symptoms**, a proxy for causes

Every prevention strategy below is a variant of the same move: **replace the proxy with a direct
observation, and make the harness run where the code runs.** Warning signs are written so you can
notice the pattern in *this* repo, with grep-able specifics.

Each pitfall carries a **phase topic** rather than a phase number — `ROADMAP.md` does not exist
yet. Topics key to PROJECT.md's target features. **Several of these are ordering constraints, not
review-time checklist items** — see [Ordering constraints](#ordering-constraints-read-this-first).

---

## Ordering constraints (read this first)

Three pitfalls below cannot be prevented by review. They constrain phase *order*:

| Constraint | Why | Consequence of getting it wrong |
|---|---|---|
| **Cross-shell harness lands before or inside the fence-fix phase** | Under a bash-only harness the fix is unverifiable at the moment it ships | Four upstream rounds (#2770 → #2962 → #3300 → #3409) are the empirical proof that a green bash harness does not gate this class |
| **Survivor assertion lands before or with the `--test-isolation` change** | The current test asserts the parent's verdict and passes while leaking a core | The next refactor regresses it silently — same shape as the bug being fixed |
| **Shared precondition is extracted before the call sites are fixed** | Two copies exist and a third site has none | Fixing them in place produces a third copy and a fourth divergence |

A roadmap that orders "fix the fences" before "make the harness see zsh" ships the same defect
class again with a green suite.

---

## Critical Pitfalls

### Pitfall 1: The harness diverges from production in exactly the dimension under test

**What goes wrong:**
`tests/unreachable-shell-guard.test.cjs` extracts the *live* fences out of shipped `.md` files —
the right instinct, it binds to the deployed contract — then writes them to a temp script with a
hardcoded `#!/usr/bin/env bash` and runs them via `runHook(scriptPath, [], { interpreter: 'bash' })`
(`tests/unreachable-shell-guard.test.cjs:148-150`). Production executes those same fences under the
user's login shell. Measured live in this session: `$0=/bin/zsh`, `ZSH_VERSION=5.9`,
`BASH_VERSION` unset. The test therefore validates a real artifact against a shell nobody runs it
in. Every guard passes; every guard is dead where it executes.

This is not one test's mistake. **57 call sites across `tests/` pass `interpreter: 'bash'`.**

**Why it happens:**
The harness silently supplies, for free, the exact property the assertion claims to check. Under
bash, `${ARR[0]}` is the first element and an unmatched glob expands to itself — so the guard's
shape is *correct* there, and the test is honestly reporting on the environment it was given. The
literature's name for this class is a **vacuous** (non-falsifiable) test; the sub-class is an
**environment-parity** failure. Documented analogues: a test harness whose Docker image pinned
`TZ=UTC`, so a query missing `AT TIME ZONE 'UTC'` could never be caught; a build sandbox using
`fakeowner`, where `chmod 0444` does not stop the owner writing, so an error-path test passed
without any error ever occurring.

The repo already contains the contradiction in writing: `tests/policy-shell-pinning.test.cjs`
enforces `shell: zsh` on macOS CI jobs (its counter-test is literally
`MACOS_MISSING_EXPLICIT_ZSH`, `:89-90`) — **the repo's own CI policy knows macOS is zsh while the
fence harness runs bash.**

**How to avoid:**
1. **Parameterize the fence harness over interpreters, not the whole test suite.** Turn
   `runBashScript(t, script)` into a runner that loops `['bash', 'zsh']` and asserts the same
   outcome under both. `runHook`'s `interpreter` option already exists and is documented as
   deliberately explicit (`tests/helpers/process-seam.cjs:221-235`), and
   `tests/pause-work-improvements.test.cjs:287,326` **already spawn zsh** — this extends an in-tree
   pattern rather than introducing one. Do **not** propose converting all 57 sites; that is a
   repo-wide refactor, violates "one concern per PR" (`CONTRIBUTING.md:195`), and doubles CI.
2. **Prove the harness can fail before trusting it.** Run the parameterized harness against the
   *unfixed* fence and require RED under zsh, GREEN under bash. A cross-shell harness that is green
   on both before the fix is measuring nothing.
3. **Do not reach for a linter to cover the zsh half.** ShellCheck's supported dialects are
   `sh`, `bash`, `dash`, `ksh`; the SC1103 wiki states plainly that *"One notable unsupported shell
   type is zsh, see issue #809"* (still open as koalaman/shellcheck#2648). A lint ratchet is worth
   shipping as a *drift guard*, but it cannot verify zsh behaviour — only execution can.
4. **Write down the harness↔runtime binding.** Any new fence-executing test states, in a comment,
   which shell the runtime uses and why the test uses that one.

**Warning signs:**
- A test file writes `#!/usr/bin/env bash` into a fixture that came from a *shipped* `.md`
- `interpreter: 'bash'` in a test whose subject is executed by an agent, not by a `.sh` file with
  its own shebang
- A defect survives multiple fix rounds while the suite stays green (the tell that finally exposed
  this one)
- A CI policy test and a behavioural test disagree about the platform's shell

**Phase to address:** **Cross-shell test harness** — must precede or contain the fence-portability
phase. Not a review gate; a prerequisite.

---

### Pitfall 2: N copies of a guard share one untested precondition — and the site with *no* copy is worse

**What goes wrong:**
The workstream fail-safe exists in two places, byte-for-byte in shape:
`src/init.cts:2926-2955` (`cmdInitProgress`, #1912) and `src/phase.cts:2212-2241`
(`cmdPhaseComplete`, #2028 — its own comment says *"Mirror the #1912 guard"*). Both gate on
the same precondition:

```ts
const availableWorkstreams = listAvailableWorkstreams(cwd);
if (availableWorkstreams.length > 0 && !resolvedWorkstream) { /* refuse */ }
```

`listAvailableWorkstreams` (`src/planning-workspace.cts:151-161`) is a `readdirSync` filtered to
`isDirectory()`. So the precondition actually means *"at least one workstream **directory** still
exists on disk"* — a proxy for *"a workstream was requested"*. When the pointer names a workstream
whose directory is gone, the count is 0, the guard never arms, and root `.planning/STATE.md` is
written silently.

**Correction to the brief:** `src/state.cts` does **not** carry a third copy.
`cmdStateAdvancePlan` (`src/state.cts:656-657`) goes straight to `planningPaths(cwd).state` with no
precondition at all. Two copies plus one unguarded site — which is *why* `advance-plan` is the
command that silently falls through to root. The clone hazard and the missing-clone hazard have
**different warning signs and one shared fix.**

Both copies were invisible because every existing fixture had at least one surviving workstream
directory — the equivalence class "pointer set, directory absent" was never in the corpus.

**Why it happens:**
This is the studied phenomenon of **inconsistent clones**. Juergens, Deissenboeck, Hummel & Wagner,
*"Do code clones matter?"* (ICSE 2009) manually assessed ~900 clone groups across five systems and
confirmed **107 developer-acknowledged faults** caused by inconsistent changes to clones; the paper
names the *inconsistent bug fix* — fault repaired in one instance, left in the others — as the
most dangerous shape. The `#3579` follow-up comments in both files are exactly that: a fix
propagated to two of three sites.

**How to avoid:**
1. **Extract before you fix.** One exported predicate — e.g. `requireResolvedWorkstream(cwd, opts)`
   — returning a typed verdict, called from all three commands. This is a pattern the repo already
   sanctions: `#3357 → PR #3513` collapsed *seven* copies of the verification-file rule onto one
   exported `resolveVerificationFile`, and gave the shell copies a `verification resolve-file` verb
   "rather than hand-rolling the rule an eighth time."
2. **Fix the precondition, not just the copies.** The correct question is not *"do workstream
   directories exist?"* but *"was a workstream named (via `--ws`, `GSD_WORKSTREAM`, session pointer
   or shared marker), and did it resolve?"* A named-but-unresolvable pointer must refuse **even
   when zero directories remain** — that is the case the current form gets wrong in both copies.
3. **Test the predicate as a contract, once, over a matrix of call sites.** A parameterized test
   that runs `[init.progress, phase.complete, state.advance-plan] × [no pointer, valid pointer,
   dangling pointer, pointer + zero dirs, `--ws` override]` — 15 cells — catches the next site that
   forgets to call it. Assert the **`reason` code**, not prose: `ERROR_REASON.WORKSTREAM_MODE_NONE_ACTIVE`
   and `WORKSTREAM_MODE_MARKER_UNRESOLVED` already exist (`src/io.cts:199-200`), which keeps this
   inside the repo's "assert on typed structured values" rule (`CONTRIBUTING.md`, *Prohibited: Raw
   Text Matching*).
4. **Before fixing any defect, grep for the shape, not the symptom.** `grep -n "listAvailableWorkstreams" src/*.cts`
   takes two seconds and is the whole prevention. Do it for every fix in this milestone.

**Warning signs:**
- A comment that says *"Mirror the #NNNN guard"* — that is a clone announcing itself
- A helper with 2–3 call sites and no test that iterates them
- Every fixture for a feature exercises the same side of a boundary (here: projects that always
  had ≥1 workstream)
- A sibling command that *should* have the guard and does not

**Phase to address:** **Workstream fail-safe precondition** — the extraction is step one of that
phase, not a refactor to schedule later.

---

### Pitfall 3: A swallowed cleanup failure composed into a later correctness decision

**What goes wrong:**
`src/workstream.cts:332-338`:

```ts
try { fs.rmdirSync(wsDir); } catch { /* ignore */ }
let remainingWs = 0;
try {
  remainingWs = fs.readdirSync(wsRoot, { withFileTypes: true }).filter(e => e.isDirectory()).length;
  if (remainingWs === 0) fs.rmdirSync(wsRoot);
} catch { /* ignore */ }
```

then reports `remaining_workstreams: remainingWs, reverted_to_flat: remainingWs === 0`.

Measured on this machine (Node 22.23.2, macOS): with a single `.DS_Store` in `wsRoot`,
`rmdirSync(wsRoot)` throws **`ENOTEMPTY`**, the throw is swallowed, `wsRoot` survives holding only
the dotfile — while the directory count that decided the outcome is **0**. The command reports
`reverted_to_flat: true` about a directory it did not remove. Node's own docs confirm the shape:
`rmdirSync` is non-recursive (the `recursive` option is deprecated, DEP0147) and the `rm -rf`
equivalent is `fs.rmSync(path, { recursive: true, force: true })`.

The same `isDirectory()` residue then feeds Pitfall 2's precondition. The `.DS_Store` variant is
not exotic here: `.DS_Store` already breaks 20 install-attribution tests in this repo because the
installer copies with `fs`, not git.

**Why it happens — and what the guidance actually says:**
The naive reading ("empty catch bad, CWE-390 *Detection of Error Condition Without Action*") is
correct as far as it goes, and Google's Error Prone `EmptyCatch` plus Google Java Style §6.2 say
*"it is very rarely correct to do nothing in response to a caught exception"* — but **cleanup paths
are the documented exception.** Raymond Chen, *"Since clean-up functions can't fail, you have to
soldier on"* (2014): a cleanup routine frequently has nowhere to report and must not abandon the
rest of the cleanup; aborting on the first failure is how you *"leak gadgets like crazy"*.

So the defect is **not the swallow**. The defect is that a swallowed cleanup failure was allowed to
become an input to a correctness decision and to a reported field. And note the local constraint:
`eslint.config.mjs` sets `'no-empty': ['warn', { allowEmptyCatch: true }]` at three places —
lint change is maintainer-owned config and a **separate concern**, not part of this fix.

**How to avoid:**
1. **Assert the postcondition; report the observation.** After cleanup, `fs.existsSync(wsRoot)` /
   `readdirSync` and derive `reverted_to_flat` from **what is true**, not from what was attempted.
   A field that describes intent rather than outcome is the bug.
2. **Narrow every catch you keep.** `catch (e) { if (e.code !== 'ENOENT') { /* record */ } }` —
   `ENOTEMPTY` is *information*, `ENOENT` is *already done*. Collapsing them is what erased the
   signal.
3. **Surface non-fatal residue in the JSON contract** (`residual_paths: [...]` or similar) so a
   caller — human or agent — can see it. Silent recovery is fine; silent recovery with zero signal
   to a caller who expected a specific outcome is not (this is the same remedy the `advance-plan`
   todo proposes for the self-healed pointer).
4. **Never infer mode from filesystem residue.** "Is a workstream active" must come from the
   pointer chain, not from a directory count that a swallowed `rmdir` can falsify.
5. **Fixture hazard:** a test that plants `.DS_Store` must clean it up in `afterEach`, or it
   reddens the 20 install-attribution tests. Plant it under a temp fixture, never under
   `gsd-core/`.

**Warning signs:**
- `catch { /* ignore */ }` within ~10 lines of a count, a boolean, or a returned field
- A reported field computed *before* the operation it describes (`remainingWs` is computed, then
  `rmdirSync` runs, and `remainingWs` is what gets reported)
- `filter(e => e.isDirectory())` used as a proxy for emptiness
- Any `rmdirSync` that is not `rmSync({recursive, force})` and is not checked

**Phase to address:** **Workstream fail-safe precondition** (same phase — the two defects compose,
and fixing only the guard leaves `workstream complete` still lying about `reverted_to_flat`).

---

### Pitfall 4: Four symptoms, one cause — fragmenting the fix and never landing it

**What goes wrong:**
Upstream filed #2770 → #2962 → #3300 → #3409 as four separate issues. #2962 fixed unmatched globs
in `for` word lists; its nullglob shim then *caused* #3300; #3409 introduced the array-index form
that is broken under zsh in a new way. Four rounds, four green suites, one unfixed root cause:
**shipped fences are authored for bash and executed under zsh.** `gsd-core/workflows/review.md:248-273`
— the file #3300 was filed against — is the single fully-correct instance in 1048 fences, and the
pattern was never propagated.

**Why it happens:**
Symptom-driven triage with no explicit escalation trigger. ITIL names this split exactly:
**incident management** (restore, per symptom) versus **problem management**, where *a problem is
"a cause, or potential cause, of one or more incidents."* The documented failure mode is precisely
this one — teams that leave the escalation trigger informal *"do not start the investigation until
the fifth or sixth recurrence."* Practice recommends a hard numeric trigger (e.g. three reports in
30 days sharing category or error signature auto-creates a problem record), a record **linked to
every triggering symptom**, structured RCA, and a Known Error entry even before the permanent fix.

**The counter-risk is real and must be held simultaneously.** Merging genuinely distinct issues
produces an unreviewable diff. `CONTRIBUTING.md:195` (*"One concern per PR"*) and `:199` (*"Scope
matches the approved issue"*) will reject it, and QA-triage practice says a defect "of 100+ parts"
should be treated as a project and decomposed. The zsh todo already did this decomposition
correctly and it is worth copying as the method: **one cause, six mechanisms, and the mechanisms
carved apart on the basis that they do not want the same code change** —
`audit-fix.md:145` (`PIPESTATUS`, uppercase, does not exist in zsh in any form) is carved out as
its own one-line fix; `read -ra` (a hard error in zsh) and `BASH_REMATCH[N]` are separate; the nine
`cat`-shaped glob sites are one fix.

**How to avoid:**
1. **Write the cause down as a first-class artifact.** `.planning/reference/shell-fence-portability.md`
   already is the Known Error record for this cause. Keep the rule the todo states: *update that
   document in the same commit as any fix.*
2. **Apply an explicit trigger.** Two or more captured todos naming the same file, the same
   primitive, or the same shell → stop and write the cause down before writing code.
3. **Split by "does this want the same edit?", never by "is this the same file?"** Same edit → one
   PR. Different edit → different PR, both linked to the one cause. That criterion, not issue
   count, decides the split.
4. **Cause-completeness check before closing:** *"if this cause were fully fixed, which of the
   captured symptoms would still reproduce?"* Any survivor means the split was wrong, not that a
   fifth item should be filed. The zsh sweep — 1048 fences, 6413 lines — is what this looks like
   done properly; a fix that only visits the reported sites is how #2962 begat #3300.

**Warning signs:**
- Two todos citing the same file or the same shell primitive
- A fix whose own commit message references a previous fix for "the same area"
- A closed upstream issue whose file is still broken (`review.md` is CLOSED and still wrong)
- A fix that changes the *shape* of a construct without changing which shell interprets it

**Phase to address:** **Shell fence portability** for this instance; the trigger rule belongs in
capture/triage practice for the whole milestone.

---

### Pitfall 5: Tightening a guard so it refuses where it previously proceeded

**What goes wrong:**
The workstream fix makes `state advance-plan`, `init.progress` and `phase.complete` refuse in
situations where they previously returned exit 0. Every refusal is indistinguishable, at the
call-site level, from a regression: the caller sees a non-zero exit where it used to see success.
Agents and workflows call these verbs unattended, so a wrongly-armed guard does not produce a bug
report — it produces a stalled workflow.

Compounding risk specific to this change: the guard must arm **more** often (dangling pointer, zero
directories) *and* must not arm where it currently does not — and the two directions are decided by
the same predicate.

**Why it happens:**
Validation strengthening against pre-existing state. The general recipe from practice is
widen-then-verify-then-narrow: attach the stricter rule in warn/soft-fail mode, measure who trips
it, remediate, then enforce (MongoDB's `validationAction: "warn"` before `"error"`; APM's policy
`enforcement: warn` before `block`; staged API validation with a machine-readable
`VALIDATION_WILL_FAIL_SOON` code). Skipping the measurement step is what turns a one-line tightening
into a fleet-wide failure.

**How to avoid — adapted to a single-developer CLI, where a soft-fail telemetry window is not
available:**
1. **Enumerate the accept set as characterization tests *before* the change.** Write tests that
   pin today's behaviour across the matrix in Pitfall 2 — including the cells you intend to flip.
   Then flip those cells' expectations in the same commit as the fix. The diff of that test file
   **is** the blast radius, reviewable in one screen. The repo already sanctions recording
   known-broken behaviour honestly rather than skipping the assertion (`CONTRIBUTING.md`, fixture
   provenance #2371: record `currentBuggyOutput`, assert against it, flip when the fix lands).
2. **Make the new refusal machine-distinguishable.** Every new refusal exits with a specific
   `ERROR_REASON` (the two workstream reasons already exist) and names the resolution
   (`Pass --ws <name> or run /gsd:workstream set …` — the existing messages do this; keep it).
   A regression is then "wrong reason code", not "non-zero exit" — a testable distinction.
3. **Grep the callers before arming.** Workflow and agent `.md` files call these verbs; a guard
   that arms in a state some workflow routinely reaches will stall it. `grep -rn "state advance-plan\|init.progress\|phase.complete" gsd-core/workflows agents commands skills`
   is the blast-radius survey.
4. **Prefer refusal over silent fallback, and say so in the changeset.** Fail-closed is the
   deliberate choice here (root-STATE.md corruption is worse than a stalled command) — record it as
   a decision so a future reader does not "fix" the refusal.

**Warning signs:**
- A predicate change that flips both directions at once with no test naming each direction
- A guard whose only test is the happy path plus one refusal
- Error text that does not tell the caller how to proceed
- A workflow that starts failing in a phase unrelated to the fix

**Phase to address:** **Workstream fail-safe precondition**; the characterization-tests-first
sequencing is a phase-plan step, not a review item.

---

### Pitfall 6: "Verified" for a shell-portability fix that does not mean what it must mean

**What goes wrong:**
A fix is declared verified because it was exercised in one shell, or because a lint passes, or
because CI is green. For this constraint set — bash 3.2.57, zsh 5.9, POSIX `sh` — each of those is
insufficient in a different way, and one of them is actively misleading.

Measured on this machine:

| Interpreter | What it actually is | What testing it proves |
|---|---|---|
| `/bin/bash` | GNU bash **3.2.57(1)** (arm64-apple-darwin25) | the macOS system-bash leg — genuinely useful, and it is *not* a Homebrew 5.x |
| `/bin/zsh` | zsh **5.9** | the login-shell leg — the one production uses |
| `/bin/sh` | reports `BASH_VERSION=3.2.57` | **bash in sh-emulation mode, not a POSIX sh.** A "tested under sh on macOS" claim does not cover dash |

So the POSIX leg **is not verifiable on this machine at all** — real `dash` exists only on the
ubuntu CI lane. And ShellCheck cannot lint the zsh leg (SC1103: supported dialects are
`sh`/`bash`/`dash`/`ksh`; zsh is explicitly unsupported, issue #809 / #2648).

A second, subtler version of the same error: local Node here is **v22.23.2** against a documented
`>=24` floor. Any claim about test-runner or child-process behaviour measured locally reproduces
Pitfall 1 one level up — the harness (Node 22) diverging from production (Node 24) in the dimension
under test.

**How to avoid:**
1. **Define "verified" as a matrix with named cells, and put it in the plan.** For each fix site:
   `{bash 3.2.57, zsh 5.9} × {glob matches, glob does not match, multiple files, spaces in names,
   missing directory, empty variable}` — the zsh todo's 8/8 matrix is the model; reuse its shape.
2. **State the POSIX leg's evidence source explicitly.** Either "covered by the ubuntu CI lane
   (dash)" or "not exercised — the construct avoids `sh` entirely". Do not let the macOS `/bin/sh`
   run stand in for it.
3. **Pin the runtime in the verification recipe.** `nvm use` / Node 24 before any test-behaviour
   claim; the repo's `.nvmrc` and `npm run check:env` exist for this.
4. **Prefer constructs that need no shell-detection.** The repo's documented policy is portable
   `while IFS= read -r` loops over `mapfile` because *"macOS ships with bash 3.2"*
   (`gsd-core/workflows/code-review.md:668-669`). A fix that sets a **global** shell option
   (`setopt NULL_GLOB`) reintroduces #3409's G4 defect — an option left set by an earlier block in
   the same shell session. Prefer the form that cannot leak state.
5. **Byte-budget check before touching agent files.** `agents/gsd-verifier.md` is **49,150 bytes
   against a 49,152 cap** (`LARGE_CAP` in `tests/agent-size-budget.test.cjs:58`) — **2 bytes of
   headroom.** Any net-additive fence fix there fails the build. Routing that site through the
   existing `verification resolve-file` verb is 7 bytes *shorter*, which is why it is the only
   viable shape.
6. **Suppression is not portable either.** `2>/dev/null` cannot suppress zsh's NOMATCH message —
   it is emitted during word expansion, before the command and its redirections exist. Only
   `{ …; } 2>/dev/null` suppresses it. A "verified quiet" claim tested under bash is wrong here.

**Warning signs:**
- A verification note that says "tested locally" without naming shell versions
- `shellcheck` cited as evidence for a zsh behaviour
- A fix that adds bytes to `gsd-verifier.md`, `gsd-planner.md` or any LARGE-tier agent
- Any behavioural claim about `node:test` made from a Node 22 run

**Phase to address:** **Shell fence portability**, with the matrix defined in the phase plan's
verification section — not discovered at review time.

---

### Pitfall 7: Killing a subprocess *tree* on timeout — the bound reaches one PID

**What goes wrong:**
`DEFECT.UNBOUNDED-SUBPROCESS` was fixed with `execFileSync(..., { timeout })`. That bounds the
**verifier's wait**, not the **process tree**. `buildNodeTestArgs` (`src/prohibition-enforcement.cts:220-222`)
spawns `node --test --test-reporter=tap -- <file>`; Node's test runner then forks the test file into
a *second* child. The timeout signals the runner; the grandchild is reparented to `launchd` and
spins. Measured 2026-08-22: two orphans, **~90% of a core each for 34 hours**, killed instantly by
a plain `SIGTERM` — so no JS handler was queuing the signal, it was simply never delivered to that
PID.

Node's own documentation carries this exact hazard as a worked example titled *"Signal propagation
limitations in shell processes"*: `subprocess.kill()` on a spawned `sh -c 'node -e …'` **does not
terminate the node grandchild**. Escaping it requires `detached: true` (child becomes leader of a
new process group) plus `process.kill(-pid)`. Separately, the v24 test-runner docs confirm
`--test-isolation` **defaults to `'process'`**, that each test file runs in a separate child
process, and that spawned children **inherit Node options from the parent** — which is exactly why
the survivor's argv is the fully-expanded flag set.

**Why it happens:**
"Bounded" is read as a property of the call, when it is a property of one PID. `execFileSync`'s
`timeout` is honest about what it does; the mental model isn't. A second trap compounds it:
cleanup written on the last line of a process that may itself be killed is not cleanup — the same
session found 18 unrelated shells leaked the same way (`kill $LOADPIDS` on a happy path whose
parent died first).

**How to avoid:**
1. **Remove the extra level rather than chasing it.** `--test-isolation=none` puts the test file in
   the process `execFileSync` actually signals; the docs confirm files are then *imported into the
   main runner process*. This keeps the library synchronous and shell-free — no `spawn` +
   `detached` + `process.kill(-pid)` rewrite, no `pkill`, no Windows divergence. Each check spawns
   exactly one file, so per-file isolation buys nothing being used. Known side effect, per the
   docs: with isolation `none`, `--test-concurrency` is ignored and concurrency is forced to 1 —
   irrelevant at one file per spawn.
2. **Re-verify the boundary the change moves.** With isolation `none` the target file shares
   globals with the runner: confirm the `GSD_PROHIB_SUBJECT` convention (#1279) and `childEnv()`'s
   `NODE_TEST_CONTEXT` / `NODE_OPTIONS` stripping still behave. That stripping exists to stop an
   ambient runner context corrupting the verdict, and this change moves the wall it guards.
3. **If a tree-kill is ever chosen instead, remember the pipes.** A grandchild inheriting the
   stdout pipe keeps it open after the direct child dies, so a synchronous call can block past its
   own timeout. `detached` + `stdio: 'ignore'`/explicit fds is the shape that avoids it.
4. **Sweep siblings.** Both `node-test` spawn sites share the shape
   (`runNodeTestWithSubject:476`, `defaultRunCheck:496`) and the default bound is
   `NODE_TEST_TIMEOUT_MS = 30_000` — so *any* genuinely stuck wired check leaks a core-burner in
   normal operation, not just the hang fixture.

**Warning signs:**
- `execFileSync`/`spawnSync` with `timeout` where the command is itself a runner, a shell, or
  anything with `--test`, `-c`, `npm run`, `xargs`
- A machine whose load average exceeds its core count after a test run
- `ps -eo pid,ppid,etime,command | grep <fixture-prefix>` showing `PPID 1`
- Cleanup written as the last statement of a process that can be killed

**Phase to address:** **Bounded-subprocess / test-infrastructure**, sequenced with Pitfall 8.

---

### Pitfall 8: The test that proves the bound works asserts the wrong side of the boundary

**What goes wrong:**
`tests/prohibition-enforcement.test.cjs:698-699` asserts `result.status !== 'green'` and
`result.located === true`. Both pass. The **parent's verdict is genuinely correct** — it did fail
closed. Nothing in ~30,600 tests ever looks for a survivor, so the suite is green while leaking a
core on every run. The test that exists to prove the bound works is the single biggest leaker.

Then the evidence erases itself: `t.after(() => cleanup(dir))` at `:688` deletes the temp directory
while the orphan still holds it as `cwd`. `ls` shows nothing; only `lsof -p <pid>` reveals
`cwd → /…/prohib-hang-…  (deleted)`.

**Why it happens:**
Same root as Pitfall 1 — the assertion covers a proxy (the verdict) for the property that matters
(no survivor). It is the textbook case for the mutation-testing question *"if I broke the thing
this test protects, would it go red?"* Here: revert the isolation flag and the test stays green.

**How to avoid:**
1. **Assert the absence of a survivor, not the presence of a verdict.** Snapshot matching PIDs
   before, run, then assert nothing matching the fixture path is alive after
   `runProhibitionEnforcement` returns. This assertion **is** the deliverable — an isolation fix
   with no survivor assertion regresses silently at the next refactor.
2. **Order cleanup after the survivor check** so the evidence still exists when the assertion runs.
3. **Route the spawn through `tests/helpers/process-seam.cjs`.** `local/no-unbounded-spawn` has had
   **no allowlist escape since #3148** — the allowlist file was deleted, `eslint-disable` on that
   rule is separately asserted against, and `timeout: 0` / `timeout: 999999999` are both rejected
   as fake bounds.
4. **Hazard while iterating:** every failed attempt at this test spawns another candidate orphan.
   Check `ps -eo pid,ppid,etime,command | grep prohib-` after each run and clean up, or the
   development loop reproduces the defect it is fixing.

**Warning signs:**
- A test named for a resource-safety property whose assertions only mention a return value
- `t.after(cleanup)` on a fixture that a spawned process may still hold
- Any "fail closed" test with no negative-space assertion about what was left behind

**Phase to address:** **Bounded-subprocess / test-infrastructure** — the assertion lands **before
or with** the isolation flag, never after.

---

### Pitfall 9: Shaping a fix for upstream without deciding, first, whether it can land there

**What goes wrong:**
Work is done in the shape that makes it contributable — split into single-concern diffs, changeset
fragments authored, PR titles conformed — for a fix whose upstream path is gated on something the
project has decided not to do. Effort is spent on a shape nobody will consume, and the local tree
carries an artificially fragmented fix.

The gate is explicit and mechanical:

- **Issue-first, no exceptions** (`CONTRIBUTING.md:107-115`): *"PRs that arrive without a
  properly-labeled linked issue are closed automatically."* CI checks for a closing keyword
  (`Closes #123`); the weaker `Refs #123` form is accepted **only** when every changed file is under
  `tests/`, under `docs/`, or is a root-level `*.md` — markdown under `gsd-core/workflows/`,
  `agents/` or `commands/` is runtime-loaded text and does **not** qualify.
- **PROJECT.md's Out of Scope** records the opposite standing decision: *"Filing GitHub issues
  upstream — defects are captured as todos here and contributed as PRs with tests; issue-filing is
  an explicit standing preference against."*

These two facts are in direct tension. That is a scoping decision, not a research finding — but the
**pitfall** is failing to resolve it *before* shaping the diff.

**Other mechanical rejection/stall causes, verified in `CONTRIBUTING.md`:**

| Cause | Rule |
|---|---|
| No changeset fragment | `Changeset Required` fails any PR touching `bin/`, `gsd-core/`, `src/`, `agents/`, `commands/`, `hooks/`, `sdk/src/`. Use `--type Fixed`; `Fixed` is **not** in the docs-required trigger set, so that gate no-ops |
| Fragment linted locally and "passed" | The lint derives its file set from `GITHUB_BASE_REF`, which only CI sets — `node scripts/changeset/lint.cjs` locally can report success on a PR CI will fail. Run `GITHUB_BASE_REF=next node scripts/changeset/lint.cjs` |
| `pr: 0` placeholder never backfilled | Fails the gate with `fail_invalid_fragment` |
| Wrong PR title shape | Must be `type(#issue): summary`. A leading tag (`[security] fix(config): …`) defeats the `^fix` anchor and files the entry under the wrong changelog section; `fix(core): …` buckets correctly but produces no issue link |
| Draft PR | Automatically closed |
| Wrong base branch | Almost everything targets `next` |
| Rebase churn | `next` has `required_status_checks.strict = true`; a rebase changes HEAD sha, **invalidating the sha-bound pass marker the push gate reads** — so rebase *last*, immediately before pushing |
| Bundled test-fixture correction | A stale-assertion fix packed under a `docs:` prefix is invisible to the hotfix cherry-pick filter and ships a half-state (v1.42.3 / #3621). Keep it as its own `test:` or `fix:` commit |
| Scope creep | *"Scope matches the approved issue"* — extras get asked out. PROJECT.md's own Out of Scope agrees: no refactoring beyond the fix at hand |

**How to avoid:**
1. **Decide carried-vs-contributed per defect, in the phase plan, before writing the diff.** A
   carried fix can be shaped for this tree; a contributed fix must be cut fresh off `next` with a
   test and one concern.
2. **Write the fix against a branch cut off `next`, regardless.** PROJECT.md's constraint —
   *"any fix intended for contribution must apply to a branch cut fresh off `next`"* — is cheap to
   honour up front and expensive to retrofit.
3. **Author the changeset fragment in the same commit as the fix**, verified with the
   `GITHUB_BASE_REF=next` invocation, not the bare one.
4. **Keep the regression test in the same PR.** `CONTRIBUTING.md:43`: *"Write a test that would
   have caught the bug."* A fix PR with no such test is a rejection reason and, for this milestone,
   the test is the whole point.

**Warning signs:**
- A local branch whose diff spans `src/` plus an unrelated refactor
- A fragment with `pr: 0` still in frontmatter
- A green local `scripts/changeset/lint.cjs` run with no `GITHUB_BASE_REF` set
- A fix that cannot be described in one sentence without "and"

**Phase to address:** Every phase that produces an upstream-viable fix; the carried-vs-contributed
decision belongs in the phase plan's opening, not its review.

---

## Moderate Pitfalls

### The generator and lint surfaces do not cover `skills/`

`scripts/sync-runtime-launcher.cjs`, `tests/no-hardcoded-home-gsd-tools.test.cjs` and the portable-glob
lint all scan `agents/` + `gsd-core/workflows/` only. **`skills/` is in none of them**, and nothing
enforces `commands/gsd/X.md` ↔ `skills/gsd-X/SKILL.md` body parity — which is why two byte-identical
copies of the same broken code shipped undetected (`commands/gsd/review-backlog.md:22` and
`skills/gsd-review-backlog/SKILL.md:22`). **Prevention:** when fixing a `commands/gsd/*.md` file,
always `diff` its `skills/gsd-*/SKILL.md` twin in the same change. **Warning sign:** a
`commands/gsd/*.md` edit whose `skills/gsd-*/SKILL.md` twin is untouched in the same diff — or a new
lint/generator whose scan list names `agents/` and `gsd-core/workflows/` and stops there.
**Phase:** shell fence portability.
*(`scripts/lint-unreachable-guard-drift.cjs` does scan all four surfaces — it is the gate that will
grade the fence fix.)*

### A `gsd_run <verb>` call site can name a verb that does not exist

`agents/gsd-plan-checker.md:758,760` calls `phase.list-artifacts`, which does not exist — runtime
says `Unknown phase subcommand`. **Nothing catches it: no test validates that a `gsd_run` call site
names a live verb.** **Prevention:** treat this as its own item (it is out of scope for the fence
fix); when adding any `gsd_run` call, run it once. **Warning sign:** a `gsd_run <noun>.<verb>` name
that appears in call sites but nowhere in the command's dispatch table — grep the verb string in
`src/` and expect at least one non-`.md` hit. **Phase:** captured-defect backlog.

### `--pick` on an array comma-joins

`String(['a','b c'])` → `a,b c`, so JSON + `--pick` is the wrong shape for multi-path output;
newline `--raw` + `while read` is the idiomatic form. Related: the `@file:` >50KB spill guard exists
in the **JSON branch only** (`src/io.cts:144-160`) — raw output writes `String(rawValue)` with no
size check, so any new verb must return **paths, never contents**. **Warning sign:** a `--pick`
whose target field is an array, or a `--raw` consumer that splits on commas; any verb returning file
*contents* rather than paths. **Prevention:** newline `--raw` + `while IFS= read -r`, and a verb
contract that returns paths. **Phase:** shell fence portability.

### Node version drift silently changes what the suite reports

Node 24 changed the default test reporter from TAP to spec, so `# fail` greps match nothing; npm
treats `engines` as advisory and never errors. A verification step that greps runner output must
pin the reporter or parse a machine format. **Phase:** any phase whose gate reads test output.

### Ambient environment reddens unrelated tests

`GSD_AGENTS_DIR` in the environment fails 12 tests; a stray `.DS_Store` under `gsd-core/` fails 20.
A phase that reports "N failures" without stating the environment baseline is reporting noise.
**Prevention:** state the known baseline (3 environment-caused failures out of 30,612 at Node 24
with a clean tree) in the phase's verification section. **Phase:** all.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Fix the guard at all N call sites in place instead of extracting one predicate | Smallest diff; no new export to justify upstream | Produces the (N+1)th copy; the next fix diverges again — this is literally how the current defect arose | Never for ≥2 sites. The #3357 → #3513 precedent (seven copies → one export) is the accepted local pattern |
| Keep `catch { /* ignore */ }` and just fix the count | One-line change; lint already allows it | The next contents-based check downstream re-derives the same wrong answer from the same residue | Only when the cleanup's outcome feeds nothing — verify by grepping downstream reads |
| Fix the fence sites without parameterizing the harness | Ships the visible fix now | Zero regression coverage; this is exactly rounds #2770/#2962/#3300/#3409 | Never — four rounds are the evidence |
| Ship the isolation flag without the survivor assertion | Stops the leak today | Silent regression at the next refactor of `buildNodeTestArgs` | Never; the assertion is the deliverable |
| Add a lint rule to ban empty catch | Systemic-looking fix | `eslint.config.mjs` sets `allowEmptyCatch: true` in three places; changing it is maintainer-owned config and a separate concern that will bounce a fix PR | Only as its own change, never bundled |
| Test only bash because zsh "behaves the same for this construct" | Halves the matrix | It does not — measured: array indexing, NOMATCH, `PIPESTATUS`, `read -ra`, `BASH_REMATCH` all differ | Only for constructs with a recorded cross-shell measurement |
| Bundle several fixes into one branch because they touch the same file | Fewer PRs to manage | `One concern per PR`; extras get asked out and the whole PR stalls | Only when the sites want the *same edit* |
| Reuse the local `scripts/changeset/lint.cjs` run as proof | Fast | It evaluates nothing without `GITHUB_BASE_REF`; CI still fails | Never — pass the base explicitly |

---

## Integration Gotchas — fix A breaking subsystem B

These are the cross-subsystem couplings in *this* tree. Each is a fix in one place with a landing
zone in another.

| Fix | What it can break | Correct approach |
|---|---|---|
| Arm the workstream guard in `state advance-plan` | Workflow/agent `.md` files that call the verb unattended now stall instead of quietly writing root | Grep all callers across `gsd-core/workflows`, `agents`, `commands`, `skills` before arming; assert the new refusal by `ERROR_REASON`, not exit status |
| Make `workstream complete` report observed state | `remaining_workstreams` / `reverted_to_flat` are consumed downstream; changing their derivation changes what callers see | Change the derivation, keep the field names and JSON shape; add residue as a **new** field rather than repurposing an existing one |
| Change the fence idiom at 11 sites | `agents/gsd-verifier.md` has **2 bytes of headroom** under `LARGE_CAP` — a net-additive fix fails `tests/agent-size-budget.test.cjs` | Route that site through the existing `verification resolve-file` verb (7 bytes shorter); check `wc -c` on every touched agent file |
| Change any fence in `session-report.md` | `scripts/sync-runtime-launcher.cjs` inserts the `gsd_run` preamble byte-identically; hand-copying the 2.8KB one-liner desynchronises the generator | Run the generator; hand-edit only the orphaned consumer line it leaves |
| Fix `commands/gsd/review-backlog.md` | Its byte-identical `skills/gsd-review-backlog/SKILL.md` twin has **no generator coverage and no parity test** | Fix both in the same change and diff them |
| Set `--test-isolation=none` | The target file is now imported into the runner process and shares globals — `GSD_PROHIB_SUBJECT` (#1279) and `childEnv()`'s `NODE_TEST_CONTEXT`/`NODE_OPTIONS` stripping guard exactly that wall | Re-verify both conventions as part of the fix, not after |
| Tighten the guard while `workstream complete` can leave `wsDir` itself behind | The *other* ENOTEMPTY direction: if a dotfile survives **inside** `wsDir`, the directory persists and `listAvailableWorkstreams` counts it as a live workstream forever — a phantom with no `STATE.md`. Post-tightening that becomes a **spurious refusal** demanding `--ws` for something that does not functionally exist, which is exactly the "new refusal vs regression" ambiguity of Pitfall 5. **Racier than the `wsRoot` case:** `cmdWorkstreamComplete` renames *every* `readdirSync` entry into the archive, so this needs the dotfile recreated between the rename loop and the `rmdir` — whereas nothing ever tries to remove a stray file in `wsRoot` | Verify the postcondition on `wsDir` too, not only `wsRoot`; if `wsDir` survives, report it as residue rather than letting a later directory count infer a live workstream from it |
| Add a `.DS_Store` fixture to reproduce the ENOTEMPTY path | `.DS_Store` anywhere under `gsd-core/` breaks 20 install-attribution tests | Plant it only under a temp fixture; remove in `afterEach` |
| Parameterize the fence harness over zsh | CI runtime roughly doubles for that suite; macOS lanes already pin `shell: zsh` via `policy-shell-pinning` | Scope to the harness that extracts shipped fences — not the 57 `interpreter: 'bash'` sites |
| Any `src/*.cts` edit | `gsd-core/bin/lib/*.cjs` is build output, gitignored, never in the diff — but `Changeset Required` still treats `src/` as user-facing | Author the fragment; never hand-edit the `.cjs` |
| Any new test that shells out | `local/no-unbounded-spawn` has **no allowlist since #3148** | Route through `tests/helpers/process-seam.cjs`; import class-norm timeouts from `tests/helpers/timeouts.cjs` |

---

## Performance Traps

Scale here is not users — it is machine resources and CI wall-clock.

| Trap | Symptoms | Prevention | When it breaks |
|---|---|---|---|
| Orphaned test grandchildren spinning a core | Load average far above core count; `ps` shows `PPID 1` with an old `ELAPSED`; the machine gets hot with no visible job | Survivor assertion + `--test-isolation=none`; `ps -eo pid,ppid,etime,command \| grep prohib-` after each iteration | **Every run of the suite** — measured 2 orphans × ~90% core × 34h. Not a scale threshold; a per-run cost |
| Cleanup on the last line of a killable process | Leaked children after an interrupted run; the same session leaked 18 unrelated shells this way | Cleanup must not depend on the parent surviving; assert absence, don't assume | Any interrupted or timed-out run |
| Cross-shell parameterization applied suite-wide | CI time doubles across 57 call sites | Scope to the fence-extraction harness only | Immediately, on the first CI run |
| Full-tree fence sweeps as a routine gate | 1048 fences / 6413 lines is a slow scan | Ship it as a ratcheting lint over changed files, one-time sweep for the inventory | Every PR, if wired as a full-tree gate |

---

## Security Mistakes

This milestone's defect classes are correctness and portability; it does not have a meaningful
domain-specific security surface, and inventing rows here would be noise. Two genuine items:

| Mistake | Risk | Prevention |
|---|---|---|
| Interpolating a workstream/project name into an error message or a shell fence without treating it as hostile | Workstream names are user-controlled and reach both shell projections and prompts; `CONTRIBUTING.md` classifies workstream/project values as prompt-injection and path-traversal surfaces | The new guard's messages already echo `_diagnosis.value` — keep them inside structured JSON fields and out of any shell fence; cover with the existing hostile-input matrix |
| `workstream complete` leaving a partially-archived tree behind after a swallowed failure | The archive path holds planning artifacts; residue that nothing reports is state nobody audits | Report residual paths in the JSON contract (same fix as Pitfall 3) |

---

## UX Pitfalls

The "users" here are one developer and the Claude sessions driving these verbs unattended. The
dominant UX failure in every one of these defects is the same: **success reported for work not done.**

| Pitfall | User impact | Better approach |
|---|---|---|
| Silent fallback to root `STATE.md` on a dangling pointer | Exit 0, JSON says `current_plan: 2`, the real file is untouched; the peer session caught it only by re-reading the artifact, then abandoned the verb and hand-edited STATE.md for the rest of the phase | Refuse, with a reason code and a named remedy; or at minimum surface `workstream_pointer_cleared: "<name>"` so silent recovery is not *signal-free* recovery |
| `reverted_to_flat: true` about a directory that still exists | A later command trusts the report and takes the wrong branch | Derive reported fields from post-operation observation |
| A guard that refuses with prose but no machine-readable reason | An agent caller cannot distinguish "you must pass `--ws`" from a crash | Every refusal carries an `ERROR_REASON` (the two workstream reasons exist already) plus the exact command that fixes it |
| A fence that reads nothing and says nothing | The planner silently plans without CONTEXT/RESEARCH/DISCOVERY; output looks plausible | Fixes must fail loudly or be covered by a test that asserts the file *was* read — absence of error is not evidence of a read |

---

## "Looks Done But Isn't" Checklist

- [ ] **Fence fix:** verified under **both** `/bin/bash` 3.2.57 and `/bin/zsh` 5.9, matched *and*
      unmatched glob — verify the harness goes RED under zsh on the unfixed input
- [ ] **Fence fix:** every touched agent file re-checked with `wc -c` against its tier cap
      (`gsd-verifier.md`: 2 bytes of headroom)
- [ ] **Fence fix:** the `commands/gsd/*.md` ↔ `skills/gsd-*/SKILL.md` twin updated in the same change
- [ ] **Fence fix:** `.planning/reference/shell-fence-portability.md` updated in the **same commit**
- [ ] **Workstream guard:** the predicate is exported once and all **three** commands call it —
      including `state.cts`, which has no guard today
- [ ] **Workstream guard:** the "pointer named, zero directories remain" cell is covered and refuses
- [ ] **Workstream guard:** `--ws` still overrides; the pre-change accept set is pinned in a
      characterization test whose diff shows exactly which cells flipped
- [ ] **`workstream complete`:** `reverted_to_flat` derived from an observation, and the ENOTEMPTY
      case has a test whose fixture is cleaned up
- [ ] **Subprocess fix:** the test asserts **no survivor**, not just the verdict, and cleanup runs
      after that assertion
- [ ] **Subprocess fix:** `GSD_PROHIB_SUBJECT` and `childEnv()` stripping re-verified under
      isolation `none`
- [ ] **Subprocess fix:** `ps -eo pid,ppid,etime,command | grep prohib-` is clean after the run
- [ ] **Every fix:** a regression test that fails on the unfixed code (demonstrate RED, don't assume)
- [ ] **Every fix:** changeset fragment present, `--type Fixed`, real PR number, verified with
      `GITHUB_BASE_REF=next node scripts/changeset/lint.cjs`
- [ ] **Every fix:** run on **Node 24** — a Node 22 run is the harness-divergence pitfall one level up
- [ ] **Every fix:** environment baseline stated (no `GSD_AGENTS_DIR`, no `.DS_Store`, complete
      `node_modules`) before quoting a failure count

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Fence fix shipped under a bash-only harness | MEDIUM | Parameterize the harness, re-run against the shipped fix; expect at least one site still broken (four upstream rounds say so). Re-sweep with the inventory table rather than spot-checking |
| Guard fixed in place at N sites | MEDIUM | Extract the predicate now, route all sites, delete the copies in the same change; add the call-site matrix test so the next site cannot skip it |
| Root `STATE.md` corrupted by a silent fallback | LOW–MEDIUM | The workstream file is untouched (that is the defect); revert root `STATE.md` from git, re-point the pointer, re-run. Costly only if the corruption went unnoticed across several plans |
| Orphans already leaked | LOW | `ps -eo pid,ppid,etime,command \| grep -E 'prohib-\|node --test'`, confirm `PPID 1`, plain `SIGTERM` (measured sufficient — no `SIGKILL` escalation needed). Note `lsof -p <pid>` is the only way to see a deleted `cwd` |
| Upstream PR stalled on a missing linked issue | LOW (effort) / HIGH (schedule) | The gate is mechanical and the project has a standing decision against issue-filing — resolve carried-vs-contributed and, if carried, record the divergence with its reason rather than reshaping the diff |
| PR gone `BEHIND` after another merge | LOW | Rebase **last**, immediately before pushing — a rebase invalidates the sha-bound pass marker and costs a full re-verification cycle |
| Bundled test-fixture correction in a `docs:` commit | LOW | Split the commit; the hotfix cherry-pick filter routes by subject prefix and will otherwise ship a half-state (v1.42.3 / #3621) |

---

## Pitfall-to-Phase Mapping

Phase *topics* keyed to PROJECT.md target features (no `ROADMAP.md` yet). **Ord.** marks the
pitfalls that constrain phase order rather than phase content.

| # | Pitfall | Prevention Phase (topic) | Ord. | Verification that prevention worked |
|---|---|---|---|---|
| 1 | Harness diverges from production shell | **Cross-shell test harness** | ✔ before/inside fence phase | The parameterized harness is RED under zsh on the pre-fix fence and GREEN after; both shells run in CI |
| 2 | N copies share an untested precondition (+ one site with none) | **Workstream fail-safe precondition** | ✔ extraction before call-site fixes | `grep -c` finds one implementation; the 3×5 call-site matrix test exists and asserts `ERROR_REASON` values |
| 3 | Swallowed cleanup composed into a correctness check | **Workstream fail-safe precondition** | — | ENOTEMPTY fixture test passes; `reverted_to_flat` provably derived from a post-operation read; residue surfaced in JSON |
| 4 | Four symptoms, one cause | **Shell fence portability** (+ triage practice, all phases) | — | The reference doc is updated in the fix commit; the cause-completeness question is answered in the phase summary with named survivors (or none) |
| 5 | Guard tightening that refuses where it proceeded | **Workstream fail-safe precondition** | ✔ characterization tests before the change | The characterization-test diff enumerates every flipped cell; caller grep recorded in the plan |
| 6 | "Verified" that does not cover bash 3.2 / zsh 5.9 / POSIX sh | **Shell fence portability** | — | The plan's verification section names the matrix cells and the POSIX leg's evidence source; agent byte budgets re-checked |
| 7 | Timeout signals one PID, not the tree | **Bounded-subprocess / test infrastructure** | — | No survivor after the suite; both `node-test` spawn sites covered, not just the fixture |
| 8 | The bound's own test asserts the wrong side | **Bounded-subprocess / test infrastructure** | ✔ assertion before/with the isolation flag | Reverting the isolation flag turns the test RED |
| 9 | Upstream PR shape decided too late | **Every contributing phase** | ✔ decided at plan time | Each fix's plan states carried-vs-contributed with a reason; contributed fixes branch off `next` |
| M1 | `skills/` outside every generator and lint surface | **Shell fence portability** | — | `commands/gsd/*.md` and its SKILL.md twin are byte-diffed in the change |
| M2 | `gsd_run` call sites naming dead verbs | **Captured-defect backlog** | — | The named verb executes without `Unknown … subcommand` |
| M3 | `--pick` array joining / raw-output spill guard | **Shell fence portability** | — | Any new verb returns paths, and multi-path output uses newline `--raw` |
| M4 | Node-version-dependent runner output | **All phases with a test-output gate** | — | Gate parses a machine format or pins the reporter |
| M5 | Ambient env reddening unrelated tests | **All phases** | — | Baseline stated with every failure count |

---

## Sources

**Measured in this repo / on this machine (2026-08-24, macOS arm64):** HIGH confidence
- Login shell of the agent Bash tool: `$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset
- `/bin/bash --version` → GNU bash **3.2.57(1)**; `/bin/zsh --version` → **5.9**;
  `/bin/sh -c 'echo $BASH_VERSION'` → **3.2.57** (macOS `/bin/sh` is bash in sh mode, not dash)
- `fs.rmdirSync` on a directory containing only `.DS_Store` → **ENOTEMPTY**, while
  `readdirSync(…).filter(isDirectory).length` → **0**
- `src/planning-workspace.cts:151-161`, `src/init.cts:2926-2955`, `src/phase.cts:2212-2241`,
  `src/state.cts:656-657`, `src/workstream.cts:300-345`, `src/io.cts:199-200`
- `tests/unreachable-shell-guard.test.cjs:132-150`; 57 `interpreter: 'bash'` sites under `tests/`;
  `tests/pause-work-improvements.test.cjs:287,326` already spawn zsh
- `tests/policy-shell-pinning.test.cjs:45-92` (macOS CI pins `shell: zsh`)
- `eslint.config.mjs:456,539,650` — `'no-empty': ['warn', { allowEmptyCatch: true }]`
- `agents/gsd-verifier.md` = **49,150 bytes**; `LARGE_CAP = 49152` (`tests/agent-size-budget.test.cjs:58`)

**Official documentation (context7, `/websites/nodejs_latest-v24_x_api`):** HIGH confidence
- `child_process` — *"Signal propagation limitations in shell processes"*: `subprocess.kill()` on a
  spawned `sh -c 'node -e …'` does **not** terminate the node grandchild; `detached: true` makes the
  child a process-group leader; `timeout` sends `killSignal` (default `SIGTERM`) to the child
- `fs` — `rmdirSync` is non-recursive, its `recursive` option is deprecated (**DEP0147**); use
  `fs.rmSync(path, { recursive: true, force: true })` for `rm -rf` semantics
- `test` / `cli` — `--test-isolation` **defaults to `'process'`**; each test file runs in a separate
  child process; spawned children inherit Node options; with `'none'`, files are imported into the
  main runner process and `--test-concurrency` is ignored (forced to 1); renamed from
  `--experimental-test-isolation` in v23.6.0

**Project documents:** HIGH confidence
- `CONTRIBUTING.md` — issue-first rule, closing-keyword CI check and its `tests/`/`docs/`/root-`*.md`
  exception, one concern per PR, no draft PRs, changeset gate and `GITHUB_BASE_REF` caveat, PR-title
  convention, `next` strict-status/rebase cost, `docs:`-bundled fixture commits (#3621),
  process seam and `local/no-unbounded-spawn` (no allowlist since #3148), typed-IR assertion rule,
  fixture provenance (#2371)
- `.planning/PROJECT.md`; the three linked todos (zsh fences, `state advance-plan` fallback,
  orphaned grandchild), including their own measurements and the 1048-fence sweep

**External, cited:** HIGH/MEDIUM confidence
- ShellCheck wiki **SC1103** — supported dialects `sh`/`bash`/`dash`/`ksh`; *"One notable
  unsupported shell type is zsh, see issue #809"*; still open as koalaman/shellcheck#2648. **HIGH**
- ShellSpec (shellspec.info) — cross-shell BDD harness for dash/bash/ksh/zsh, shell selected with
  `-s/--shell`: the precedent for parameterizing a harness over interpreters. **HIGH**
- E. Juergens, F. Deissenboeck, B. Hummel, S. Wagner, *"Do code clones matter?"*, ICSE 2009 —
  ~900 clone groups assessed, **107 confirmed faults** from inconsistent changes; the *inconsistent
  bug fix* is the dangerous shape; recommends clone detection in the nightly build and detectors
  that find *inconsistent* clones. Related: CP-Miner (OSDI 2004), DejaVu (2010). **HIGH**
- MITRE **CWE-390** *Detection of Error Condition Without Action*; Google Error Prone `EmptyCatch`
  + Google Java Style §6.2. **HIGH**
- R. Chen, *"Since clean-up functions can't fail, you have to soldier on"*, The Old New Thing,
  2014-08-07 — the cleanup-path exception that makes the *composition*, not the swallow, the defect. **HIGH**
- ITIL problem-vs-incident management (Atlassian ITSM, Rootly) — *"a problem is a cause, or
  potential cause, of one or more incidents"*; explicit numeric escalation triggers; Known Error
  Database; the documented failure of informal triggers. **MEDIUM** (practice framework)
- Validation-strengthening rollout practice — MongoDB `validationAction: warn` → `error`,
  Microsoft APM policy `enforcement: warn` → `block`, staged API validation with machine-readable
  warning codes; Khorikov, *"How to Strengthen Requirements for Pre-existing Data"*. **MEDIUM**
- Environment-parity / vacuous-test writing: mutation testing and confirm-RED as sufficiency gates;
  worked cases where a harness supplied the asserted property for free (container-pinned `TZ=UTC`;
  `fakeowner` making `chmod 0444` unenforced). **MEDIUM** (practitioner reports, mechanism
  independently confirmed here by measurement)

---
*Pitfalls research for: defect-fixing in a mature tested fork feeding upstream*
*Researched: 2026-08-24 — gsd-core 1.11.0, next@7cf6a079*
