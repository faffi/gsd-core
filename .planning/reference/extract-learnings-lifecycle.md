# Extract Learnings Lifecycle

> **Generated:** 2026-08-29T00:00:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** `gsd-core/workflows/extract-learnings.md`, `gsd-core/bin/lib/learnings.cjs`, `agents/gsd-planner.md`, `docs/features/extract-learnings.md`

<purpose>
Reference documentation for GSD's extract-learnings system — how structured knowledge is extracted from phase artifacts, stored globally, and injected into planning contexts.
</purpose>

## Overview

The extract-learnings system captures institutional knowledge from completed phases and makes it available to future planning sessions. It consists of:

1. **Phase-scoped extraction** (`/gsd-extract-learnings`) — reads phase artifacts and produces `LEARNINGS.md`
2. **Global knowledge store** (`~/.gsd/knowledge/`) — cross-project JSON store for learnings
3. **Context injection** — planner pulls relevant learnings into planning context

## Command

```bash
/gsd-extract-learnings <phase-number>
```

**Purpose:** Extract structured knowledge from completed phase artifacts into four categories: decisions, lessons, patterns, and surprises.

## Input Artifacts

| Artifact | Required | Purpose |
|----------|----------|---------|
| `*PLAN.md` | **Yes** | Decisions, trade-offs, technology choices |
| `*SUMMARY.md` | **Yes** | Lessons from execution, unexpected complexity |
| `*VERIFICATION.md` | No | Testing patterns, verification findings |
| `*UAT.md` | No | User acceptance feedback, discovered gaps |
| `STATE.md` | No | Project-level decisions and blockers |

**Exit condition:** If PLAN.md or SUMMARY.md are missing, the workflow exits with error: `"Required artifacts missing. PLAN.md and SUMMARY.md are required for learning extraction."`

## Output Artifact

**Path:** `{phase_dir}/{PADDED_PHASE}-LEARNINGS.md`

Example: `.planning/phases/3.0-implementation/03-LEARNINGS.md`

### Frontmatter Schema

```yaml
---
phase: 3
phase_name: "Implementation"
project: "my-app"
generated: "2026-08-29T00:00:00Z"
counts:
  decisions: 4
  lessons: 2
  patterns: 3
  surprises: 1
missing_artifacts:
  - "VERIFICATION.md"
---
```

### Body Structure

```markdown
# Phase 3 Learnings: Implementation

## Decisions

### Use SQLite over Postgres
Zero-ops for single-node deployments.

**Rationale:** Simplified deployment, adequate for MVP scale.
**Source:** 03-01-PLAN.md

---

## Lessons

### Test data fixtures drift from production schemas
Schemas evolved but fixtures weren't updated, causing validation failures.

**Context:** Integration test suite spun up with stale fixtures.
**Source:** 03-SUMMARY.md

---

## Patterns

### Repository pattern with dependency injection
Interface-based repositories injected at runtime enable test doubles.

**When to use:** Any service layer with external dependencies.
**Source:** 03-VERIFICATION.md

---

## Surprises

### npm dedupe changed lockfile hash
Expected no-op but lockfile changed after `npm dedupe`.

**Impact:** CI cache invalidated, had to re-verify all packages.
**Source:** 03-SUMMARY.md
```

## Extraction Categories

### 1. Decisions

Technical and architectural choices made during the phase.

**Sources:** PLAN.md, STATE.md

**Each entry includes:**
- What was decided
- Why (rationale)
- Source attribution

### 2. Lessons

Things learned during execution that were not known beforehand.

**Sources:** SUMMARY.md, VERIFICATION.md, UAT.md

**Each entry includes:**
- What was learned
- Context for the lesson
- Source attribution

### 3. Patterns

Reusable approaches, techniques, or structures discovered.

**Sources:** SUMMARY.md, VERIFICATION.md, PLAN.md

**Each entry includes:**
- Pattern description
- When to use it
- Source attribution

### 4. Surprises

Unexpected findings, behaviors, or outcomes.

**Sources:** SUMMARY.md, VERIFICATION.md

**Each entry includes:**
- What was surprising
- Impact of the surprise
- Source attribution

## Global Learnings Store

### Storage Location

```
~/.gsd/knowledge/
├── lx7k9m2a-3f8b.json
├── mx9p3q7d-1a2c.json
└── ...
```

Each learning is stored as an individual JSON file.

### Record Schema

```json
{
  "id": "lx7k9m2a-3f8b",
  "source_project": "gsd-core",
  "date": "2026-08-29T00:00:00.000Z",
  "context": "Use SQLite over Postgres",
  "learning": "Zero-ops for single-node deployments.",
  "tags": ["sqlite", "postgres", "deployment"],
  "content_hash": "a1b2c3d4..."
}
```

### Deduplication

Content-hash deduplication via SHA-256 of `{learning}\n{source_project}`.

If the same learning is written twice from the same project, the second write returns the existing ID with `created: false`.

## Configuration

### Config Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `features.global_learnings` | boolean | `false` | Enable automatic extraction and copy on phase completion |
| `learnings.max_inject` | number | `10` | Maximum learnings to inject into agent prompts |

### Enabling Global Learnings

```bash
gsd-tools config-set features.global_learnings true
```

Or in `.planning/config.json`:

```json
{
  "features": {
    "global_learnings": true
  }
}
```

## Workflow Integration

### Manual Extraction

User invokes directly:

```bash
/gsd-extract-learnings 3
```

Produces `{phase_dir}/03-LEARNINGS.md`. Does NOT copy to global store unless followed by:

```bash
gsd-tools learnings copy
```

