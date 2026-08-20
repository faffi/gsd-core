bug(pause-work): phase-detect glob never matches `NN-PLAN.md` — every handoff lands at the planning root, where the mandatory blocking-anti-pattern gate cannot see it

---

**Version:** 1.11.0 (verified against the published tarball; also present in 1.10.0 — the two differ only in the `/gsd-` → `/gsd:` command rename)
**Platform:** macOS 15 / zsh 5.9, Claude Code runtime
**Area:** workflows/pause-work.md, workflows/discuss-phase.md, workflows/execute-phase.md

## Summary

`pause-work.md:18` detects the active phase with a glob that does not match GSD's own plan filenames. Detection always fails, the handoff always falls through to the `Default` branch, and it is written to a path that the two workflows enforcing its `blocking` anti-patterns never read. The gate that `pause-work.md` describes twice as **MANDATORY** never fires, and it fails silent on both ends — pause reports success, execute reports "no `.continue-here.md`, proceed."

## The defect chain

**1. The glob cannot match.**

```
gsd-core/workflows/pause-work.md:18
phase=$(( ls -lt .planning/phases/*/PLAN.md 2>/dev/null || true ) | head -1 | grep -oP 'phases/\K[^/]+' || true)
```

Plans are named `NN-PLAN.md`. Across `gsd-core/` in 1.11.0, **18 files** glob `*-PLAN.md`; `pause-work.md:18` is the only place using the bare `*/PLAN.md` form. `resume-project.md:90` — the direct counterpart that consumes this handoff — has it right.

**2. So detection silently degrades to `Default`.**

`phase` is unconditionally empty, so `pause-work.md:35` applies: handoff → `.planning/.continue-here.md`.

**3. So the mandatory gate is dead.**

`execute-phase.md:220` and `discuss-phase.md:165` both look in exactly one place:

```bash
ls ${phase_dir}/.continue-here.md 2>/dev/null || true
```

The file is at the planning root, not the phase dir. Both workflows take the "no `.continue-here.md` exists → proceed directly" branch. The blocking constraints — collected at `pause-work.md:52` specifically because they were *"discovered through actual failure"* — are written somewhere nothing reads.

This contradicts `pause-work.md:53` (*"the discuss-phase and execute-phase workflows will enforce a mandatory understanding check"*) and `:148` (*"the discuss-phase and execute-phase workflows parse this table"*).

**4. And nothing ever cleans it up.**

`templates/continue-here.md:77` states *"This file gets DELETED after resume — it's not permanent storage."* Nothing deletes it. `resume-project.md:112` deletes `HANDOFF.json` ("it's a one-shot artifact") and says nothing about the markdown; a grep for `rm`/`delete` near `continue-here` across `gsd-core/` returns nothing.

That inverts once step 1 is fixed: with the handoff correctly in the phase dir, every later `execute-phase` / `discuss-phase` run re-triggers the three-question understanding ritual against constraints resolved weeks earlier. The gate is currently dead; the naive fix makes it permanently stuck on. Both halves need to land together.

## Reproduction

```console
$ mkdir -p /tmp/t/.planning/phases/03-foo && touch /tmp/t/.planning/phases/03-foo/03-PLAN.md
$ cd /tmp/t && zsh -c 'phase=$(( ls -lt .planning/phases/*/PLAN.md 2>/dev/null || true ) | head -1 | grep -oP "phases/\K[^/]+" || true); echo "phase=[$phase]"'
zsh:1: no matches found: .planning/phases/*/PLAN.md
phase=[]
```

## Sub-bug: `grep -oP` is not portable, and pause-work is missing the #2962 nullglob guard

Lines 18, 21 and 24 all use PCRE `\K`. BSD grep has no `-P`:

```console
$ echo "phases/03-foo/PLAN.md" | /usr/bin/grep -oP 'phases/\K[^/]+'
grep: invalid option -- P
```

