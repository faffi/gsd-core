# Intel System Lifecycle

> **Generated:** 2026-08-21T23:25:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** `src/intel.cts`, `gsd-core/bin/lib/intel.cjs`, `gsd-core/bin/lib/intel-command-router.cjs`, `agents/gsd-intel-updater.md`

<purpose>
Reference documentation for GSD's queryable codebase intelligence system — how it's
configured, populated, updated, and consumed by other GSD features.
</purpose>

## Overview

The intel system stores structured, queryable intelligence about a project's codebase
in `.planning/intel/`. It provides a JSON-based knowledge store that other GSD features
can query instead of doing expensive codebase exploration reads.

**Key capability gating:** Intel requires explicit opt-in via `intel.enabled: true` in
`.planning/config.json`. All intel operations gate on the tri-state capability resolver
(`isCapabilityActive('intel', cwd)`), which checks installed + surfaced + enabled.

## 5 Core JSON Files

All files live in `.planning/intel/` and share a common structure with `_meta` metadata:

| File | Purpose | Token Budget |
|------|---------|--------------|
| `stack.json` | Tech stack: languages, frameworks, tools, build system | ≤500 tokens (800 hard limit) |
| `file-roles.json` | File graph: exports, imports, types for key source files | ≤2000 tokens (3000 hard limit) |
| `api-map.json` | API surfaces: endpoints, methods, parameters | ≤1500 tokens (2500 hard limit) |
| `dependency-graph.json` | Dependency chains: versions, types, used-by relationships | ≤1000 tokens (1500 hard limit) |
| `arch-decisions.json` | Architecture summary: patterns, data flows, component responsibilities | ≤1500 tokens (2000 hard limit) |

### Common Schema Elements

All JSON files include:

```json
{
  "_meta": {
    "updated_at": "2026-08-20T12:00:00Z",
    "version": 1
  },
  "entries": { /* file-specific structure */ }
}
```

The `_meta.updated_at` timestamp enables staleness detection (24-hour threshold).

### File-Specific Schemas

#### stack.json

```json
{
  "_meta": { "updated_at": "ISO-8601", "version": 1 },
  "languages": ["TypeScript", "JavaScript"],
  "frameworks": ["Express", "React"],
  "tools": ["ESLint", "Jest", "Docker"],
  "build_system": "npm scripts",
  "test_framework": "Jest",
  "package_manager": "npm",
  "content_formats": ["Markdown (skills, agents, commands)", "YAML (frontmatter config)"],
  "state_management": ["OpenTofu", "Terraform"]
}
```

#### file-roles.json

```json
{
  "_meta": { "updated_at": "ISO-8601", "version": 1 },
  "entries": {
    "src/index.ts": {
      "exports": ["main", "configLoad"],
      "imports": ["./config", "express"],
      "type": "entry-point"
    }
  }
}
```

**Critical constraint:** `exports` must be actual symbol names extracted from
`module.exports` or `export` statements — NEVER descriptions. Use
`gsd-tools intel extract-exports <file>` for accurate extraction.

Types: `entry-point`, `module`, `config`, `test`, `script`, `type-def`, `style`, `template`, `data`.

#### api-map.json

```json
{
  "_meta": { "updated_at": "ISO-8601", "version": 1 },
  "entries": {
    "GET /api/users": {
      "method": "GET",
      "path": "/api/users",
      "params": ["page", "limit"],
      "file": "src/routes/users.ts",
      "description": "List all users with pagination"
    }
  }
}
```

#### dependency-graph.json

```json
{
  "_meta": { "updated_at": "ISO-8601", "version": 1 },
  "entries": {
    "express": {
      "version": "^4.18.0",
      "type": "production",
      "used_by": ["src/server.ts", "src/routes/"],
      "invocation": "npm start"
    }
  }
}
```

Types: `production`, `development`, `peer`, `optional`.

`invocation` indicates how the dependency is used: npm script command (e.g. `npm test`),
`require` for direct imports, or `implicit` for framework dependencies.

#### arch-decisions.json

```json
{
  "_meta": { "updated_at": "ISO-8601", "version": 1 },
  "entries": {
    "overview": {
      "pattern": "Layered architecture",
      "description": "Separation of concerns between routes, services, and data layers"
    },
    "data-flow": {
      "flow": "routes → services → repositories → database",
      "description": "Unidirectional data flow with clear boundaries"
    },
    "component:Router": {
      "path": "src/routes/",
      "responsibility": "HTTP endpoint definitions and request validation"
    }
  }
}
```

