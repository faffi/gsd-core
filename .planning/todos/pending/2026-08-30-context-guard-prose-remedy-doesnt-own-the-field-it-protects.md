---
created: 2026-08-30T00:00:00.000Z
corrected: 2026-08-31T00:00:00.000Z
title: "gsd-context-monitor.js auto-records CRITICAL-context state via state record-session, unconditionally overwriting STATE.md's Stopped At narrative"
area: hooks
severity: blocker
scope: Small
scope_note: The auto-record block is 20 lines in one file; the fix is delete-it-and-let-the-user-run-pause-work (already applied as a local patch elsewhere) or make it preserve/append instead of overwrite — either way a single-file, single-behavior change
files:
  - hooks/gsd-context-monitor.js:142-163 (the auto-record block — spawns `state record-session --stopped-at "context exhaustion at N% (date)"` unconditionally on first CRITICAL reading)
  - src/state.cts:1656-1658 (cmdStateRecordSession / stateReplaceField — a straight field replace, no merge or preserve-existing-content logic; not itself buggy, just not designed to be called with a disposable auto-generated value)
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

Alternative, if the "breadcrumb for `/gsd:resume-work`" behavior is worth keeping: make the
write non-destructive using a primitive that already exists in this codebase for exactly
this shape of problem. `src/state-document.cts:802` exports
`stateReplaceFieldIfTemplate(content, field, knownDefaults, newValue)` — it only overwrites
a field when its *current* value matches a known, handler-generated default, leaving any
richer/executor-authored content alone. `cmdStateRecordSession` (`src/state.cts:1665-1684`)
already uses exactly this primitive to protect **Resume File** on the line immediately
after `Stopped At` — but only in the "caller omitted `--resume-file`" branch; when the
caller passes an explicit value, `Resume File` is overwritten unconditionally too, the same
as `Stopped At` is today. So the precedent is real but not a literal drop-in: `Stopped At`
also has **no entry in `KNOWN_TEMPLATE_DEFAULTS`** (`src/state-document.cts:691-717`,
checked directly — only `Resume File`, `Status`, `Last Activity` have one) and the hook
always passes an *explicit* `--stopped-at` value, so protecting it means calling
`stateReplaceFieldIfTemplate` unconditionally against a new `KNOWN_TEMPLATE_DEFAULTS['Stopped At']`
list (e.g. `['None']` or whatever the template's initial value is), not gating on
omission the way `Resume File` does. Same primitive, small new table entry, one changed
call site — still smaller and more precedented than a bespoke solution, just not
byte-for-byte identical to the `Resume File` case.

No preference between delete-the-block and make-it-non-destructive stated here — flagged by
`gsd-core-working` (cross-session message, 2026-08-31) that a breadcrumb written at the
exact moment of context degradation may be the wrong thing to write unguarded regardless,
favoring deletion. Whoever implements this should decide.

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
