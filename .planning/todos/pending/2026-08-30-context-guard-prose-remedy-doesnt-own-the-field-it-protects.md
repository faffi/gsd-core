---
created: 2026-08-30T00:00:00.000Z
corrected: 2026-08-31T00:00:00.000Z
title: "gsd-context-monitor.js auto-records CRITICAL-context state via state record-session — which also runs with resync:true, a known bug (#3242 Bug A) that rebuilds progress.* from disk on every call"
area: hooks
severity: blocker
scope: Small
scope_note: Two independent, separately-fixable defects at the same call site — deleting/gating the hook's auto-record block is one small change, and passing {resync:false} to cmdStateRecordSession's readModifyWriteStateMd call (matching state.update's existing pattern) is a one-line fix for the broader progress-counter defect
files:
  - hooks/gsd-context-monitor.js:142-163 (the auto-record block — spawns `state record-session --stopped-at "context exhaustion at N% (date)"` unconditionally on first CRITICAL reading)
  - src/state.cts:1656-1658 (cmdStateRecordSession / stateReplaceField — a straight field replace, no merge or preserve-existing-content logic for `Stopped At` specifically)
  - src/state.cts:1640 (cmdStateRecordSession's `readModifyWriteStateMd` call — no options passed, so `resync` defaults to `true`, rebuilding the entire frontmatter including `progress.*` from disk on every call)
  - src/state.cts (`readModifyWriteStateMd`'s own JSDoc, directly above its definition — documents `resync:true`'s "trample manually-curated cross-milestone progress.* counters" failure as the already-numbered #3242 Bug A, and the `{resync:false}` fix `state.update` already applies)
---

## ⚠ CORRECTED 2026-08-31 — the original root cause below was wrong

Original filing (2026-08-30) reasoned from the *symptom* (STATE.md's `Stopped At` field
overwritten with the literal string `context exhaustion at N% (date)`) to a *plausible but
unverified* mechanism: that the context-pressure guard's prescribed remedy
(`/gsd:pause-work`) is prose-only and doesn't itself write `STATE.md`, so an agent under
pressure must have hand-edited the frontmatter directly. That reasoning was never checked
against the actual hook source — it inferred agent behavior instead of reading the code
that runs automatically.

**Reported by peer session `claude-71`** (cross-session message, 2026-08-31), with a full
writeup at their own `~/.claude/reference/gsd-context-monitor-state-md-overwrite.md`
(their local install, not this repo). **Verified directly in this repo's own source**,
not taken on their word: `hooks/gsd-context-monitor.js:142-163` —

```js
// On CRITICAL with active GSD project, auto-record session state as a
// breadcrumb for /gsd:resume-work (#1974). Fire-and-forget subprocess —
// doesn't block the hook or the agent. Fires ONCE per CRITICAL session,
// guarded by warnData.criticalRecorded to prevent repeated overwrites
// of the "crash moment" record on every debounce cycle.
if (isCritical && isGsdActive && !warnData.criticalRecorded) {
  try {
    const gsdTools = path.join(__dirname, '..', 'gsd-core', 'bin', 'gsd-tools.cjs');
    const safeUsedPct = Number(usedPct) || 0;
    const stoppedAt = `context exhaustion at ${safeUsedPct}% (${new Date().toISOString().split('T')[0]})`;
    spawn(
      process.execPath,
      [gsdTools, 'state', 'record-session', '--stopped-at', stoppedAt],
      { cwd, detached: true, stdio: 'ignore', windowsHide: true }
    ).unref();
    warnData.criticalRecorded = true;
    fs.writeFileSync(warnPath, JSON.stringify(warnData));
  } catch { /* non-critical — don't let state recording break the hook */ }
}
```

**No agent improvisation occurred, ever, in this incident class.** The hook itself —
deterministically, automatically, on the first CRITICAL context reading per session —
spawns exactly the sanctioned `state record-session --stopped-at` verb
(`src/state.cts:1656-1658`, `src/state-command-router.cts:181`) with a disposable,
auto-generated template string. `stateReplaceField` does a straight field replace with no
merge or preserve-existing-content logic, so whatever richer narrative was already in
`Stopped At` (e.g. a 1,601-byte phase-closure summary, per the originally reported
incident) is silently clobbered. This requires no hand-editing, no guard being ignored, and
no agent decision at all — it fires unconditionally, by design (the code comment says so
outright: "auto-record session state as a breadcrumb for `#1974`").

The earlier framing (guard remedy is prose, `pause-work.md` doesn't own `stopped_at`) is
**still factually true as independent observations** — verified directly, see the
Cross-references below — but it is not what caused this incident, and the fix aimed at it
(enforce the remedy, or make `pause-work.md` call `state.record-session`) would not have
prevented this bug, because this bug bypasses the remedy path entirely.

## Fix

Per `claude-71`'s report, this has already been resolved as a **local-only patch** (not
upstreamed) in their install: delete the auto-record block entirely — "a monitor must not
write project state; the CRITICAL message already tells the user to run `/gsd:pause-work`,
which records a real stopping point." That's the correct minimal fix for this repo's own
`hooks/gsd-context-monitor.js` too: remove lines 142-163, rely on the existing CRITICAL
advisory message (a few lines below, already present) to prompt the user/agent toward
`/gsd:pause-work` instead of writing anything automatically.

**RETRACTED 2026-08-31 — do not apply `stateReplaceFieldIfTemplate` to `Stopped At`.** An
earlier version of this section proposed gating `Stopped At` through
`stateReplaceFieldIfTemplate` (`src/state-document.cts:802`) the way `Resume File` is
gated, on the theory that the same "only overwrite a known template default" protection
would apply. `gsd-core-working` (cross-session message, 2026-08-31) caught the flaw and it
was verified directly: `Resume File`'s guard only fires in the branch where the caller
*omits* `--resume-file` (`src/state.cts:1670-1678` — "Caller explicitly passed a value —
always honour it" governs the explicit-value branch, unconditional `stateReplaceField`,
same as `Stopped At`). Applying the guard to `Stopped At` unconditionally — the only way to
protect it, since the hook always passes an explicit value — would silently no-op the four
**legitimate** callers (`execute-plan.md`, `discuss-phase-assumptions.md`,
`milestone-summary.md`, `ui-phase.md`) every time the existing value isn't already a
template default, i.e. every normal multi-plan session after the first stop is recorded.
That converts a real, intended overwrite into a silent no-op at exactly the moment a real
stop most needs recording. As `cnc` put it: the verb isn't the defect, the caller is — a
workflow passing `--stopped-at` *intends* to overwrite; that's the correct contract for
every caller except the hook. Guarding the verb degrades every correct caller to defend
against one incorrect one.

The two options that remain: **delete the auto-record block** (simplest; the existing
CRITICAL advisory message already tells the user to run `/gsd:pause-work`), or **make the
hook's own call opt into non-destructive behavior via a new flag** (e.g.
`--only-if-template`) that only the hook passes, leaving the four legitimate callers'
contract untouched by construction. `gsd-core-working` leans deletion — a breadcrumb
written at the exact moment of context degradation is the worst-timed write to leave
unguarded, and the CRITICAL message's own text already says GSD state is tracked
elsewhere, making the breadcrumb largely redundant. No implementation decision made here;
left to whoever picks this up.

## A second, more severe defect found while answering "does this also clobber progress
counters?" — confirmed 2026-08-31

`cnc` separately observed, in a live incident, that the same `state record-session` call
also changed `completed_phases` (4→1) and `percent` (50→13) — fields `cmdStateRecordSession`
never touches directly. `gsd-core-working` traced 180 lines of `cmdStateRecordSession`
looking for a progress-recompute call, found none, and flagged it as unresolved — the
right instinct, but the trace stopped one layer too early.

**Confirmed by reading the write path one level down, plus an empirical repro.**
`cmdStateRecordSession`'s write goes through `readModifyWriteStateMd(statePath, callback)`
(`src/state.cts:1640`, no options object passed) → `syncAndPreserveStateMd` →
`syncStateFrontmatter`. `readModifyWriteStateMd`'s own JSDoc (`src/state.cts`, directly
above its definition) states explicitly:

> `resync`: when true (**default**) rebuilds the **entire frontmatter from disk** after
> the transform. Pass `{ resync: false }` for body-only updates (e.g. `state.update` on a
> single field) that **must not trample manually-curated cross-milestone `progress.*`
> counters** in the frontmatter (**#3242 Bug A**).

`cmdStateRecordSession` calls `readModifyWriteStateMd` with **no options**, so `resync`
defaults to `true` — the exact behavior the docstring names as the cause of a
**pre-existing, already-numbered bug (#3242 Bug A)**. `state.update` already carries the
`{ resync: false }` fix for this; `cmdStateRecordSession` does not.

Reproduced directly (`env -u GSD_AGENTS_DIR node gsd-core/bin/gsd-tools.cjs state
record-session --stopped-at "..."` against a synthetic `.planning/STATE.md` seeded with a
`progress:` block): the `completed_phases`/`percent` block present before the call was gone
after it, and the frontmatter shape changed beyond the three session fields
(`gsd_state_version`, `status`, `last_updated` were rewritten from scratch). The fixture
lacked real `.planning/phases/` directories, so this specific repro shows the progress
block going to *absent* rather than reproducing cnc's exact *wrong-but-present* numbers
(4→1, 50→13) — that more precise numeric mismatch is consistent with a cross-milestone or
workstream scope where the disk-rescan and the manually-curated value disagree, which a
minimal single-directory fixture can't reconstruct. The mechanism, though, is confirmed,
not inferred: `resync: true` is in effect on every `state record-session` call, and its own
docstring already documents the exact failure class.

**This is a distinct, broader defect from the `Stopped At` overwrite above** — it affects
**every** caller of `state record-session`, not just the hook's auto-record, whenever the
project has manually-curated or cross-milestone progress counters that a plain disk rescan
wouldn't reproduce.

**Promoted to its own todo, 2026-08-31**, after `gsd-core-working` asked whether this is one
missed call site or several: **`2026-08-31-state-verbs-default-to-resync-true-dropping-progress-counters.md`**.
An empirical sweep of 9 `state.cts` verbs found 6 confirmed to clobber `progress.*` the same
way (`record-metric`, `add-decision`, `add-blocker`, `add-roadmap-evolution`,
`resolve-blocker`, plus `record-session` here) — a systemic gap (the fix policy is applied
at only 2 of ~14 call sites), not an isolated oversight. Full evidence and the fix
recommendation live in that todo; this section is kept for provenance of how it was found.

## Damage inventory (per claude-71, not independently re-verified in this repo)

`grep -rl 'context exhaustion at' --include=STATE.md ~/Documents/git/` reportedly hits 10
distinct repos on their machine. Not all warrant restoration — in several the terse value
is truthful (the session really did end from exhaustion); only cases where a richer,
pre-existing narrative was replaced (this repo's originally-reported incident pattern)
warrant fixing, per-repo, when next touched. Not checked against this repo's own
`.planning/STATE.md` history as part of this correction.

## Methodological note (unchanged from original filing, still accurate)

A competing theory — an unqualified `/tmp/STATE.before.md` from another repo overwriting
this one, then "restored" — fit the *shape* of the damage (prose-looking corruption with
the tool-written `progress:` block intact) but was ruled out on *content*: a foreign-file
swap deposits text from elsewhere, not an accurate first-person summary of the writer's own
state. Worth carrying as debugging guidance: a mechanism that explains the shape but not
the content is a lead, not a cause. (This todo's own history is now a second instance of
the same lesson, one level up: a mechanism — "agent hand-edited frontmatter" — that
explained the shape of the damage but, unlike the rejected theory above, was never checked
against the actual code before being filed.)

## Cross-references

- Reported by peer session `cnc` (cross-session message, 2026-08-30) — original incident
  report and the now-superseded root-cause hypothesis.
- **Root cause corrected by peer session `claude-71`** (cross-session message,
  2026-08-31); full writeup at their `~/.claude/reference/gsd-context-monitor-state-md-overwrite.md`
  (not in this repo).
- The independent observations this todo originally centered on — `warn` mode's remedy
  being unenforced prose, and `pause-work.md` never touching `STATE.md` — remain true and
  verified (`gsd-core/references/execute-phase-context-guard.md:13`,
  `gsd-core/workflows/pause-work.md`), but are a separate, lower-priority concern from this
  incident: they describe what happens if an agent *chooses* to hand-edit frontmatter under
  pressure, which — per this correction — is not what happened here or, likely, in most
  real instances of this symptom.
