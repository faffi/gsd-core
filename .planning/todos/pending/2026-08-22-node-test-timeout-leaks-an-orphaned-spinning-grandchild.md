---
created: 2026-08-22T12:05:00.000Z
title: the bounded-subprocess timeout signals only the direct child, so every hung `node-test` check leaks an orphaned grandchild that spins a core forever — and the test that exists to prove the bound works is itself the biggest leaker
area: tooling
severity: major
scope: Small
scope_note: One flag in `buildNodeTestArgs` plus a survivor assertion and a regression test. Small in diff, but the leak is unbounded in cost — two runs left 2 orphans burning ~1.8 cores for 34h on the author's machine, and the class affects every `node-test` check, not just the hang fixture.
files:
  - src/prohibition-enforcement.cts:220-222 (buildNodeTestArgs — the fix site; no `--test-isolation` flag)
  - src/prohibition-enforcement.cts:468-482 (runNodeTestWithSubject — execFileSync + timeout, leaks)
  - src/prohibition-enforcement.cts:485-500 (defaultRunCheck node-test branch — execFileSync + timeout, leaks)
  - src/prohibition-enforcement.cts:449 (NODE_TEST_TIMEOUT_MS = 30_000 — the default bound every real check runs under)
  - gsd-core/bin/lib/prohibition-enforcement.cjs:133-135,379-395,396-420 (build output — do not hand-edit)
  - tests/prohibition-enforcement.test.cjs:685-700 (the B2 hang test — asserts the parent verdict, never the survivor)
---

## Problem

`DEFECT.UNBOUNDED-SUBPROCESS` was fixed with `execFileSync(..., { timeout })`. That bounds the
**verifier's wait**. It does not bound the **subprocess tree**. The hang survives the timeout,
gets reparented to `launchd`/`init`, and spins a full core until the machine reboots.

Measured 2026-08-22 on the author's 18-core machine — two orphans from two runs of the suite:

```
  PID  PPID  %CPU     ELAPSED  COMMAND
55029     1  90.9  01-10:24:03  node …--test-isolation=process --test-timeout=0… /…/T/prohib-hang-47WGp5/hang.test.cjs
77983     1  88.7  01-10:08:57  node …--test-isolation=process --test-timeout=0… /…/T/prohib-hang-BRS3ZA/hang.test.cjs
```

**34 hours each, ~90% of a core each.** `sample 55029` shows 2489/2489 samples pinned in one JIT
frame under `RunMicrotasks → AsyncFunctionAwaitResolveClosure`, zero syscalls — a tight loop, not
a stuck wait. Both died instantly on plain `SIGTERM`, so **no JS handler was queuing the signal:
it was simply never delivered to that PID.** No `SIGKILL` escalation is needed by the fix.

## Root cause — the surviving process is a GRANDCHILD, and its own argv proves it

`buildNodeTestArgs` (`src/prohibition-enforcement.cts:221`) spawns:

```
node --test --test-reporter=tap -- <file>
```

The survivors carry **no `--test` and no `--test-reporter`** — they run the test file as a direct
entry point, with `--test-isolation=process` and a fully-resolved flag set. That is not the process
`execFileSync` spawned; it is the process-isolation child that the runner forked one level deeper.

Confirmed against the Node v24 docs (`/websites/nodejs_latest-v24_x_api`, CLI Options → Test Runner):

> `--test-isolation` … **'process' runs each test file in a separate child process** … **The default
> is 'process'** … (renamed from `--experimental-test-isolation` in v23.6.0)

> Test runner execution model: *"When process-level test isolation is enabled, each test file runs
> in a separate child process."*

> Child process option inheritance: *"spawned child processes inherit Node.js options from the
> parent process"* — which is exactly why the survivor's argv is the fully-expanded flag set.

`child_process`'s `timeout` sends one signal to **one PID**. The runner (the direct child) dies on
schedule; the forked grandchild running `while (true) {}` never hears about it. `--test-timeout=0`
in the inherited argv is the second nail — `node:test` would not have aborted the hanging test on
its own either.

