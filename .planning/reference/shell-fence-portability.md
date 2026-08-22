# Shell-fence portability — bash-authored fences execute under the user's login shell

**Status: OPEN.** No fix landed. This document is the whole picture; the actionable item is
`.planning/todos/pending/2026-08-21-zsh-array-index-guards-silently-read-nothing.md`.

> **This is `reference/`, so staleness is a bug.** When a site is fixed, update its row here in
> the same commit. A row that says BROKEN after the fix lands is worse than no row.

## Root cause, in one sentence

902 shipped markdown fences are tagged ` ```bash `, but Claude Code's Bash tool executes them
under the operator's **login shell** — zsh on macOS — and the two shells disagree about globs,
array indexing, word-splitting, regex captures, and `read`.

The tag is a claim the runtime does not honour. Every defect below is that gap.

Verified in-session: `$0 = /bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset. macOS system bash
is **3.2.57** (bash 4+ features unavailable) — `gsd-core/workflows/code-review.md:668-669` already
states this policy: *"macOS ships with bash 3.2 … all array construction uses portable
`while IFS= read -r` loops compatible with bash 3.2."*

## The five mechanisms

Each measured on this machine against `/bin/bash 3.2.57` and `/bin/zsh 5.9`.

### M1 — glob that matches nothing ABORTS the fence
`ARR=( "$d"/*.md )` and `for x in "$d"/*.md; do` abort the **entire fence** under zsh NOMATCH.
The artifacts globbed here (CONTEXT/RESEARCH/DISCOVERY/VERIFICATION) are **optional by design**,
so no-match is the *normal* path, not an edge case.

```
$ /bin/zsh -c 'eval "_CTX=( ./*-CONTEXT.md ); echo reached"'
zsh: no matches found: ./*-CONTEXT.md      # "reached" never prints, exit 1
```

**It cascades.** `agents/gsd-planner.md:697-702` chains three globs in one fence: a missing
`RESEARCH.md` kills the `DISCOVERY.md` read at :701-702 even when DISCOVERY.md exists.

**`2>/dev/null` cannot suppress the message** — zsh emits it during word-expansion, before the
command and its redirections exist. Only `{ …; } 2>/dev/null` around the whole statement works.

**Severity split (important):** only *array-assignment* and *for-list* globs abort. A bare
command-position glob (`cat glob`, `ls glob`) or a glob inside `$(…)` does **not** abort — the
command fails, zsh prints `no matches found`, the script continues. ~160 sites are this milder
class: stderr noise, functionally harmless.

### M2 — `${ARR[0]}` is always empty in zsh
zsh arrays are **1-indexed**. Confirmed against the zsh manual (Options → KSH_ARRAYS):
*"Without KSH_ARRAYS, `array[0]` would be an error or empty string."*

This compounds M1 into failure in **both directions**: no match → fence aborts; match exists →
guard is false, file silently never read.

```
$ touch /tmp/gt/01-CONTEXT.md
$ zsh -c '_CTX=( /tmp/gt/*-CONTEXT.md ); echo count=${#_CTX[@]} zero=[${_CTX[0]}]'
count=1 zero=[]          # file exists; guard evaluates false; cat never runs
```

### M3 — `BASH_REMATCH[N]` is empty in zsh
zsh populates `$match`/`$MATCH` instead. Measured: bash `[3]`, zsh `[]`.
Breaks `--wave N`, `--granularity X`, `--prd`, `--ingest`, `--research-phase`, and phase-decimal
normalization — all silently parse to empty.

### M4 — `read -ra` is a hard error in zsh
Not a divergence with a workaround; `-a` is not a zsh `read` option.
Measured: `zsh:read:1: bad option: -a`, array stays length 0.
**`/gsd:code-review --files` is silently ignored on every macOS run** — no crash, nothing surfaced.

### M5 — bare `$VAR` does not word-split in zsh
`for x in $VAR` iterates **once** in zsh where bash iterates per word.

⚠ **`$(…)` DOES word-split in zsh** — only *bare parameter* expansion does not. Six sites were
initially suspected and retracted on measurement (`next.md:124,280`, `autonomous.md:84`,
`plan-review-convergence.md:66`, `review.md:363`, `sync-skills.md:40`).

Scoping caveat resolved 2026-08-21: `SH_WORD_SPLIT` is **not** set on this machine (absent from
`setopt`, 0 hits in `~/.zshrc`), so these findings hold here.

### M6 — `${PIPESTATUS[0]}` does not exist in zsh
zsh uses lowercase `$pipestatus`, 1-indexed. `AUDIT_TEST_EXIT=${PIPESTATUS[0]}` yields `""`, so the
subsequent `[ "$X" -eq 124 ]` timeout check silently never fires.

## Site inventory — the whole picture