**Note:** arch-decisions.json is JSON, not markdown. Keys and string values are what
`intel query <term>` searches.

## Setup and Configuration

### Configuration Path

Config field: `intel.enabled` (default: `false`)

**Enable via CLI:**

```bash
gsd-tools config-set intel.enabled true
```

**Enable via `/gsd-settings` workflow:**

Interactive configuration via `/gsd-settings` command.

**Enable manually** by editing `.planning/config.json`:

```json
{
  "intel": {
    "enabled": true
  }
}
```

The settings workflow presents the question in the "Features" section:

```
Enable Intel? (queryable codebase intelligence via /gsd-map-codebase --query —
builds a JSON index in .planning/intel/)

  • No (Recommended) — Skip intel indexing when codebase is small or queries not needed
  • Yes — Enable /gsd-map-codebase --query commands
```

### Initial Population

Once enabled, populate intel via:

```bash
/gsd-map-codebase --query
```

This spawns the `gsd-intel-updater` agent which:
1. Orients by globbing project structure indicators
2. Detects stack (reads package.json, configs, build files)
3. Builds file graph (glob sources, read key files for imports/exports)
4. Extracts API surfaces (greps for route definitions)
5. Builds dependency graph (reads package.json/requirements.txt)
6. Synthesizes architecture patterns
7. Validates all files via `gsd-tools intel validate`
8. Writes snapshot to `.last-refresh.json`

### Capability Gating

All intel operations are gated by `isCapabilityActive('intel', cwd)`, which checks:

1. **Installed:** GSD is installed in the project
2. **Surfaced:** GSD surfaces are active for the current runtime
3. **Enabled:** `intel.enabled: true` in config.json

If any check fails, operations return a disabled response:

```json
{
  "disabled": true,
  "message": "Intel system disabled. Set intel.enabled=true in config.json to activate."
}
```

## Update Lifecycle

### Staleness Detection

Each intel file carries `_meta.updated_at`. A file is stale if older than 24 hours:

```javascript
const STALE_MS = 24 * 60 * 60 * 1000; // 24 hours
const age = now - new Date(updatedAt).getTime();
const stale = age > STALE_MS;
```

The `gsd-tools intel status` command reports staleness:

```bash
gsd-tools intel status
```

Output:

```json
{
  "files": {
    "stack.json": { "exists": true, "updated_at": "2026-08-20T10:00:00Z", "stale": false },
    "file-roles.json": { "exists": true, "updated_at": "2026-08-19T08:00:00Z", "stale": true }
  },
  "overall_stale": true
}
```

### Update Triggers

**On-demand (full refresh):**

```bash
/gsd-map-codebase --query
```

Spawns `gsd-intel-updater` agent to rebuild all 5 files.

**On-demand (CLI):**

```bash
gsd-tools intel update
```

Returns action directive:

```json
{
  "action": "spawn_agent",
  "message": "Run gsd-tools intel update or spawn gsd-intel-updater agent for full refresh"
}
```

**Partial updates:**

```bash
/gsd-map-codebase --query --files src/index.ts,src/config.ts
```

Only updates entries referencing the specified paths. Preserves existing entries
unrelated to those paths. Does NOT rewrite stack.json or arch-decisions.json
(these need full context).

### Change Tracking

The `.last-refresh.json` file stores SHA-256 hashes of all intel files:

```json
{
  "hashes": {
    "stack.json": "abc123...",
    "file-roles.json": "def456..."
  },
  "timestamp": "2026-08-20T12:00:00Z",
  "version": 1
}
```

The `gsd-tools intel diff` command compares current hashes against the snapshot:

```bash
gsd-tools intel diff
```

Output:

```json
{
  "changed": ["file-roles.json"],
  "added": [],
  "removed": []
}
```

If no baseline exists:

```json
{
  "no_baseline": true
}
```

## CLI Subcommands

All subcommands route through `gsd-tools intel <subcommand>`:

