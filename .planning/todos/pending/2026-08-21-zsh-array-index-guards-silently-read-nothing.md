---
created: 2026-08-21T02:30:00.000Z
title: zsh glob guards in shipped fences abort the block on the common no-match path (11 sites; a 12th is an unrelated PIPESTATUS bug)
area: tooling
resolves_phase: 4
severity: blocker
scope: Large
scope_note: The single largest item in this list — 1048 fences swept, 4 new failure-mode families beyond the original scope, a mandatory cross-shell test harness parameterization, and multiple merge gates; blocks the port-4-10 todo
files:
  - agents/gsd-planner.md:659-660,697-702 (4 guards — SUMMARY, CONTEXT, RESEARCH, DISCOVERY; NO nullglob shim)
  - agents/gsd-phase-researcher.md:548-549 (CONTEXT; no shim)
  - agents/gsd-verifier.md:85-86 (VERIFICATION; no shim)
  - gsd-core/workflows/transition.md:231-232 (SUMMARY; no shim)
  - gsd-core/workflows/session-report.md:37-38 (prior reports; no shim)
  - commands/gsd/review-backlog.md:22 (backlog; no shim)
  - skills/gsd-review-backlog/SKILL.md:22 (backlog; no shim)
  - gsd-core/workflows/audit-fix.md:145 (AUDIT_TEST_EXIT=${PIPESTATUS[0]} — swallows a TEST EXIT CODE)
  - gsd-core/workflows/complete-milestone.md:369-370 (SUMMARY; HAS the shim, still broken)
  - gsd-core/workflows/review.md:269-273 (CONTEXT, RESEARCH; HAS the shim, still broken — the #3300 file)
  - gsd-core/workflows/resume-project.md:67-68 (the sanctioned #2962 nullglob shim, for reference)
---

> **📓 The whole picture lives in `.planning/reference/shell-fence-portability.md`** — six
> mechanisms, the full 25-site inventory with per-site status, six measured fix candidates, the
> upstream trail, and the merge constraints. **Update that document in the same commit as any
> fix**; it is `reference/`, so a stale row there is a bug. This todo is the actionable item.

## ⚠ CORRECTED 2026-08-21 by a 5-agent review — read this before the section below

The original framing (title included) is **wrong about the primary mechanism**, and the site
count is inflated. Verified by execution and by reading each file.

**1. The fatal failure is NOMATCH ON THE ASSIGNMENT, not `${ARR[0]}` indexing.**
When the glob does NOT match — the COMMON case, since CONTEXT/RESEARCH/DISCOVERY are all
optional by design — `_CTX=( "$dir"/*-CONTEXT.md )` **aborts the entire fence** under zsh:
```
$ /bin/zsh -c 'eval "_CTX=( ./*-CONTEXT.md ); echo reached"'
zsh: no matches found: ./*-CONTEXT.md      # "reached" never prints, exit 1
```
Indexing is the *secondary* bug (silent empty read when the glob DOES match). So the title
understates it: not "silently read nothing" but "crash the block, on the normal path."

**2. It CASCADES.** `agents/gsd-planner.md:697-702` chains three globs in ONE fence. A missing
`RESEARCH.md` kills the `DISCOVERY.md` read at :701-702 — even when DISCOVERY.md exists.

**3. `gsd-core/workflows/review.md:269,273` does NOT use `${ARR[0]}`** — it uses
`if [ ${#_CTX[@]} -gt 0 ]`. Still broken, but via NOMATCH-on-assignment only. The inventory
table below lists it under the wrong mechanism.

**4. `gsd-core/workflows/audit-fix.md:145` is a DIFFERENT BUG** — `PIPESTATUS` (uppercase) does
not exist in zsh in any form; zsh's is lowercase `pipestatus`, 1-indexed. Not a glob bug, not
fixable by any glob change. **Carve it out as its own one-line fix.** It inflated the count.

**5. FALSE UNIFICATION** — the sites do not want the same operation:
9 × `cat` (content) · 1 × `ls -la` (session-report, metadata) · 2 × `ls -d` (review-backlog,
*directories* via `999*`) · 1 unrelated (audit-fix). A single "read+cat" mechanism serves 9 of 12.

**6. "Just fix the index" (`[0]`→`[1]`, or a length check) is NOT a fix** — it leaves the
NOMATCH crash fully intact. review.md already uses the length form and is still broken.

## Chosen fix — validated 8/8 across bash 3.2.57 and zsh 5.9

```bash
while IFS= read -r f; do cat "$f"; done < <(find "$d" -maxdepth 1 -name '*-CONTEXT.md' 2>/dev/null | sort)
```
Matched/unmatched, multi-file ordering (`03 01 10 02` → `01 02 03 10`, identical to glob
collation), spaces in names, missing dir, empty variable, and **loop-variable state survives**
(process substitution `< <()` does not fork a subshell; `cmd | while read` is the only form
that loses state — do not use it).

**This is the codebase's DOCUMENTED policy, not an invention** —
`gsd-core/workflows/code-review.md:668-669`: *"macOS ships with bash 3.2 (GPL licensing). This
workflow does NOT use `mapfile` (bash 4+ only) — all array construction uses portable
`while IFS= read -r` loops compatible with bash 3.2."* All testing was done on the real macOS
system bash (3.2.57), not a Homebrew 5.x.

**Rejected alternative:** `if [ -n "$ZSH_VERSION" ]; then setopt NULL_GLOB; fi` + for-glob tied
on all 8 cells and needs no external binaries — but it sets a GLOBAL shell option, which is
exactly #3409's G4 defect ("a nullglob left set by an earlier block in the SAME shell session").
Tie on behaviour → take the one that cannot leak state.

**Also rejected:** `find -print0 | sort -z | xargs -0`. Measured identical to the chosen form on
every cell, but `-print0`/`sort -z`/`xargs -0` appear **zero times** in this repo and are all
non-POSIX GNU/BSD extensions — against the spirit of `scripts/lint-portable-timeout.cjs` (#2351),
which bans GNU-only tools in shipped fences because stock macOS lacks them. CI includes
`windows-latest`.

**Also rejected:** `${#ARR[@]} -gt 0` WITHOUT a nullglob shim — strictly WORSE than today in
bash: unmatched glob yields count 1 (the literal pattern) and emits
`cat: ...*-CONTEXT.md: No such file or directory`, where the current `[ -e "${ARR[0]}" ]`
correctly skips. Confirmed against the bash manual: *"If `nullglob` is set, patterns that match
no files expand to nothing and are removed, rather than expanding to themselves."*

## The VERIFICATION sites need no new code — an existing verb already owns the rule

`gsd_run query verification.resolve-file "$PHASE_DIR" --raw` exists
(`src/verification.cts:834-853`). Added by **#3357 → PR #3513** for EXACTLY this class:

> *"The issue named two copies. There were seven, in four grammars… and two in shell. All seven
> now route through one exported `resolveVerificationFile`; the shell copies via a new
> `verification resolve-file` verb rather than hand-rolling the rule an eighth time."*

Replacing `agents/gsd-verifier.md:85-86` with it is **7 bytes SHORTER** (96 → 89) — which is
load-bearing: that file is **49,150 bytes against a 49,152 cap (2 bytes of headroom)**, tier
LARGE per `tests/agent-size-budget.test.cjs:66`. Any net addition there fails the build.

## Scope — CONTRIBUTING.md forces a split

`CONTRIBUTING.md:195` *"One concern per PR"* and `:199` *"Scope matches the approved issue."*
`:52` *"An enhancement… does **not** add new commands, new workflows, or new concepts."*

**IN SCOPE (one fix PR):** the glob idiom at the no-selection-rule sites; routing VERIFICATION
through the existing verb; `scripts/lint-portable-glob-guard.cjs` as a ratchet (precedent: the
#2351 PR shipped its own ratchet in the same PR); a regression test (`:43` *"Write a test that
would have caught the bug"*).

**OUT OF SCOPE — separate items, must NOT be bundled:**
- A verb exposing `scanPhasePlans.summaryFiles`. **No verb exposes it today** and
  `summaryFiles` is returned in filesystem order, unsorted (`src/plan-scan.cts` concatenates raw
  `readdirSync`; `src/phase.cts:537` sorts client-side). A new verb = a new command =
  enhancement/feature class, needs its own approved issue BEFORE any code.
- `audit-fix.md:145` PIPESTATUS — different mechanism.
- **`phase.list-artifacts` DOES NOT EXIST** but is called twice at
  `agents/gsd-plan-checker.md:758,760`. Runtime: `Unknown phase subcommand. Available:
  uat-passed, next-decimal, add, add-batch, insert, remove, complete, list-plans`. Nothing
  catches it — **no test validates that a `gsd_run <verb>` call site names a live verb.**
- Bare unshimmed `gsd-tools query phase.add` / `commit` calls at
  `commands/gsd/review-backlog.md:39,52` and its byte-identical SKILL.md twin — the exact bug
  `tests/no-bare-gsd-tools-command-position.test.cjs` exists to catch.
- **Structural gap behind several of these:** that lint, `scripts/sync-runtime-launcher.cjs`,
  and `tests/no-hardcoded-home-gsd-tools.test.cjs` all scan only `agents/` + `gsd-core/workflows/`.
  **`skills/` is in none of them**, and nothing enforces `commands/gsd/X.md` ↔ `skills/gsd-X/SKILL.md`
  body parity — which is why two copies of the same broken code shipped undetected.

## Merge gates (verified, with commands)

- **Changeset required** (`src/`, `agents/`, `commands/` are all in `USER_FACING_PREFIXES`,
  `scripts/changeset/lint.cjs:32-39`) — **`--type Fixed`**. Precedent: `run-with-timeout` added a
  whole new verb and still shipped `type: Fixed` (`.changeset/2351-portable-timeout.md`).
  `Fixed` is NOT in `TRIGGERING_TYPES` (`scripts/lint-docs-required.cjs:37`), so the
  docs-required gate is a **no-op**.
- **`scripts/lint-unreachable-guard-drift.cjs`** scans `gsd-core/workflows`, `commands`, `agents`
  AND `skills` — baseline 0, ratchet with no allowlist escape. This is the gate that grades the fix.
- **New tests must route subprocess spawns through `tests/helpers/process-seam.cjs`**
  (`local/no-unbounded-spawn`, no allowlist since #3148) — directly relevant, since testing a
  cross-shell fix means spawning both shells.
- **`node scripts/sync-runtime-launcher.cjs`** inserts the `gsd_run` preamble into
  `session-report.md` byte-identically and idempotently (verified in a scratch tree) — but leaves
  the orphaned consumer line for hand-rewriting. Do NOT hand-copy the 2.8KB one-liner.
- Shim status: 7 of 10 target files already carry it; `session-report.md` and the two
  `review-backlog` copies do not (the latter two have no generator coverage at all).
- **`--pick` on an array COMMA-joins** (`String(['a','b c'])` → `a,b c`), so JSON+`--pick` is the
  wrong shape for multi-path output. Newline-`--raw` + `while read` is the only idiomatic form.
- **The `@file:` >50KB spill guard is in the JSON branch ONLY** (`src/io.cts:144-160`); raw output
  writes `String(rawValue)` with no size check. Any future verb must return PATHS, never contents.

## The harness is why this survived four fix rounds

`tests/unreachable-shell-guard.test.cjs:148` extracts the LIVE fences from shipped `.md` — good —
then executes them under a hardcoded `#!/usr/bin/env bash` with `interpreter: 'bash'`. The runtime
executes them under the user's login shell, which on macOS is zsh. **The test binds to the deployed
contract and validates it against a shell the deployment does not use.** Every guard passes; every
guard is dead where it runs. Upstream trail: #2770 → #2962 → #3300 → #3409, each fixing the shape
that was visible under bash. **Parameterizing that harness over both shells is mandatory, not
optional** — without it nothing catches a regression.

## Problem

**zsh arrays are 1-indexed.** `${ARR[0]}` is the empty string whether or not the glob matched.
Every guard of the shape below therefore evaluates false under zsh and the file is **never
read — even when it exists**:

```bash
_CTX=( "$phase_dir"/*-CONTEXT.md )
if [ -e "${_CTX[0]}" ]; then cat "${_CTX[@]}"; fi
```

Measured (`zsh 5.9`, macOS default shell), file **present**:

| form | bash | zsh |
|---|---|---|
| current array guard | reads it | **reads nothing** |
| the 1.10.0 `cat glob 2>/dev/null` it replaced | reads it | reads it |

```
zsh:  a=( .../MEMORY-RECALL.md ); [0]=<>  [1]=</...MEMORY-RECALL.md>  count=1
bash: a=( .../MEMORY-RECALL.md ); [0]=</...MEMORY-RECALL.md>  [1]=<>  count=1
```

**This matters because Claude Code's Bash tool runs the user's login shell.** Verified in-session:
`$0 = /bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset. So on any macOS machine with the
default shell, `gsd-planner` never reads CONTEXT.md, RESEARCH.md or DISCOVERY.md.

## Two INDEPENDENT variants — the shim only fixes one

1. **NOMATCH** — an unmatched glob aborts the whole block under zsh. Fixed by the sanctioned
   #2962 shim (`gsd-core/workflows/resume-project.md:67-68`):
   `shopt -s nullglob 2>/dev/null; setopt NULL_GLOB 2>/dev/null`
2. **1-indexing** — `${ARR[0]}` empty. **The shim does NOT fix this.** Measured: with the shim
   applied, zsh still reads nothing when the file is present.

`for X in <glob>` loops (the shape #2962 targeted) are **fully covered** — all 9 live in the 7
shimmed files. The gap is entirely the array-index form.

## Inventory — 12 sites, 10 files

| File | Lines | Reads | shim? |
|---|---|---|---|
| `agents/gsd-planner.md` | 660, 698, 700, 702 | SUMMARY, CONTEXT, RESEARCH, DISCOVERY | ✗ |
| `agents/gsd-phase-researcher.md` | 549 | CONTEXT | ✗ |
| `agents/gsd-verifier.md` | 86 | VERIFICATION | ✗ |
| `gsd-core/workflows/transition.md` | 232 | SUMMARY | ✗ |
| `gsd-core/workflows/session-report.md` | 38 | prior reports | ✗ |
| `commands/gsd/review-backlog.md` | 22 | backlog | ✗ |
| `skills/gsd-review-backlog/SKILL.md` | 22 | backlog | ✗ |
| `gsd-core/workflows/audit-fix.md` | 145 | **test exit code** | ✗ |
| `gsd-core/workflows/complete-milestone.md` | 370 | SUMMARY | ✓ |
| `gsd-core/workflows/review.md` | 269-273 | CONTEXT, RESEARCH | ✓ |

The 8 unshimmed files carry **both** variants: NOMATCH on absence, silent skip on presence.

## The worst one is not a missed read

`gsd-core/workflows/audit-fix.md:145` — `AUDIT_TEST_EXIT=${PIPESTATUS[0]}`

```
bash   PIPESTATUS[0]=<1>
zsh    PIPESTATUS[0]=<>      # zsh uses $pipestatus, lowercase, 1-indexed
```

That captures a **test-suite exit code**. Under zsh a failing run yields the empty string.

## Upstream history — three rounds landed next to this bug

- **#2770** → **#2962** (CLOSED) *"unmatched globs in `for` word lists abort the whole block
  under zsh — silently bypasses verify-phase's decision-coverage gate (re-opens #2770 on macOS)"*
- **#3300** (CLOSED) *"nullglob from #2962 defeats the ls-guards for CONTEXT.md/RESEARCH.md in
  build_prompt — empty section files"* — the #2962 fix caused this one
- **#3409** / `15914543 feat(#3409): reject shell guards that cannot observe their own failure arm (#3558)`
  introduced the array-index form now under discussion

`review.md` is the #3300 file. It is marked CLOSED, but the replacement form is **still broken
on zsh**, differently. Each round fixed the shape that was visible; every failure in this class
is silent and fails in the safe-looking direction (guard false, file unread, status empty), so
nothing errors and no test notices.

## Verified fixes

Both measured across bash 5.x and zsh 5.9, glob matching and not:

**Guards — shim + element count** (keeps the block's idiom, minimal diff):
```bash
shopt -s nullglob 2>/dev/null; setopt NULL_GLOB 2>/dev/null
_CTX=( "$phase_dir"/*-CONTEXT.md )
if [ "${#_CTX[@]}" -gt 0 ]; then cat "${_CTX[@]}"; fi
```
`${#ARR[@]}` is correct in both shells; nullglob makes an unmatched glob yield an empty array
instead of aborting. Requires **both** parts — the count alone still hits NOMATCH.

**Alternative — `find`, no shim required:**
```bash
find "$phase_dir" -maxdepth 1 -name '*-CONTEXT.md' -exec cat {} +
```
Silent on no-match, exit 0, correct in both shells. Already the documented preference in
`resume-project.md:74-76` ("Use `find` rather than a chained `ls` of bare globs"). Deviates
further from the current idiom.

**PIPESTATUS:**
```bash
AUDIT_TEST_EXIT=${PIPESTATUS[0]:-${pipestatus[1]}}
```
Verified `<1>` in both shells. Avoiding the pipe entirely also works.

## Solution

Recommend the shim + count form for all 11 guard sites (smallest diff, preserves the
established idiom, no new dependency on `find` semantics), and the `PIPESTATUS` fallback for
`audit-fix.md:145`.

**Test shape:** a portability test that greps shipped `.md` fences for `${ARR[0]}` on an array
built from a glob and fails on any hit — this class is invisible to behavioural tests because
it never errors. `tests/policy-shell-pinning.test.cjs` and `scripts/workflow-policy.cjs` are
the existing precedent for lint-style shell policy enforcement.

**Upstream viability: strong** — reproducible, measurable, affects every macOS default-shell
user, and continues a line of work the maintainers have already accepted three times.

## Provenance

Found 2026-08-21 while porting concern 4.10 (mempalace recall line). Writing the new line in
the block's current idiom and then testing it revealed the idiom itself is dead under zsh.
4.10 is **blocked** on this: adding a 4th guard in the same form would ship a line that
provably never fires. See
`.planning/todos/pending/2026-08-20-port-4-10-mempalace-recall-line-in-the-planner.md` and
`.planning/runbooks/porting-local-patches-to-the-fork.md` §4.10.

## Exhaustive sweep — 2026-08-21, 1048 bash fences / 6413 lines across next@7cf6a079

Scope confirmed complete: `contexts/`, `templates/`, `capabilities/` carry no agent-executed
fences; the 394 other files with bash fences are `docs/**` + README (human-facing). All 777
untagged fences re-scanned for the 5 severest patterns — zero hits.

| Mode | Count | Effect under zsh |
|---|---|---|
| Array-from-glob, UNPROTECTED | **11** | aborts fence on no-match; silently skips on match |
| Array-from-glob, protected | 2 | correct (`review.md:269,273`) |
| `${ARR[0]}` compounding the above | 9 | never reads the file EVEN WHEN IT EXISTS |
| `BASH_REMATCH[N]` | **7** | CLI flags parse to empty |
| Word-split on stored `$VAR` | 5 (+1 embedded) | one giant item instead of N |
| `read -ra` | 1 | hard error, array stays empty |
| `${PIPESTATUS[0]}` | 1 | timeout detection never fires |
| bare glob in command position | ~160 genuine | stderr noise only, NOT fatal |
| `for x in glob` | 10 | **all protected** — full coverage |

### THREE CORRECTIONS to this todo's earlier framing

1. **Only array-assign and for-list globs ABORT.** A bare command-position glob (`cat glob`,
   `ls glob`) or a glob inside `$(...)` does NOT abort — the command fails, zsh prints
   `no matches found`, the script CONTINUES. Two severity tiers, not one.
2. **`2>/dev/null` cannot suppress zsh's NOMATCH message** — emitted during word-expansion,
   before the command and its redirections exist. Only `{ ...; } 2>/dev/null` suppresses it.
   ~160 sites leak that line whenever an artifact is absent.
3. **`$(...)` DOES word-split in zsh** — only bare `$VAR` does not. Six suspected sites
   (`next.md:124,280`, `autonomous.md:84`, `plan-review-convergence.md:66`, `review.md:363`,
   `sync-skills.md:40`) are SAFE. Retracted.

### FOUR NEW FAILURE MODES — separate concerns, each needs its own fix

- **`read -ra` is a hard error in zsh** (`gsd-core/workflows/code-review.md:78`). Measured:
  `zsh:read:1: bad option: -a`, array length 0. **`/gsd:code-review --files` is silently ignored
  on every macOS run** — no crash, nothing surfaced to the user.
- **`BASH_REMATCH[N]` is empty in zsh** (zsh populates `$match`/`$MATCH`). 7 sites, 3 files:
  `gsd-core/references/phase-argument-parsing.md:39`, `gsd-core/workflows/execute-phase.md:84`,
  `gsd-core/workflows/plan-phase.md:70,71,72,73,127`. Breaks `--wave N`, `--granularity X`,
  `--prd`, `--ingest`, `--research-phase`, phase-decimal normalization. Measured: bash `[3]`, zsh `[]`.
- **Word-splitting on a stored variable** — 5 sites:
  `execute-phase/steps/per-plan-worktree-gate.md:35,40`, `pr-branch.md:265`,
  `sync-skills.md:240,245` (the last iterates 70+ skills as ONE item), plus one embedded in a
  spawned-subagent template at `quick.md:467-470`.
  Caveat RESOLVED 2026-08-21: `SH_WORD_SPLIT` is NOT set here (absent from `setopt`, 0 hits in
  `~/.zshrc`), so these hold.
- **`${PIPESTATUS[0]}`** (`audit-fix.md:145`) — already carved out above.

### The one CORRECT implementation already in the tree

`gsd-core/workflows/review.md:248-273` has BOTH the nullglob shim AND `${#_CTX[@]} -gt 0`
(length check, not `[0]`). It is the only fully-correct instance in 1048 fences — and it is the
file **#3300** was filed against. The pattern was solved once and never propagated.
**The fix applies a pattern already in the tree; it does not invent one.**

WARNING — `complete-milestone.md` is the trap: a shim at :331 protects the for-loop at :335, but
the glob-array at :369 is in a DIFFERENT fence and unprotected. Checking "does this file have the
shim" gives a false pass.

### Unconfirmed

`hooks/*.sh` carry `#!/usr/bin/env bash` and use `BASH_REMATCH` legitimately. Out of scope IF
invoked via their own shebang — the wiring through `managed-hooks-registry.cjs`/`build-hooks.js`
was not traced. If any hook is invoked as `sh script.sh`, re-audit.

## A second correct reference implementation exists — not yet in this repo

`~/Desktop/gsd-1.10.0-mods/SPEC-05-concurrent-cross-ai-review.md` (Risks section) independently
documents the same word-split class this todo's "FOUR NEW FAILURE MODES" section covers: `wait
$PIDS` unquoted passes ONE argument under zsh, fails silently (`wait: job not found`), returns in
~7ms, and reports every still-running background lane as EMPTY with exit status **0** — worse than
a crash, because it looks like success. The fix is the array form (`PIDS=()` / `PIDS+=($!)` / `wait
"${PIDS[@]}"`), used correctly in the `gsd-review-concurrent` skill
(`.planning/todos/pending/2026-08-25-implement-gsd-review-concurrent-as-a-tracked-skill.md`,
property 4 — "written by someone who hit the bug in production and measured it"). That skill exists
today only at `$HOME/.claude/skills/gsd-review-concurrent/SKILL.md`, untracked in any repo — so this
is a second correct implementation to cite as prior art (alongside `review.md:248-273`) once it
lands in this repo, not a new site to fix here.
