---
created: 2026-08-22T02:20:00.000Z
title: gsd-context-monitor warns subagents with the parent session's context usage, not their own
area: hooks
resolves_phase: 6
severity: major
scope: Small
scope_note: The fix is a single guard clause, already implemented and verified in the live install — porting it into this repo's own hooks/gsd-context-monitor.js is the same minimal diff
files:
  - hooks/gsd-context-monitor.js:43-54 (session_id read, no agent_id check — reads the metrics file unconditionally)
  - "hooks/gsd-context-monitor.js:74 (metricsPath keyed only by sessionId: `claude-ctx-${sessionId}.json`)"
  - hooks/gsd-statusline.js:608-620 (bridge write — session/used_pct only, no agent scoping)
  - hooks/hooks.json (registers gsd-context-monitor.js on PostToolUse, SubagentStop, Stop, PreCompact)
  - ~/.claude/settings.json (hooks + statusLine config; confirms `subagentStatusLine` is absent/unset in this install)
---

## Problem

`gsd-context-monitor.js` reads `/tmp/claude-ctx-{session_id}.json` — a bridge file written
only by the top-level session's own `statusLine` render (`gsd-statusline.js`) — and injects
WARNING/CRITICAL "context almost full" messages into the agent's context when the bridge's
`used_pct` crosses 35%/25% remaining thresholds. It is registered on four hook events:
`PostToolUse`, `SubagentStop`, `Stop`, `PreCompact`.

The bridge file is keyed **only** by `session_id`. Per Claude Code's own hook docs
(code.claude.com/docs/en/hooks, "Common input fields", verified via context7
`/websites/code_claude`), `session_id` is **shared** between a session and every subagent
it spawns — only the optional `agent_id` field distinguishes a subagent-originated hook
event from the top-level session's own:

```json
// SubagentStop example payload from the docs
{
  "session_id": "abc123",   // ← same value the parent session uses
  "agent_id": "def456",     // ← the ONLY field that identifies the subagent
  "hook_event_name": "SubagentStop"
}
```

Because only one `statusLine` is ever rendered (the top-level terminal UI), the bridge file
structurally can only ever reflect the **parent** session's usage. But `gsd-context-monitor.js`
applies it unconditionally to every hook event carrying that `session_id` — including
`PostToolUse`/`SubagentStop` events fired *by a subagent*, which share the parent's
`session_id`. A fresh, low-usage subagent (or one of several concurrent forks — this
environment's own `Agent`/fork tooling routinely runs several in parallel) can get a false
CRITICAL/WARNING injection sourced from the *parent's* usage, misattributed as if it
describes its own. Symptom as reported: "responses are incorrectly claiming context is
almost full when it is NOT... it's literally firing for the wrong session."

## Why there's no data available to do this correctly today

Checked whether a per-subagent number exists anywhere to read instead of the parent's:

- `PostToolUse`/`SubagentStop` hook payload schemas (context7, same library) do **not**
  include `context_window` at all — only the separate `statusLine` command input does.
- Claude Code has a distinct, documented `subagentStatusLine` config hook
  (code.claude.com/docs/en/statusline) that *does* receive per-subagent "token count" on
  every refresh tick — the correct primitive for this.
- **This install has it unconfigured** — confirmed directly: `settings.json` has no
  `subagentStatusLine` key at all (`null` on lookup).

So today there is no source of truth for "this subagent's own context usage" anywhere on
disk. Any number `gsd-context-monitor.js` reports for a subagent-originated event is
necessarily the parent's, mislabeled.

## Fix applied (local only — not yet upstreamed)

Patched the installed hook (`~/.claude/hooks/gsd-context-monitor.js`, gsd 1.10.0) to skip
entirely when `data.agent_id` is present, since misattributing the parent's number is worse
than reporting nothing:

```js
const agentId = data.agent_id;
...
if (agentId) {
  process.exit(0);
}
```

Recorded in `~/.claude/scripts/gsd-local-patches-1.10.0.diff` (appended, `hooks/gsd-context-monitor.js`
section) per this fork's convention for `~/.claude`-tree edits that `/gsd-update` would
otherwise silently discard. Verified: diffed the installed file against this repo's `v1.10.0`
tag first to confirm zero pre-existing functional patch (only cosmetic `/gsd:x`→`/gsd-x`
renames from the fork's slash-command normalization) — this is a genuine upstream gap, not
something already touched by prior local patches. Smoke-tested the guard directly:
`echo '{"session_id":"...","agent_id":"..."}' | node gsd-context-monitor.js` exits 0 with no
bridge-file access.

## Fix options for upstream / this repo's own source tree

1. **Land the same guard clause here** — `hooks/gsd-context-monitor.js`, right after the
   existing `sessionId` validation block (~line 44-51 in `v1.10.0`). Minimal, matches what's
   now running locally. Trade-off: subagents get zero context-awareness rather than wrong
   context-awareness — acceptable, since subagents are short-lived and parent-monitored, and
   the parent's own `Stop`/`PostToolUse` events (no `agent_id`) are unaffected and keep
   working correctly.
2. **Full fix (larger scope, separate follow-up)** — wire `subagentStatusLine` to write a
   second bridge file keyed by `agent_id` (e.g. `claude-ctx-agent-{agent_id}.json`) using the
   real per-subagent token count Claude Code already provides via that hook, then have
   `gsd-context-monitor.js` prefer it when `agent_id` is present, falling back to option 1's
   skip only if that file doesn't exist yet. Gives subagents genuine, accurate warnings
   instead of silence. New capability, not required to close this defect.

## Cross-references

- No existing GitHub issue found matching this defect — searched
  `open-gsd/gsd-core` for "context monitor session", "context-monitor bridge session",
  "context warning wrong stale", "false positive context"; nearest hits were #3709 (warn
  sentinel surviving PreCompact — different failure direction, under-warning not
  over/mis-warning) and #2451 (buffer-normalization inflation, already fixed upstream by
  `0ea443cb`, confirmed present in the `v1.10.0` tag's source — not the live cause here).
- Related, same defect class (unscoped `/tmp` state, no per-consumer isolation): closed
  issue #2358, "review.md: /tmp/gsd-review-*-{phase} temp paths are not project-scoped,
  causing cross-project prompt collisions."
- Also observed while investigating (not this defect, noted for awareness): the shared
  `$TMPDIR` had 100+ leftover `claude-ctx-*.json`/`-warned.json` files at time of
  investigation, including one from a session 2+ days old and several with synthetic IDs
  clearly written by gsd-core's own test suite (`test-1194-*`, `probe-*`, `sess-305-*`) —
  nothing in this mechanism ever cleans the bridge/sentinel files up. Not filed separately;
  flagging here in case it's worth its own todo later.