**This is not specific to the hang fixture.** Both `node-test` spawn sites
(`runNodeTestWithSubject:476`, `defaultRunCheck:496`) share the shape, and the *default* bound is
`NODE_TEST_TIMEOUT_MS = 30_000`. Any genuinely stuck wired check in normal operation leaks a
core-burning orphan after 30s. The hang fixture is just the one that leaks on *every single run*.

## The test cannot see the leak — it asserts the wrong side of the boundary

`tests/prohibition-enforcement.test.cjs:698-699`:

```js
assert.notEqual(result.status, 'green', 'a hung check must be killed and fail closed …');
assert.equal(result.located, true);
```

Both pass. The *parent's verdict* is correct — it genuinely did fail closed. Nothing in the suite
ever looks for a survivor, so the test is green while leaking a core. The failure is silent and in
the safe-looking direction: same class as the zsh guard bugs — nothing errors, no test notices.

**Compounding trap for whoever debugs this next:** `t.after(() => cleanup(dir))` at :688 deletes the
temp dir while the orphan still holds it as `cwd`. `ls` shows nothing; only `lsof -p <pid>` reveals
`cwd → /…/prohib-hang-47WGp5 (deleted)`. The evidence erases itself.

## Fix

Add `--test-isolation=none` in `buildNodeTestArgs` (`src/prohibition-enforcement.cts:221`):

```ts
export function buildNodeTestArgs(check: CheckDescriptor): string[] {
  return ['--test', '--test-isolation=none', '--test-reporter=tap', '--', check.target];
}
```

With isolation off, the docs confirm *"test files are imported into the main runner process"* — so
the hang runs **in the direct child that `execFileSync`'s timeout actually signals**, and the empirical
`SIGTERM` result above says that is sufficient to kill it.

Why this over a tree-kill: it keeps the lib **synchronous and shell-free** (no `spawn` +
`detached: true` + `process.kill(-pid)` rewrite, no `pkill`, no Windows divergence — `windowsHide`
and portability are already load-bearing here). Every check spawns **exactly one file**, so per-file
isolation buys nothing that is being used.

**Known, acceptable side effect** (docs, `--test-concurrency`): *"If `--test-isolation` is set to
'none', this flag is ignored and concurrency is set to one."* Irrelevant at one file per spawn.

**Real caveat to check during the fix:** with isolation `none` the target file is imported into the
runner process, so it now shares globals with the runner. Verify the `GSD_PROHIB_SUBJECT` convention
(#1279) and the `childEnv()` `NODE_TEST_CONTEXT`/`NODE_OPTIONS` stripping still behave — the
stripping exists precisely to stop an ambient runner context corrupting the verdict, and this change
moves the boundary it guards.

## Test shape — the missing assertion is the actual deliverable

A tree-kill or isolation fix with no companion assertion regresses silently on the next refactor.
The B2 test must assert **no survivor**, not just the verdict:

- Capture the spawned pid (or snapshot matching pids before/after), then after `runProhibitionEnforcement`
  returns, assert nothing matching the fixture path is still alive.
- Must route the spawn through `tests/helpers/process-seam.cjs` — `local/no-unbounded-spawn` has had
  no allowlist escape since #3148.
- **Hazard while iterating:** every failed attempt at this test spawns another candidate orphan.
  Check `ps -eo pid,ppid,etime,command | grep prohib-` after each run and clean up.

## Provenance

Found 2026-08-22 while diagnosing why two `node` processes were pinning cores on the author's
machine. They turned out to be this suite's own fixtures, orphaned 34h earlier. Killed manually with
`SIGTERM`; the leak itself is unfixed and reproduces on every run of the suite.

Not the only orphan class found in that session — 18 `while :; do :; done` shells from an unrelated
`/tmp/c5-errgroup` benchmark were leaked the same way (cleanup on the happy path of a parent that was
killed first, so `kill $LOADPIDS` never ran). Combined, the 20 orphans held ~17.5 of 18 cores at load
average 102. **The general lesson for this repo: cleanup that lives on the last line of a process
that may be killed is not cleanup.** Worth a sweep for other `execFileSync`/`spawnSync` timeout sites
that assume the bound reaches the whole tree.
