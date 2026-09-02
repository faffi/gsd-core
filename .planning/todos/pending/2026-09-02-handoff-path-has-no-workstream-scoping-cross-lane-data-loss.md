---
created: 2026-09-02T00:00:00.000Z
title: "HANDOFF.json/pause-work/resume-project have no workstream scoping — one lane's pause silently destroys another's handoff, already happened once"
area: workflows
severity: blocker
scope: Medium
scope_note: Three related fixes in the same subsystem (HANDOFF.json scoping, the delete-on-resume instruction, a missing quick-task branch) — related enough to land together per the reporter's own workaround, but each independently testable; not a one-line patch given the resume-side fallback logic needs writing too
files:
  - gsd-core/workflows/resume-project.md:71 (hardcoded `cat .planning/HANDOFF.json` — no --ws scoping, no workstream fallback)
  - gsd-core/workflows/resume-project.md:80 ("`.continue-here*.md` discovery via `find .planning -maxdepth 3` — already correctly multi-lane-capable, the asymmetry is the bug")
  - gsd-core/workflows/resume-project.md:112 ("After successful resumption, delete HANDOFF.json (it's a one-shot artifact)")
  - gsd-core/workflows/pause-work.md:67,217 (writes/commits `.planning/HANDOFF.json` unconditionally — no workstream-scoped path)
  - gsd-core/workflows/pause-work.md:14-35 (`detect` step — phase/spike/sketch/deliberation/research/default; no `quick` branch, so a quick task falls to `default` and writes the ROOT `.continue-here.md`)
---

## Problem

Reported by peer session `plane-custom-fields` (cross-session message, 2026-09-02), running
three parallel GSD workstreams in one repo on GSD 1.12.0. Verified directly against this
repo's own source (all three line citations confirmed by reading the files, not taken on
their word).

**1. `HANDOFF.json` has no workstream variant.** `resume-project.md:71` reads the single
hardcoded root path; `pause-work.md:67` writes to that same single path, unconditionally,
regardless of an active workstream. With N parallel workstreams, exactly one structured
handoff can exist repo-wide — each lane's `/gsd:pause-work` silently overwrites whatever the
previous lane left there. The reporter's own root `HANDOFF.json` belonged to an unrelated
lane; pausing their own lane would have destroyed it. **The asymmetry that makes this a bug
and not just an inherent limitation**: `.continue-here.md` does NOT have this problem —
`resume-project.md:80`'s discovery (`find .planning -maxdepth 3 -name '.continue-here*.md'`)
already reaches `.planning/workstreams/<ws>/.continue-here.md` (depth 3 from `.planning`),
confirmed by the reporter finding two lanes' files simultaneously. So the markdown half is
already workstream-safe; only the structured JSON half isn't — meaning a workstream-scoped
`.continue-here.md` can end up referencing a JSON companion that was never written for it
(or was overwritten by another lane).

**2. 🔴 `resume-project.md:112` instructs deleting the single shared `HANDOFF.json` after
every resumption.** Combined with #1, this is actively destructive across lanes: lane A
resumes and deletes the one `HANDOFF.json`, taking lane B's still-pending handoff with it.
**Already fired once in the reporter's repo** — a prior session followed this instruction
and destroyed a handoff that had to be recovered from git (commit `88eaca0f79`), now
documented as a scar in that lane's own `.continue-here.md`. Even single-lane, deleting a
small, git-tracked, cheap-to-keep file on every resume is a hazard for no real benefit.

**3. `pause-work.md`'s destination-detection step has no `quick`-task branch.** The `detect`
step (`pause-work.md:14-35`) checks phase / spike / sketch / deliberation / research, then
falls to `default` (root `.continue-here.md`) for anything else. A quick task
(`.planning/workstreams/<ws>/quick/<id>-<slug>/`) matches none of the named branches, so
pausing one writes straight into the root handoff — i.e., into whatever another lane already
owns there — for a task type that's fully self-describing on disk and didn't need a root
handoff at all.

**Workaround the reporter used, offered as the documented pattern until fixed:** write the
full handoff at `.planning/workstreams/<ws>/.continue-here.md` (already collision-free per
#1's asymmetry), leave root `HANDOFF.json`/`.continue-here.md` to whichever lane already owns
them, and add a banner at the top of the workstream file warning that `/gsd:resume-work` will
read the *other* lane's `HANDOFF.json` first and announce the wrong workstream — so a human
has to know to ignore it. That banner is itself evidence of the gap; it shouldn't need to
exist.

## Fix

Per the reporter's own suggestions, verified plausible against the files above:

1. Resume reads `.planning/workstreams/<ws>/HANDOFF.json` first (when a workstream is
   active), falling back to the root path — backwards compatible.
2. Pause writes to the workstream-scoped path when a workstream is active, root path
   otherwise.
3. Stop instructing unconditional deletion at `resume-project.md:112` — archive to
   `HANDOFF.<timestamp>.json` instead, or at minimum scope the deletion to the resuming
   workstream's own file once (1) lands, so it can never touch a different lane's file.
4. Add a `quick`-task branch to `pause-work.md`'s `detect` step, writing to the quick task's
   own directory (or skipping handoff generation entirely for quick tasks in favor of
   `/gsd:quick resume <slug>`, which already has everything it needs on disk).

## Cross-references

- Reported by peer session `plane-custom-fields` (cross-session message, 2026-09-02),
  three-workstream repo on GSD 1.12.0.
- Related, same "multi-lane collision" family, filed separately (lower severity, different
  subsystem): `2026-09-02-windows-md-id-collision-and-fixed-status-drops-reason.md`.