| Subcommand | Purpose | Example |
|------------|---------|---------|
| `query <term>` | Search all intel files for term | `gsd-tools intel query router` |
| `status` | Report staleness of each file | `gsd-tools intel status` |
| `diff` | Show changes since last refresh | `gsd-tools intel diff` |
| `snapshot` | Write `.last-refresh.json` | `gsd-tools intel snapshot` |
| `patch-meta <file>` | Update `_meta.updated_at` on a file | `gsd-tools intel patch-meta .planning/intel/stack.json` |
| `validate` | Check correctness and freshness | `gsd-tools intel validate` |
| `extract-exports <file>` | Extract exports from JS/TS file | `gsd-tools intel extract-exports src/index.ts` |
| `update` | Trigger intel update (returns directive) | `gsd-tools intel update` |
| `api-surface` | Generate API-SURFACE.md from api-map.json | `gsd-tools intel api-surface` |

### Validation Rules

`gsd-tools intel validate` checks:

1. **Existence:** All 5 files present
2. **Parseable JSON:** Valid JSON structure
3. **Metadata:** `_meta.updated_at` present and recent (<24h)
4. **File graph exports:** No descriptions in exports (no spaces in symbol names)
5. **File graph paths:** Sample paths exist on disk (first 5 entries)
6. **Dependency fields:** Missing `version`, `type`, `used_by` flagged

Output:

```json
{
  "valid": false,
  "errors": ["file-roles.json: file does not exist"],
  "warnings": [
    "stack.json: _meta.updated_at is 26 hours old (>24 hr)",
    "file-roles.json: \"src/index.ts\" export \"main function\" looks like a description (contains space)"
  ]
}
```

### API-SURFACE.md Generation

The `api-surface` subcommand renders `api-map.json` as human-readable markdown:

```bash
gsd-tools intel api-surface
```

Writes `.planning/intel/API-SURFACE.md`:

```markdown
# API Surface

> Generated from `.planning/intel/api-map.json`. Do not edit by hand.

## `GET /api/users`

- **method:** GET
- **path:** /api/users
- **params:** page, limit
- **file:** src/routes/users.ts
- **description:** List all users with pagination
```

**Staleness banner:** If api-map.json is stale, includes:

```markdown
> **Warning:** api-map.json is stale (>24 hours old). Data below may be out of date.
```

**Incomplete banner:** If api-map.json has no entries:

```markdown
> **Incomplete:** api-map.json has no entries (intel extraction is regex/JS-only or not yet populated).
> Treat absence here as "unknown", not "does not exist".
```

## Integration Seams

### Source Grounding Authority

Intel integrates with GSD's plan review system as one of five source grounding authorities:

Config path: `plan_review.source_grounding_authority`

Allowed values: `grep`, `intel`, `treesitter`, `lsp`, `scip`

When set to `intel`, the plan review's drift guard queries intel files instead of
grepping source:

```json
{
  "plan_review": {
    "source_grounding": true,
    "source_grounding_authority": "intel"
  }
}
```

**Use case:** When intel is populated and fresh, querying the JSON store is faster
than grepping the codebase and avoids false negatives from grep patterns.

### Agent Spawning

The `gsd-intel-updater` agent is defined in `agents/gsd-intel-updater.md`:

- **Tools:** Read, Write, Bash, Glob, Grep
- **Color:** cyan
- **Effort:** low

Spawned by `/gsd-map-codebase --query` command. Follows a 7-step execution flow:

1. Orientation (glob project indicators)
2. Stack detection (read configs)
3. File graph (glob sources, read imports/exports)
4. API surface (grep route definitions)
5. Dependencies (read package files)
6. Architecture (synthesize patterns)
7. Self-check (`gsd-tools intel validate`) + snapshot

### Capability System

Intel uses the shared GSD capability pattern:

```javascript
// All public functions gate on capability activation
function intelQuery(term, planningDir) {
  if (!isIntelCapabilityActive(planningDir))
    return disabledResponse();
  // ... query logic
}
```

The capability resolver (`isCapabilityActive`) is shared across GSD features:
- Installed check (GSD present in project)
- Surfaced check (runtime surfaces active)
- Config gate (`intel.enabled: true`)

### Map-Codebase Trigger

The `/gsd-map-codebase` skill has two modes:

1. **Default mode:** Spawns mapper agents, writes to `.planning/codebase/`
2. **`--query` mode:** Spawns `gsd-intel-updater`, writes to `.planning/intel/`

The two directories serve different purposes:

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| `.planning/codebase/` | Mapper agent outputs (prose summaries, diagrams) | Ad-hoc, per-mapper-run |
| `.planning/intel/` | Structured JSON intelligence | Persistent, queryable, staleness-tracked |

## Comparison with Graphify

GSD has two knowledge systems with different purposes:

