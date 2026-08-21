---
created: 2026-08-21T02:30:00.000Z
title: zsh 1-indexed arrays make 12 glob guards silently read nothing (and one swallow a test exit code)
area: tooling
severity: blocker
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
