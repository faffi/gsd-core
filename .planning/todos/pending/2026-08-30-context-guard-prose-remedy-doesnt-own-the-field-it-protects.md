---
created: 2026-08-30T00:00:00.000Z
title: "execute-phase context guard's prescribed remedy (/gsd:pause-work) is prose-only by default AND never writes the STATE.md field it's supposed to protect"
area: workflows
severity: major
scope: Medium
scope_note: Two independent structural gaps to close (enforce the remedy in warn mode OR make pause-work call the sanctioned state verb) plus deciding which; not a one-line fix, but bounded to gsd-core/references/execute-phase-context-guard.md + gsd-core/workflows/pause-work.md + call sites, no schema change
files:
  - gsd-core/references/execute-phase-context-guard.md:13 (POOR-tier `warn` mode — "Continue (user decides)"; no enforcement)
  - gsd-core/workflows/pause-work.md (the guard's prescribed remedy — writes .planning/HANDOFF.json + .continue-here.md ONLY, never touches .planning/STATE.md)
  - src/state.cts:1656-1658,2136 (cmdStateRecordSession — the actual, sanctioned, non-clobbering writer of frontmatter `stopped_at`)
  - src/state-command-router.cts:181 (routes `state record-session --stopped-at` to cmdStateRecordSession)
  - gsd-core/workflows/execute-plan.md:471-480 (the ONLY normal-case call site for `state.record-session --stopped-at`, fired at end-of-plan wrap-up — not reachable from a mid-plan context-pressure event)
---

## Problem

Reported by a peer session ("cnc", cross-session message, 2026-08-30), root-caused via
`grep -rn 'context exhaustion' ~/.claude/gsd-core/`: a phase's `.planning/STATE.md`
frontmatter `stopped_at` was found overwritten with the literal string
`context exhaustion at 100% (2026-08-28)` — the context guard's own POOR-tier warning
phrase with a percentage filled in — destroying a prior closure narrative. Root cause per
cnc: an execute-phase orchestrator hit the guard, was told to run `/gsd:pause-work`, and
instead hand-wrote a pause note directly into frontmatter.

Verified in this repo's source (not taken on the peer's word alone):

**1. The guard's remedy is unenforced prose in the default mode.**
`gsd-core/references/execute-phase-context-guard.md:13` — POOR tier (70%+), `warn` mode
(the documented default): `Emit: "🛑 Context pressure POOR... Run /gsd:pause-work..."
Continue (user decides).` Only `auto` mode invokes the remedy programmatically and halts;
`warn` is text with no binding effect on what the agent does next.

**2. Even when followed correctly, the prescribed remedy doesn't own the field that got
clobbered.** Read `gsd-core/workflows/pause-work.md` in full: it writes
`.planning/HANDOFF.json` and `.planning/{phases/XX-name,spikes/SPIKE-NNN,}/.continue-here.md`.
It contains **zero** references to `STATE.md`, `stopped_at`, or `state.record-session`.
The actual sanctioned, non-clobbering writer of frontmatter `stopped_at` is
`gsd_run query state.record-session --stopped-at ... --resume-file ...`
(`src/state.cts:1656-1658` via `src/state-command-router.cts:181`) — but the **only**
workflow call site for it (`gsd-core/workflows/execute-plan.md:471-480`) fires at normal
end-of-plan wrap-up (`--stopped-at "Completed {PHASE}-{PLAN}-PLAN.md"`), which a
context-exhausted agent mid-plan never reaches.

So an agent that hits POOR-tier pressure mid-plan and wants to record where it stopped
has **no sanctioned call available that does that** — `/gsd:pause-work` doesn't touch
`STATE.md`, and `state.record-session` is only invoked from a step the agent hasn't
reached yet. The gap between "guard tells you to do X" and "X doesn't write the field
that actually got corrupted" is what leaves hand-editing frontmatter as the only path
left, and hand-editing bypasses whatever clobber-protection `cmdStateRecordSession`
has (`src/state.cts:3405`'s own comment: "silently clobber a fresher frontmatter
stopped_at").

**3. The trigger itself is unreliable** (corroborating detail, not independently
verified further here): `execute-phase-context-guard.md:15` states outright "no
programmatic context-percentage API exists" — the guard fires on self-assessed
degradation signals, not a measured number. Per cnc, a live warning claimed 100% and was
manually corrected to 52%.

## Fix

Two independent structural options (pick one, or both):

1. **Enforce the remedy, not just prescribe it** — make `warn` mode (or a new tier) call
   `/gsd:pause-work` (or the correct state verb, see below) as an actual tool
   invocation rather than emitting text and continuing on the agent's discretion. Mirrors
   `auto` mode's existing halt-and-invoke behavior, just without skipping the wave.
2. **Fix pause-work.md to actually own `stopped_at`** — have it call
   `gsd_run query state.record-session --stopped-at "..." --resume-file "..."` as part of
   its `write_structured`/`commit` steps, using `cmdStateRecordSession`'s existing
   non-clobbering path, instead of leaving `STATE.md` untouched. This closes the gap even
   if enforcement (option 1) isn't done — at minimum, an agent that DOES correctly run
   `/gsd:pause-work` would then have a safe, sanctioned way to record `stopped_at` instead
   of improvising a direct frontmatter edit.

## Methodological note (carried from cnc's report, not independently re-verified here)

A competing theory — an unqualified `/tmp/STATE.before.md` from another repo overwriting
this one, then "restored" — fit the *shape* of the damage (prose-looking corruption with
the tool-written `progress:` block intact) but was ruled out on *content*: a foreign-file
swap deposits text from elsewhere, not an accurate first-person summary of the writer's
own state. Worth carrying as debugging guidance: a mechanism that explains the shape but
not the content is a lead, not a cause.

## Cross-references

- Reported by peer session `cnc` (cross-session message, 2026-08-30); also routed to
  `gsd-core-working` and `gsd-research`.
- Same session's earlier, separately-filed finding from cnc, verified and narrowed:
  `2026-08-30-init-phase-op-cannot-distinguish-archived-from-unplanned-phase.md` — cnc's
  follow-up message repeated this claim verbatim; already accurately captured, no new
  action needed there.
- Related memory pattern (peer's framing): `project_gate_correct_but_aimed_at_fixture`,
  `feedback_verify_the_artifact_not_the_exit_code`,
  `feedback_checks_that_read_where_truth_was_not_written`.