| System | Format | Purpose | Query Method |
|--------|--------|---------|--------------|
| Intel | JSON files | Structured, curated intelligence | `gsd-tools intel query <term>` |
| Graphify | Graph corpus | Raw entity relationships | Graph queries via `.planning/graphify/` |

**Intel advantages:**
- Structured, validated schemas
- Staleness detection
- Token budgets enforced
- Queryable by CLI

**Graphify advantages:**
- Captures relationships intel doesn't model
- Visual exploration (network graphs)
- Pattern detection across large codebases

Both are opt-in features (config gates: `intel.enabled`, `graphify.enabled`).

## Execution Flow (Agent Perspective)

When `gsd-intel-updater` runs:

1. **Config gate:** Already confirmed by `/gsd-map-codebase --query` before spawn
2. **Orientation:** Glob `**/package.json`, `**/tsconfig.json`, etc.
3. **Stack detection:** Read configs, write `stack.json`, patch `_meta`
4. **File graph:** Glob sources, read key files, write `file-roles.json`, patch `_meta`
5. **API surface:** Grep routes, write `api-map.json`, patch `_meta`
6. **Dependencies:** Read package files, write `dependency-graph.json`, patch `_meta`
7. **Architecture:** Synthesize patterns, write `arch-decisions.json`, patch `_meta`
8. **Self-check:** Run `gsd-tools intel validate`, fix errors if any
9. **Snapshot:** Run `gsd-tools intel snapshot` to write `.last-refresh.json`

**Context budget tiers:**

| Budget Used | Tier | Behavior |
|-------------|------|----------|
| 0-30% | PEAK | Explore freely, read broadly |
| 30-50% | GOOD | Be selective with reads |
| 50-70% | DEGRADING | Write incrementally, skip non-essential |
| 70%+ | POOR | Finish current file and return immediately |

**Priority rule:** For large codebases, include the most important 50-100 source files
in file-roles.json rather than attempting exhaustive listing.

## Failure Modes and Recovery

### Missing Files

If an intel file is missing: `gsd-tools intel status` reports `exists: false`, `stale: true`.

**Recovery:** Re-run `/gsd-map-codebase --query`.

### Corruption

If JSON is malformed: `gsd-tools intel validate` reports `invalid JSON`.

**Recovery:** Delete the corrupted file, re-run `/gsd-map-codebase --query`.

### Stale Data

If `_meta.updated_at` >24 hours: `gsd-tools intel validate` warns about staleness.

**Recovery:** Re-run `gsd-tools intel status` to check staleness, then
`/gsd-map-codebase --query` to refresh.

### Missing Exports

If `file-roles.json` has descriptions instead of symbols (e.g., `"main function"`):

```bash
gsd-tools intel extract-exports src/index.ts
```

Returns:

```json
{
  "file": "src/index.ts",
  "exports": ["main", "configLoad"],
  "method": "esm"
}
```

**Recovery:** Fix the entry manually or re-run the intel updater.

## Implementation Notes

### ADR-457: TypeScript Source of Truth

Per `src/intel.cts:11-14`, the hand-written `bin/lib/intel.cjs` collapsed to a
TypeScript source of truth (`src/intel.cts`). The compiled `.cjs` is generated
at publish time. Behaviour is preserved byte-for-behaviour from the prior
hand-written `.cjs`; only types are added.

### Constants

From `src/intel.cts:27-35`:

```typescript
const INTEL_DIR = '.planning/intel';

const INTEL_FILES: Record<string, string> = {
  files: 'file-roles.json',
  apis: 'api-map.json',
  deps: 'dependency-graph.json',
  arch: 'arch-decisions.json',
  stack: 'stack.json',
};
```

### Command Router

The `intel-command-router.cjs` dispatches CLI subcommands via the Command Routing Hub
(ADR-959). It supports 9 subcommands: `api-surface`, `diff`, `extract-exports`,
`patch-meta`, `query`, `snapshot`, `status`, `update`, `validate`.

Test seams: `_intel` and `_core` parameters allow injection of mock modules for testing.

## References

- Agent definition: `agents/gsd-intel-updater.md`
- Core implementation: `src/intel.cts` (TypeScript source of truth)
- Compiled module: `gsd-core/bin/lib/intel.cjs`
- Command router: `gsd-core/bin/lib/intel-command-router.cjs`
- Capability resolver: `gsd-core/bin/lib/capability-state.cjs`
