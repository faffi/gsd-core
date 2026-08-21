---
description: "Lifecycle and workflow of GSD thread records"
last_verified: 2026-08-20
---

# Thread Lifecycle

## Purpose

Threads are **persistent context records for cross-session work** that:
- Exist independently of phases and the roadmap
- Capture multi-step efforts with internal ordering constraints
- Span sessions without requiring a full handoff or pause
- Are lighter weight than `/gsd-pause-work`

Threads are NOT phase-scoped. They sit alongside the roadmap, not on it.

## File Location

```
.planning/threads/<slug>.md
```

The slug is sanitized to prevent path traversal (max 60 chars, `[a-z0-9-]` only, `..` and `/` rejected).

## Frontmatter Schema

```yaml
---
slug: <sanitized-slug>
title: "Human-readable title"
status: <open|in_progress|resolved>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---
```

Required fields: `slug`, `title`, `status`, `created`, `updated`.

## Status Values

| Status | Meaning |
|--------|---------|
| `open` | New or unclaimed thread |
| `in_progress` | Actively being worked |
| `resolved` | Terminal state — thread closed |

**Status transitions:**
- `open` → `in_progress` (when work begins)
- `in_progress` → `resolved` (terminal)
- `open` → `resolved` (terminal — work completed without explicit in_progress claim)

There is no automatic status update. All transitions require explicit `--status` flag or manual edit.

## Body Structure

Threads follow a consistent section pattern:

```markdown
# Thread: <title>

## Goal

Concise description of what this thread achieves. Often includes:
- Why this is a thread (vs. todo or phase work)
- Scope boundaries (what's in/out)
- Operator-ownership markers if applicable

## Context

Background, current state, prior work. May include:
- Evidence summaries
- Decision history
- Cross-references to phases/todos/seeds

## References

Bulleted list of related files, MRs, commits, external URLs.

## Next Steps

Ordered or unordered task list. Checkboxes (`[ ]`, `[x]`) track completion.
May be grouped by:
- Agent work (no authorization needed)
- Operator authorization required
- Ordered pairs (5a before 5b is load-bearing)
```

## Workflow Operations

### CREATE

```
/gsd-thread --title "Descriptive title"
```

Creates a new thread with:
- Sanitized slug derived from title
- `status: open`
- `created` and `updated` set to today

### RESUME

```
/gsd-thread <slug>
```

Lists open threads and allows selection to continue work. Sets `status: in_progress`.

### LIST

```
/gsd-thread --list
```

Shows all threads regardless of status.

### LIST-OPEN

```
/gsd-thread --list-open
```

Shows only threads with `status: open` or `in_progress`.

### LIST-RESOLVED

```
/gsd-thread --list-resolved
```

Shows only threads with `status: resolved`.

### CLOSE

```
/gsd-thread --close <slug>
```

Sets `status: resolved` and updates `updated` date. Thread file remains in `.planning/threads/`.

### STATUS

```
/gsd-thread --status <slug>
```

Returns current thread status without opening.

## Thread vs. TODO vs. SEED

| Aspect | Thread | TODO | SEED |
|--------|--------|------|------|
| Purpose | Cross-session context | Actionable task | Forward-looking idea |
| Scope | Independent of roadmap | Independent | Independent |
| Lifecycle | Manual open/close | Directory move | Frontmatter status |
| Ordering | Explicit in Next Steps | Implicit | None |
| When to use | Multi-step effort with ordering constraints | Single actionable item | Conditional future work |

**When to choose thread over TODO:**
- Internal ordering matters (5a before 5b is load-bearing)
- Work spans multiple sessions
- Context is too large for a single TODO
- No active phase workflow will carry it

**When to choose thread over SEED:**
- Work is actionable now, not conditional
- No trigger-based surfacing needed

**When to choose thread over `/gsd-pause-work`:**
- Lighter weight suffices
- No need for full handoff artifact
- Work will be picked up soon

## Example Threads

### Active: Phase 76 validation closure

```yaml
---
slug: phase-76-validation-closure-the-7-remaining-rows
title: Phase 76 validation closure — the 7 remaining rows
status: open
created: 2026-08-20
updated: 2026-08-20
---
```

Key characteristics:
- **Why a thread:** seven items with ordering constraints, not seven independent TODOs
- **Goal:** clear closure verdict
- **Next Steps:** grouped by authorization requirement, with ordering noted
- **Cross-references:** to validation file, action plan, MRs

### Active: Hook false-positive investigation

```yaml
---
slug: block-dirty-tree-ops-false-positives-on-git-literals-in-text
title: "block-dirty-tree-ops.js blocks git-command literals appearing in TEXT, not as commands"
status: open
created: 2026-08-19
updated: 2026-08-19
---
```

Key characteristics:
- **Why a thread:** design decision with security implications, not a simple fix
- **Goal:** decide approach without weakening security guard
- **Context:** root cause, impact, workaround in use
- **Next Steps:** investigation → decision → fix

## Terminal State

A thread reaches terminal state when `status: resolved`. The file remains in `.planning/threads/` as historical record. Unlike TODOs (which move to `done/`), threads stay in place.

To close a thread:
1. Confirm all Next Steps are complete or explicitly delegated
2. Run `/gsd-thread --close <slug>` or manually update frontmatter
3. Update `updated` date

**Thread files are never deleted.** They serve as context for future work on related topics.

## Security Notes

Slug sanitization (per thread.md workflow):
- Maximum 60 characters
- Lowercase alphanumeric and hyphens only: `[a-z0-9-]`
- Explicitly reject `..` and `/` to prevent path traversal

This prevents:
- Directory escape (`../../../etc/passwd`)
- Nested paths that break assumptions
- Unvalidated file writes

## Relationship to Other GSD Workflows

| Workflow | Relationship |
|----------|--------------|
| `/gsd-pause-work` | Heavier; pauses active work and creates handoff |
| `/gsd-execute-phase` | Phase-scoped; threads are phase-independent |
| `/gsd-capture --seed` | Captures ideas, not active work |
| `/gsd-thread` | Lightweight cross-session context |

Threads may be **referenced by** phases, handoffs, or other threads, but they are not subordinate to any of them.