Sweep basis: fence-aware parse of **1048 ```bash fences / 6413 lines** across `agents/`,
`gsd-core/workflows/**`, `gsd-core/references/`, `commands/**`, `skills/**`, `hooks/` at
`next@7cf6a079`. All 777 *untagged* fences re-scanned for the five severest patterns — zero hits.
Scope confirmed complete: `contexts/`, `templates/`, `capabilities/` carry no agent-executed
fences; the 394 other files with bash fences are `docs/**` + README (human-facing).

### M1+M2 — glob array (11 broken, 2 correct)

| File:line | Construct | Status |
|---|---|---|
| `agents/gsd-planner.md:659-660` | `_SUMMARIES` | BROKEN |
| `agents/gsd-planner.md:697-698` | `_CTX` | BROKEN |
| `agents/gsd-planner.md:699-700` | `_RESEARCH` | BROKEN |
| `agents/gsd-planner.md:701-702` | `_DISCOVERY` | BROKEN |
| `agents/gsd-phase-researcher.md:548-549` | `_CTX` | BROKEN |
| `agents/gsd-verifier.md:85-86` | `_VERIF` | BROKEN — ⚠ file is **49,150 B against a 49,152 cap** |
| `gsd-core/workflows/transition.md:231-232` | `_SUMMARIES` | BROKEN |
| `gsd-core/workflows/complete-milestone.md:369-370` | `_SUMMARIES` | BROKEN — ⚠ see trap below |
| `gsd-core/workflows/session-report.md:37-38` | `_REPORTS` (`ls -la`) | BROKEN |
| `commands/gsd/review-backlog.md:21-22` | `_BACKLOG` (`ls -d`, dirs) | BROKEN |
| `skills/gsd-review-backlog/SKILL.md:21-22` | byte-identical twin | BROKEN |
| `gsd-core/workflows/review.md:269` | `_CTX` | **CORRECT** — shim @248 + length check |
| `gsd-core/workflows/review.md:273` | `_RESEARCH` | **CORRECT** — same |

⚠ **`complete-milestone.md` is the trap.** A nullglob shim at :331 protects the for-loop at :335,
but the glob-array at :369 is in a **different fence** and unprotected. Checking "does this file
carry the shim?" gives a false pass.

### M3 — BASH_REMATCH (7 sites, 3 files)
`gsd-core/references/phase-argument-parsing.md:39` · `gsd-core/workflows/execute-phase.md:84` ·
`gsd-core/workflows/plan-phase.md:70,71,72,73,127`

### M4 — `read -ra` (1 site)
`gsd-core/workflows/code-review.md:78`

### M5 — word-split on stored var (5 sites + 1 embedded)
`gsd-core/workflows/execute-phase/steps/per-plan-worktree-gate.md:35,40` ·
`gsd-core/workflows/pr-branch.md:265` · `gsd-core/workflows/sync-skills.md:240,245`
(the last iterates **70+ skills as one item**) · embedded in a spawned-subagent template at
`gsd-core/workflows/quick.md:467-470`

### M6 — PIPESTATUS (1 site)
`gsd-core/workflows/audit-fix.md:145`

### Fully protected — no action needed
All **10** `for x in glob` loops carry the dual shim and are correct:
`agents/gsd-integration-checker.md:101` · `agents/gsd-plan-checker.md:763,780,868` ·
`audit-milestone.md:130` · `complete-milestone.md:335` · `execute-phase.md:1505` ·
`resume-project.md:90` · `review.md:259,337`

## The one correct implementation already in the tree

`gsd-core/workflows/review.md:248-273` carries **both** the nullglob shim and `${#_CTX[@]} -gt 0`
(length check, never `[0]`). It is the only fully-correct instance in 1048 fences — and it is the
file **#3300** was filed against.

**The pattern was solved once, correctly, and never propagated.** Any fix should propagate what is
already here rather than invent a new idiom.

## Fix candidates — all measured, none landed

| Candidate | Fixes | Measured result |
|---|---|---|
| `find … \| sort \| while IFS= read -r` | M1, M2 | 12/12 across bash 3.2.57, zsh 5.9, **and POSIX `sh`**; ordering matches glob collation under both `C` and `en_US.UTF-8` (glob and `sort` share `LC_COLLATE`, so they cannot diverge) |
| nullglob shim + `${#ARR[@]} -gt 0` | M1, M2 | Correct in both shells; **the in-tree precedent**. Sets a global shell option — #3409's G4 defect is a shim leaking into a later block in the same session |
| `emulate -L sh` preamble | M1, M2, M5 | **3 of 6 in one line**, across all 902 fences. Does NOT fix M3/M4. Large blast radius — changes far more than three behaviours |
| `${#ARR[@]} -gt 0` **without** a shim | — | **WORSE than today** in bash: unmatched glob yields count 1 and emits `cat: …: No such file`, where `[ -e "${ARR[0]}" ]` correctly skips. Per the bash manual, without `nullglob` patterns *"expand to themselves"* |
| `find -print0 \| sort -z \| xargs -0` | M1, M2 | Correct, but all three flags are non-POSIX and appear **zero times** in this repo; against the spirit of `scripts/lint-portable-timeout.cjs` (#2351) |
| `verification.resolve-file` (existing verb) | M1, M2 at VERIFICATION sites | **No new code.** Already exists (`src/verification.cts:834-853`), added by #3357/PR #3513 for exactly this class. Swap at `gsd-verifier.md:85-86` is **7 bytes shorter** — load-bearing at 2 bytes of headroom |

## Why four fix rounds missed it

`tests/unreachable-shell-guard.test.cjs:148` extracts the **live** fences from shipped `.md` —
deliberately, to avoid drift — then executes them under a hardcoded `#!/usr/bin/env bash` with
`interpreter: 'bash'`. The runtime uses the login shell.

**The harness binds to the deployed contract and validates it against a shell the deployment does
not use.** Every guard passes; every guard is dead where it runs.

Upstream trail, each round fixing the shape visible under bash:
**#2770 → #2962** (for-list globs; shipped the nullglob shim) **→ #3300** (*"nullglob from #2962
defeats the ls-guards … empty section files"* — the #2962 fix caused this one) **→ #3409**
(guard-hardening; introduced the `${ARR[0]}` array form now under discussion).

**A dual-shell harness is the only change that makes all six mechanisms visible at once.**
Without it, each mechanism needs its own regex lint — and ADR-1703 explicitly condemns that
accretion: *"three parsers, two escape conventions, and a permanent grandfather list — to do a job
that a linter does natively … growing the regex path is the wrong direction."*

## Constraints any fix must satisfy

- **`agents/gsd-verifier.md` has 2 bytes of headroom** (49,150 / 49,152, tier LARGE per
  `tests/agent-size-budget.test.cjs:66`). Any net addition there fails the build.
- **`scripts/lint-unreachable-guard-drift.cjs`** scans `gsd-core/workflows`, `commands`, `agents`
  **and `skills`** — baseline 0, ratchet, no allowlist escape. This is the gate that grades the fix.
- **Changeset `type: Fixed`** (`src/`, `agents/`, `commands/` are in `USER_FACING_PREFIXES`).
  `Fixed` is not in `TRIGGERING_TYPES`, so the docs-required gate is a no-op. Precedent:
  `run-with-timeout` added a whole new verb and still shipped `type: Fixed`.
- **One concern per PR** (`CONTRIBUTING.md:195`) and *"an enhancement does not add new commands"*
  (`:52`) — a new verb cannot ride in a fix PR.
- New tests must route subprocess spawns through `tests/helpers/process-seam.cjs`
  (`local/no-unbounded-spawn`, no allowlist since #3148).
- `node scripts/sync-runtime-launcher.cjs` inserts the `gsd_run` preamble idempotently for
  `agents/` + `gsd-core/workflows/` — but **not** `commands/` or `skills/`.

## Structural gaps this exposed (separate concerns)

- **`skills/` is absent from three lint scan-dirs** — `no-bare-gsd-tools-command-position.test.cjs`,
  `sync-runtime-launcher.cjs`, `no-hardcoded-home-gsd-tools.test.cjs` all scan only `agents/` +
  `gsd-core/workflows/`.
- **Nothing enforces `commands/gsd/<name>.md` ↔ `skills/gsd-<name>/SKILL.md` body parity** — verified by
  direct diff: bodies near-identical, only frontmatter differs. This is why two copies of the same
  broken code shipped undetected.
- **No test validates that a `gsd_run <verb>` call site names a live verb** — which is why
  `agents/gsd-plan-checker.md:758,760` calls `phase.list-artifacts`, a verb that does not exist
  (`Unknown phase subcommand`).
- **Bare unshimmed `gsd-tools` calls** at `commands/gsd/review-backlog.md:39,52` and its SKILL twin.

## Open questions

1. Per-site portability rewrite (25+ sites, 6 mechanisms, a lint each) vs. one `emulate -L sh`
   preamble (3 of 6, one line, 902 fences of blast radius)? Undecided — the harness should inform
   this rather than prediction.
2. Are `hooks/*.sh` in scope? They carry `#!/usr/bin/env bash` and use `BASH_REMATCH` legitimately.
   Out of scope **if** invoked via their own shebang; the wiring through
   `managed-hooks-registry.cjs`/`build-hooks.js` was never traced.
3. M3/M4 (`BASH_REMATCH`, `read -ra`) are **user-facing feature breakage** — `--wave`,
   `--granularity`, `/gsd:code-review --files` all silently ignored on macOS. Arguably higher
   priority than M1, which merely loses context.

## Cross-references

- Actionable item: `.planning/todos/pending/2026-08-21-zsh-array-index-guards-silently-read-nothing.md`
- Blocked by this: `.planning/todos/pending/2026-08-20-port-4-10-mempalace-recall-line-in-the-planner.md`
- Campaign context: `.planning/runbooks/porting-local-patches-to-the-fork.md` §4.10, §7

## Document log

| Date | Change |
|---|---|
| 2026-08-21 | Created. Six mechanisms, 1048-fence sweep, 25 sites, six fix candidates measured. No fix landed. |
