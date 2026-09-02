---
created: 2026-08-20T02:13:40.264Z
title: Fix pause-work's broken phase glob and dead gate
area: tooling
resolves_phase: 5
severity: blocker
scope: Large
scope_note: Cross-cutting across 6+ workflow files, five coupled sub-fixes that must ship together per the todo's own warning, plus six secondary findings
files:
  - gsd-core/workflows/pause-work.md:18
  - gsd-core/workflows/pause-work.md:21
  - gsd-core/workflows/pause-work.md:24
  - gsd-core/workflows/pause-work.md:35
  - gsd-core/workflows/pause-work.md:52
  - gsd-core/workflows/pause-work.md:53
  - gsd-core/workflows/pause-work.md:67
  - gsd-core/workflows/pause-work.md:106
  - gsd-core/workflows/pause-work.md:118-205
  - gsd-core/workflows/pause-work.md:148
  - gsd-core/workflows/pause-work.md:234
  - gsd-core/workflows/pause-work.md:248
  - gsd-core/workflows/execute-phase.md:220
  - gsd-core/workflows/discuss-phase.md:165
  - gsd-core/workflows/resume-project.md:67-68
  - gsd-core/workflows/resume-project.md:90
  - gsd-core/workflows/resume-project.md:109
  - gsd-core/workflows/resume-project.md:112
  - templates/continue-here.md:77
  - src/commands.cts (TRACKED SOURCE — edit here; the #3587 three-tier policy)
  - gsd-core/bin/lib/commands.cjs:1030 (gitignored BUILD OUTPUT — line ref only, never edit)
  - .planning/research/2026-08-19-pause-work-phase-glob-upstream-report.md (evidence, in-repo)
  - .planning/research/2026-08-20-pause-work-missing-directives-and-template-defects.md (related: template defects in the same workflow)
---

## Problem

`/gsd-pause-work`'s phase-detect glob never matches GSD's own plan filenames, so every
handoff lands at the planning root — a path the two workflows that enforce its
`blocking` anti-pattern gate never read. The gate `pause-work.md` calls **mandatory**
twice never fires. Silent on both ends: pause reports success, execute/discuss report
"no `.continue-here.md`, proceed directly."

Independently verified, every citation below confirmed on this machine against this
repo's `next`/`working`:

**1. The glob cannot match.**
```
gsd-core/workflows/pause-work.md:18
phase=$(( ls -lt .planning/phases/*/PLAN.md 2>/dev/null || true ) | head -1 | grep -oP 'phases/\K[^/]+' || true)
```
Plans are named `NN-PLAN.md`. 18 files in `gsd-core/` glob `*-PLAN.md`; this is the
only site using the bare `*/PLAN.md` form. `resume-project.md`'s equivalent (the
`for plan in .planning/phases/*/*-PLAN.md` loop, ~line 90) has it right.

Reproduced live:
```console
$ mkdir -p /tmp/t/.planning/phases/03-foo && touch /tmp/t/.planning/phases/03-foo/03-PLAN.md
$ cd /tmp/t && zsh -c 'phase=$(( ls -lt .planning/phases/*/PLAN.md 2>/dev/null || true ) | head -1 | grep -oP "phases/\K[^/]+" || true); echo "phase=[$phase]"'
zsh: no matches found: .planning/phases/*/PLAN.md
phase=[]
```

**2. Detection silently degrades to the `Default` branch** (`:35`) → handoff writes to
`.planning/.continue-here.md` (planning root), not the phase directory.