On macOS this currently appears to work only because the Claude Code harness shims `grep` to `ugrep`. Any context that bypasses the shim breaks all three detectors — including the spike and sketch ones, whose globs I verified *are* conventional elsewhere in the tree (`spikes/*/README.md` and `sketches/*/index.html` are both used by other workflows), so those two would otherwise work.

This is not a macOS-only nit: the runtime-resolution preamble in this same file branches across ~15 supported runtimes (26 config-dir branches), several of which land on BusyBox or BSD userlands where `-P` is absent or unbuilt.

Related: `pause-work.md` has none of the `shopt -s nullglob 2>/dev/null; setopt NULL_GLOB 2>/dev/null` guarding that #2962 added to `resume-project.md:67-68`. The fix never reached this file.

This is the #3409 class — a guard that cannot observe its own failure arm — and structurally the same shape as #2287 (a convention with no reader).

## Suggested fix

1. `pause-work.md:18` → `.planning/phases/*/*-PLAN.md`, matching `resume-project.md:90`.
2. Replace `grep -oP '...\K...'` on lines 18/21/24 with a portable extraction (`sed` or shell parameter expansion), and add the #2962 nullglob preamble.
3. Prefer the canonical position source over the mtime heuristic entirely: `gsd-tools state` and `gsd-tools progress` both already return structured position JSON, and `resume-project.md:24` uses exactly that pattern via `query init.resume`. `ls -lt` answers "what did I plan most recently?", not "what am I executing?" — those diverge as soon as an earlier phase is replanned.
4. Have `discuss-phase` / `execute-phase` resolve `.continue-here.md` through the same path list `pause-work` writes to (or have `resume-project` normalise it), so non-phase contexts are gated too.
5. Delete or archive `.continue-here.md` on successful resume, per the contract in `templates/continue-here.md:77`.

## Secondary findings in the same workflow

- **`uncommitted_files` is always `[]`.** Hardcoded at `pause-work.md:106`, never populated — the workflow never runs `git status`. But `resume-project.md:109` instructs the resuming agent to *"Validate `uncommitted_files` against `git status` — flag divergence"*, so resume flags spurious divergence on every resumption of a mid-task pause.
- **The WIP commit can silently not happen.** `cmdCommit` resolves a three-tier commit-docs policy (`bin/lib/commands.cjs:1030`, the #3587 refactor: `phase_commit_docs.<phase-id>` → `commit_docs` → `.gitignore`) and returns `{committed:false, skipped:true}` when any tier says no — including the common case of a gitignored `.planning/`. `pause-work.md:234` and the success criterion at `:248` both assert "Committed as WIP" unconditionally, with no branch for the first-class `skipped` signal that #3678 added precisely so prompts could match on it.
- **No state reads at all.** The whole workflow issues four `ls` detectors, one placeholder `grep`, two `current-timestamp` calls and the commit. It never reads `STATE.md` or calls `state`/`progress`, so every substantive field comes from the model's in-context memory — thinnest at exactly the moment `/gsd:pause-work` is reached for. The skill's own `<context>` block claims *"State and phase progress are gathered in-workflow with targeted reads."*
- **`HANDOFF.json` is a single hardcoded slot.** The path is literal `.planning/HANDOFF.json` at `pause-work.md:67`, and the workflow never references `GSD_WS` or passes `--ws` (0 occurrences, against 7 in `resume-project.md` and 5 in `execute-phase.md`). Pausing a second workstream overwrites the first with no detection, merge or warning.
- **Blocking constraints have no machine-readable form.** `pause-work.md:52` collects them with `blocking`/`advisory` severity, but the `HANDOFF.json` schema has no field for them — only `blockers`. Since `resume-project.md:103` calls `HANDOFF.json` "the primary resumption source", the highest-severity category is the only one absent from it.
- **Template drift.** `templates/continue-here.md` and the template inlined at `pause-work.md:118-205` have diverged; the shared file lacks the `context:` frontmatter key, the blocking-constraints checklist, the anti-patterns table, Required Reading, Infrastructure State and Pre-Execution Critique.