### Automatic Extraction (Gated)

When `features.global_learnings: true`, the `execute-phase` workflow runs extraction automatically after phase completion.

**Location in execute-phase.md:** Step `auto_copy_learnings` (line 1443)

**Sequence:**
1. Check config: `GL_ENABLED=$(gsd_run query config-get features.global_learnings --raw)`
2. If disabled: skip entire step
3. If enabled:
   - Run `extract-learnings` workflow for completed phase
   - Run `gsd_run query learnings.copy` to copy to global store
4. Extraction/copy failures do NOT block phase completion

## CLI Commands

### List All Learnings

```bash
gsd-tools learnings list
```

Returns:
```json
{
  "learnings": [
    {
      "id": "lx7k9m2a-3f8b",
      "source_project": "gsd-core",
      "context": "Use SQLite over Postgres",
      "learning": "Zero-ops for single-node deployments.",
      "tags": ["sqlite", "postgres"],
      "date": "2026-08-29T00:00:00.000Z"
    }
  ],
  "count": 1
}
```

### Query by Tag

```bash
gsd-tools learnings query --tag auth
```

Returns learnings whose `tags` array includes `"auth"`.

### Copy to Global Store

```bash
gsd-tools learnings copy
```

Reads from `.planning/` (phase-scoped or project-root `LEARNINGS.md`) and writes to `~/.gsd/knowledge/`.

**Source resolution order:**
1. Most recent phase-scoped `*LEARNINGS.md` (by mtime)
2. Project-root `LEARNINGS.md` (fallback)

### Prune Old Learnings

```bash
gsd-tools learnings prune --older-than 90d
```

Removes learnings older than 90 days.

### Delete by ID

```bash
gsd-tools learnings delete lx7k9m2a-3f8b
```

## Context Injection

### When Injected

During `/gsd-plan-phase`, the planner injects relevant global learnings into planning context.

**Location in gsd-planner.md:** Step `inject_global_learnings` (line 691)

### How Injected

1. Check `features.global_learnings` config
2. If enabled: read tags from PLAN.md frontmatter
3. For each tag: `gsd_run query learnings.query --tag <tag> --limit 5`
4. Prefix matches with `[Prior learning from <project>]`
5. Project-local decisions take precedence over injected learnings

**Format in context:**
```
[Prior learning from gsd-core] Use SQLite over Postgres — Zero-ops for single-node deployments.
```

### Injection Limits

Controlled by `learnings.max_inject` config (default: 10).

The planner can limit results per query via `--limit` flag, and the total injected is bounded by `max_inject`.

## capture_thought Integration (Optional)

`capture_thought` is an **optional convention** for users who run a memory/knowledge-base MCP server.

If an MCP server in the session exposes a tool named `capture_thought`, each extracted learning is routed through it:

```javascript
capture_thought({
  category: "decision" | "lesson" | "pattern" | "surprise",
  phase: PHASE_NUMBER,
  content: LEARNING_TEXT,
  source: ARTIFACT_NAME
})
```

**If not available:** Step is skipped silently. `LEARNINGS.md` is always the primary output.

## Estimate Calibration

After extraction, the workflow rebuilds estimate-vs-actual calibration:

```bash
gsd_run query estimate-calibrate
```

Pairs each phase's PLAN `estimate` with its SUMMARY `actuals` and writes `.planning/estimation-calibration.json`. The planner reads this on the next `/gsd-plan-phase`.

## Failure Modes

### Missing Required Artifacts

**Symptom:** Exit with error, no `LEARNINGS.md` written.

**Recovery:** Ensure PLAN.md and SUMMARY.md exist for the phase.

### Copy No-Ops

**Symptom:** `learnings copy` returns `{ created: 0, skipped: N }`.

**Causes:**
- No phase-scoped LEARNINGS.md exists
- All entries are duplicates (same content_hash from same project)

### Stale Global Store

**Symptom:** Old learnings pollute context.

**Recovery:** Run `gsd-tools learnings prune --older-than 90d`.

## Implementation

### Core Library

**Source:** `gsd-core/bin/lib/learnings.cjs`

**Exports:**
- `learningsWrite(entry, opts)` — write a learning with dedup
- `learningsRead(id, opts)` — read by ID
- `learningsList(opts)` — list all, sorted by date desc
- `learningsQuery({ tag }, opts)` — filter by tag
- `learningsDelete(id, opts)` — remove by ID
- `learningsCopyFromProject(planningDir, opts)` — copy from LEARNINGS.md to store
- `learningsPrune(olderThan, opts)` — remove old entries

### CLI Router

**Source:** `gsd-core/bin/gsd-tools.cjs:2738-2761`

**Subcommands:** `list`, `query`, `copy`, `prune`, `delete`

### Workflow Definition

**Source:** `gsd-core/workflows/extract-learnings.md`

**Steps:**
1. `initialize` — parse args, load project state
2. `collect_artifacts` — read required and optional artifacts
3. `extract-learnings` — analyze and categorize
4. `capture_thought_integration` — optional MCP routing
5. `write_learnings` — output LEARNINGS.md
6. `calibrate_estimates` — rebuild estimation calibration
7. `update_state` — update STATE.md activity
8. `report` — summary output

## References

- Workflow: `gsd-core/workflows/extract-learnings.md`
- Library: `gsd-core/bin/lib/learnings.cjs`
- Planner injection: `agents/gsd-planner.md:691-693`
- Feature docs: `docs/features/extract-learnings.md`
- Tests: `tests/learnings.test.cjs`
- Config schema: `gsd-core/bin/shared/config-schema.manifest.json`