**3. The mandatory gate is dead.** `execute-phase.md:220` and `discuss-phase.md:165`
both check only:
```bash
ls ${phase_dir}/.continue-here.md 2>/dev/null || true
```
Never the root. Both take the "doesn't exist → proceed" branch. Blocking
constraints collected at `:52` — recorded specifically because they were *"discovered
through actual failure"* — go somewhere nothing reads. Directly contradicts `:53`
("the discuss-phase and execute-phase workflows will enforce a mandatory
understanding check") and `:148` ("...parse this table").

**4. Nothing ever cleans it up.** `templates/continue-here.md:77` says the file "gets
DELETED after resume — it's not permanent storage." `resume-project.md:112` deletes
only `HANDOFF.json`. No `rm`/`delete` near `continue-here` anywhere in `gsd-core/`.

**This inverts once #1 is fixed alone — do not ship a partial fix.** With the handoff
correctly placed in the phase dir, every later execute/discuss run re-triggers the
three-question understanding ritual against constraints resolved weeks ago. The gate
is currently dead; a naive one-line glob fix makes it permanently *stuck on*. Both
halves (#1 and #4) have to land together.

**Sub-bug — portability.** Lines 18/21/24 use PCRE `\K` via `grep -oP`. BSD grep has
no `-P` (`/usr/bin/grep -oP ... → grep: invalid option -- P`, reproduced on this
machine independently of the peer session's report). Appears to work under Claude
Code only because the harness shims `grep` to `ugrep`; any runtime that bypasses the
shim breaks all three detectors. Not macOS-only: the runtime-resolution preamble in
this same file branches across ~15 supported runtimes, several landing on
BusyBox/BSD userlands. `pause-work.md` also has none of the
`shopt -s nullglob; setopt NULL_GLOB` guarding `resume-project.md:67-68` added for
#2962 — confirmed present there, confirmed absent here — so that fix never reached
this file. Same class as #3409 (a guard that can't observe its own failure arm),
same shape as #2287 (a convention with no reader).

**Checked, not local drift:** `pause-work.md` has zero occurrences in
`~/.claude/scripts/gsd-local-patches-1.10.0.diff` — this is pristine upstream
behavior. No duplicate found on the upstream tracker (searched independently).

**Six secondary findings, all spot-checked and confirmed:**
- `uncommitted_files` hardcoded `[]` at `:106`, never populated — no `git status`
  anywhere in the workflow — yet `resume-project.md:109` tells the resuming agent to
  validate it against `git status`, flagging spurious divergence on every resume.
- `:234`/`:248` assert "Committed as WIP" unconditionally. `cmdCommit`
  (`bin/lib/commands.cjs:1030`, the #3587 three-tier policy) returns `skipped:true`
  when `.planning` is gitignored (the common case — including this repo). No branch
  for that first-class signal.
- Zero state reads anywhere: four `ls` detectors, one placeholder grep, two
  timestamps, one commit. Never reads `STATE.md`, never calls `state`/`progress`.
  Contradicts the skill's own `<context>` claim: "State and phase progress are
  gathered in-workflow with targeted reads."
- `HANDOFF.json` is a single hardcoded slot at `:67`. Confirmed: zero `GSD_WS`
  occurrences in `pause-work.md`, vs 7 in `resume-project.md` and 5 in
  `execute-phase.md`. A second workstream silently clobbers the first.
- Blocking constraints carry severity in the markdown but have no field at all in
  the `HANDOFF.json` schema — the one category `resume-project.md:103` calls "the
  primary resumption source" can't carry them.
- `templates/continue-here.md` has drifted from the copy inlined at
  `pause-work.md:118-205` (missing `context:` frontmatter key, blocking-constraints
  checklist, anti-patterns table, Required Reading, Infrastructure State,
  Pre-Execution Critique).

Originally surfaced via a cross-session message from a peer Claude session
(`claude-9b`), who did the initial repro, portability check, local-patches check,
and duplicate search; independently re-verified line-by-line — including running the
repro fresh and reproducing the BSD grep failure separately — before capture.

Cross-reference: touches the same file as
`.planning/todos/pending/2026-08-19-route-workflow-files-through-resolved-workstream-paths.md`
(`pause-work.md:67`, the `HANDOFF.json` path) but is a different root cause — that
todo is about workstream-path resolution being ignored; this one is about the
phase-detect glob and the dead gate. Not a duplicate.

## Solution

1. `pause-work.md:18` → `.planning/phases/*/*-PLAN.md`, matching `resume-project.md`.
2. Replace `grep -oP '...\K...'` on `:18`/`:21`/`:24` with a portable extraction
   (`sed` or shell parameter expansion); add the `#2962` nullglob preamble.
3. Prefer the canonical position source over the mtime heuristic entirely —
   `gsd-tools state`/`gsd-tools progress` already return structured position JSON,
   and `resume-project.md:24`'s `query init.resume` is the existing pattern.
   `ls -lt` answers "what did I plan most recently," not "what am I executing" —
   those diverge as soon as an earlier phase is replanned.
4. Have `discuss-phase`/`execute-phase` resolve `.continue-here.md` through the same
   path `pause-work` writes to (or have `resume-project` normalize it), so non-phase
   contexts get gated too.
5. Delete or archive `.continue-here.md` on successful resume, per the contract in
   `templates/continue-here.md:77`. **Ship with #1, not after** — landing the glob
   fix alone flips the gate from dead to stuck-on.
