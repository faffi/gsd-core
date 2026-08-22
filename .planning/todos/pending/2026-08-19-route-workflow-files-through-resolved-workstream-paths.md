---
created: 2026-08-20T01:51:52.025Z
title: Route workflow files through resolved workstream paths
area: tooling
severity: blocker
scope: Large
scope_note: 27 sites across 8 files — each individually mechanical, but the sweep plus a proposed follow-up lint rule adds up to a large PR, not a high-risk one
files:
  - gsd-core/workflows/resume-project.md:40
  - gsd-core/workflows/resume-project.md:71
  - gsd-core/workflows/resume-project.md:90
  - gsd-core/workflows/plan-phase.md:1335
  - gsd-core/workflows/quick.md:150
  - gsd-core/workflows/quick.md:469
  - gsd-core/workflows/fast.md:77
  - gsd-core/workflows/ship.md:510
  - gsd-core/workflows/ship.md:513
  - gsd-core/workflows/pause-work.md:67
  - gsd-core/workflows/review.md
  - gsd-core/workflows/pr-branch.md
  - .planning/research/2026-08-19-workstream-commit-path-defect.md (evidence, in-repo; incl. live gsd-tools run output)
---

## Problem

The `gsd-tools` CLI/query layer resolves workstream paths correctly (verified live:
`init.resume` and `init.plan-phase` return `.planning/workstreams/<ws>/STATE.md` when
`GSD_WORKSTREAM` is set), but eight `gsd-core/workflows/*.md` files never read that
resolved value — they hardcode the flat literal path instead. 27 flat-literal sites
(`.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`,
`.planning/HANDOFF.json`, `.planning/phases/`) across the 8 files below, zero
occurrences of the word "workstream" in any of them:

```
file                  flat-literals   "workstream"
pause-work.md               8              0
resume-project.md           4              0
review.md                   4              0
pr-branch.md                4              0
plan-phase.md                2              0
fast.md                      2              0
ship.md                      2              0
quick.md                     1              0
```

Independently verified against both `~/.claude/gsd-core` (installed) and this repo's
`next`/`working` — identical pattern in both, counts match exactly.

Reproduce (adjust `$W` to the workflows dir being checked):
```bash
W=path/to/gsd-core/workflows
for f in resume-project plan-phase quick fast ship pause-work review pr-branch; do
  lit=$(grep -c '\.planning/STATE\.md\|\.planning/ROADMAP\.md\|\.planning/REQUIREMENTS\.md\|\.planning/HANDOFF\.json\|\.planning/phases/' "$W/$f.md" || true)
  ws=$(grep -ci 'workstream' "$W/$f.md" || true)
  printf '%-22s %-6s %s\n' "$f.md" "${lit:-0}" "${ws:-0}"
done
```

**Cleanest single instance** — `resume-project.md`:40 calls `init.resume`, receives
`state_path` pointing at the workstream's STATE.md, and one step later runs
`cat .planning/STATE.md` anyway. The correct value was already in hand.

**Observed consequences (verified, not inferred), in a repo with an active workstream
whose flat `.planning/` belongs to a different, live milestone:**
- `resume-project.md:40` loads the WRONG milestone's STATE.md on resume.
- `quick.md` (zero "workstream" occurrences) derives its write path as
  `dirname(quick_dir)/STATE.md`, so step 7 writes the flat STATE.md — compounded by
  `:469` telling the executor not to commit STATE.md at all, which is fatal when a
  STATE.md edit *is* the task's payload.
- `fast.md:77` hardcodes `grep -q "Quick Tasks Completed" .planning/STATE.md` as a
  guard; when the flat file happens to already have that table (e.g. from a prior
  milestone), the guard passes and `/gsd-fast` appends a quick-task row to another
  milestone's live tracking file.
- `review.md`'s `gather_context` reads flat `.planning/REQUIREMENTS.md`, feeding
  external reviewers the wrong milestone's requirements (different length/content
  entirely from the workstream's).
- `plan-phase.md:1335` commits `--files "${PHASE_DIR}"/*-PLAN.md .planning/STATE.md
  .planning/ROADMAP.md` — flat literals, and the glob also sweeps in already-executed
  plans.

**Why it's nasty rather than merely wrong:** on a single-milestone repo the flat path
and the workstream path coincide, so every one of these passes. The defect only
manifests where a flat `.planning/` belongs to a DIFFERENT, live milestone — exactly
the case workstreams exist to create. Several of these are silent WRITES, not reads,
so the failure surfaces later, in a different worktree, as unexplained state drift.

**Prior art — this is a known bug CLASS, just never reached this layer.** CHANGELOG.md
has a long history of "X silently falls back to flat `.planning/` instead of respecting
the active workstream" fixes at the CLI/SDK layer: `workstream progress` (#1913),
`milestone complete --ws` (#1911/#1917), `phase complete` (#2066), `init progress`
(#1912), `roadmap update-plan-progress` (#1988), `config-get` under a workstream
(#2833), the statusline (#2850), concurrent-session pointer isolation (#3557/#3570),
and most recently `#3579`/PR `#3616` (closed 2026-08-18) — "a pointer-less session
inherits the repo active-workstream marker." **Checked `#3616`'s diff directly: it
touches only `gsd-core/bin/gsd-tools.cjs` and `src/*.cts` — zero files under
`gsd-core/workflows/`.** The resolver has been hardened repeatedly; the workflow
markdown that discards the resolver's output has not.

**Distinct from, do not conflate with:** a separate observation from the same session
— `gsd-plan-checker` completing twice with no returned verdict — is NOT this defect
(read-only, mutated nothing, reproduced under identical spawn conditions with
`gsd-planner` returning fine; absolute workstream paths were passed explicitly so it
never relied on resolution at all).

Originally surfaced via a cross-session message from a peer Claude session
(`bootstrap-terraform-75`, running milestone v1.12 in the `tenant-vpc-reach`
workstream) working the operator's `bootstrap-terraform` repo; independently
re-verified line-by-line against `~/.claude/gsd-core` and this repo's `next` before
capture.

## Solution

Every site already has the correct value in scope, or one query call away —
`resume-project.md` is a one-line change (use the `state_path` it already parsed from
`init.resume`). The pattern is mechanical enough that a lint rule asserting "no flat
`.planning/{STATE,ROADMAP,REQUIREMENTS}.md`/`HANDOFF.json`/`phases/` literal in
`gsd-core/workflows/*.md`" would hold the line once all 27 sites are converted —
mirrors the existing `local/no-source-grep` / `local/no-elapsed-assertion` pattern of
codifying a fixed defect class as a standing rule rather than trusting it stays fixed.
