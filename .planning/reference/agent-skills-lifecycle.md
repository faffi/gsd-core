# Agent Skills Lifecycle

> **Generated:** 2026-08-21T23:30:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** gsd-core/bin/lib/init.cjs:2865-3097, gsd-core/bin/gsd-tools.cjs, gsd-core/references/agent-skills-bootstrap.md

## 1. Purpose and Overview

The `agent_skills` capability injects user-configured skills into agent prompts, enabling project-specific skill injection into GSD's 22 consumer agents (gsd-executor, gsd-planner, etc.). This provides a configuration-driven extension point for customizing agent behavior without modifying agent definitions.

The capability operates across two seams:

1. **Orchestrator-side injection** — During workflow init, the orchestrator calls `gsd_run query agent-skills <agent-type>` and interpolates the returned `<agent_skills>` block into spawn prompts via `${AGENT_SKILLS_<ROLE>}` placeholders.

2. **Agent-side self-load** — Each consumer agent checks for an existing `<agent_skills>` block in its prompt during mandatory init. If absent (orchestrator did not inject), the agent self-loads its configured skills via the same CLI (gsd-core/references/agent-skills-bootstrap.md:19-23). The dedup guard prevents double-loading.

## 2. Configuration Schema

### agent_skills

A map in `.planning/config.json` where keys are agent type names and values are skill path arrays (or a single string):

```json
{
  "agent_skills": {
    "gsd-executor": ["skills/my-skill", "skills/another-skill"],
    "gsd-planner": "skills/planning-helpers",
    "gsd-verifier": ["global:test-helpers"]
  }
}
```

**Path formats:**

| Format | Example | Resolution |
|--------|---------|------------|
| Project-relative | `skills/my-skill` | Resolved against project root: `<project>/skills/my-skill/SKILL.md` |
| Global personal | `global:<name>` | Resolved against runtime's global skills dir: `~/.claude/skills/<name>/SKILL.md` |
| Plugin-namespaced | `global:<plugin>:<skill>` | **Claude only** — emitted as Skill-tool directive, no filesystem path |

### agent_skills_security.trusted_global_roots

An optional array of absolute paths that allow symlinks or escape hatches for global skills:

```json
{
  "agent_skills_security": {
    "trusted_global_roots": [
      "/Users/alice/shared-skills",
      "~/work/common-skills"
    ]
  }
}
```

Validations (security.cjs:150-206):
- Non-string entries are dropped
- Project-relative paths are rejected (must be absolute)
- Leading `~/` expands to `os.homedir()`
- Non-existent paths are skipped
- Filesystem root (`/`) and homedir itself are rejected as too broad
- Canonical realpath is used for all comparisons (closes case-insensitive bypass on macOS APFS)
- Results are de-duplicated by canonical path

## 3. CLI Commands

### gsd-tools query agent-skills

```bash
gsd_run query agent-skills <agent-type> [--json]
```

**Arguments:**
- `<agent-type>` — The agent name from frontmatter (e.g., `gsd-executor`). Required.
- `--json` — Output typed IR instead of raw block.

**Output (plain):**
The raw `<agent_skills>` XML block, suitable for direct interpolation into prompts.

**Output (--json):**
```json
{
  "agent_type": "gsd-executor",
  "block": "<agent_skills>\nRead these user-configured skills:\n- @skills/my-skill/SKILL.md\n</agent_skills>",
  "skills_count": 1,
  "warnings": [],
  "configured": true,
  "reason": "resolved",
  "source": "root",
  "degraded": false,
  "value": {
    "block": "<agent_skills>\n...",
    "skills_count": 1
  }
}
```

**Resolution reasons:**
- `not_configured` — Agent type not in `agent_skills` map
- `configured_empty` — Agent configured with empty array or blank strings
- `configured_unresolved` — Agent configured with paths but all failed to resolve
- `resolved` — At least one skill resolved successfully

## 4. Resolution Logic

### Processing Flow (init.cjs:2865-2988)

1. **Load config and extract agent skills** — Read `agent_skills[<agent-type>]` from config.
2. **Normalize to array** — Single strings become `[string]`.
3. **Validate and resolve each path:**
   - **Project-relative paths** — Resolve against project root, validate no traversal, check `SKILL.md` exists.
   - **Global skills (`global:<name>`)** — Resolve against runtime's skills directory.
   - **Plugin-namespaced (`global:<plugin>:<skill>`)** — Claude only, emit directive.
4. **Build output block** — Interleave `@`-includes and directives.

### Project-Relative Skills

```
skills/my-skill → <project-root>/skills/my-skill/SKILL.md
```

Security checks (security.cjs:46-135):
- Path traversal (`../`) rejected
- Null bytes rejected
- Symlinks are resolved via `realpathSync`
- Result must be within project root

### Global Skills

```
global:my-skill → ~/.claude/skills/my-skill/SKILL.md
```

Resolution via `getGlobalSkillsBase(runtime)` (runtime-homes.cjs:485-513):
1. Check runtime descriptor's artifact layout for `skills` kind
2. Honor `home` override if present (e.g., Codex uses `~/.agents/skills`)
3. Fall back to `<config-home>/skills`

Security:
- Symlink escape check via `validatePath(globalSkillMd, globalSkillsBase, { allowAbsolute: true })`
- If realpath escapes base, check against `trusted_global_roots`
- If no trusted root covers the path, reject

### Plugin-Namespaced Skills

```
global:coderabbit:code-review → Load the `coderabbit:code-review` skill via the Skill tool...
```

- **Claude runtime only** — The Skill tool is Claude-specific.
- **No filesystem path** — Emitted as a natural-language directive.
- **Other runtimes** — Skipped with warning: "requires a Skill-tool-capable runtime (claude)"

### Bare Name Hint (#2941)

When a project-relative path like `patch-coverage-check` fails to resolve but a global skill of that name exists, the warning hints at the `global:` prefix:

```
WARNING: Skill not found at "patch-coverage-check/SKILL.md" — a global skill named "patch-coverage-check" exists; use "global:patch-coverage-check" to reference it
```

## 5. Agent Bootstrap Contract

Every consumer agent self-loads its configured skills in its mandatory init step (agent-skills-bootstrap.md:14-39).

### When to Run

Immediately after `mandatory-initial-read.md` / Project skills discovery, before any other work.

### Steps

1. **Dedup guard (MANDATORY)** — Check if prompt already contains `<agent_skills>` block. If present, the orchestrator already injected; skip self-load entirely.

2. **Query configured skills** — Use your own agent type (the `name:` value from frontmatter):

   ```bash
   _AGENT_SKILLS=$(gsd_run query agent-skills <YOUR-FRONTMATTER-NAME> 2>/dev/null || true)
   ```

3. **Read listed skills** — The block emits `@<path>/SKILL.md` includes; `Read` each one.

### What Self-Load Covers

| Skill Form | Self-loads? | Notes |
|------------|-------------|-------|
| Project-relative | Yes, everywhere | `Read` the `@`-include |
| Global personal (`global:<name>`) | Yes, everywhere | Resolves to runtime global skills dir, then `Read` |
| Plugin-provided (`global:<plugin>:<skill>`) | Claude only | Emitted as Skill-tool directive; **skipped with warning on all other runtimes** |

### Why Two Seams?

Cursor and similar runtimes do not reliably execute delegated workflow bash (open-gsd/gsd-core#1600 / #1601). Agent-side self-load is durable across all runtimes; orchestrator-side injection is an optimization that avoids the extra CLI call when it works.

## 6. Output Format

### Include-Only Block

```
<agent_skills>
Read these user-configured skills:
- @/Users/alice/.claude/skills/shadcn/SKILL.md
- @skills/local-skill/SKILL.md
</agent_skills>
```

### Mixed Block (Includes + Directives)

```
<agent_skills>
Read these user-configured skills:
- @/Users/alice/.claude/skills/my-local-skill/SKILL.md
- Load the `vendor:remote-skill` skill via the Skill tool before proceeding (plugin-provided).
</agent_skills>
```

**Critical:** The block is a SINGLE `<agent_skills>` section. Plugin-provided directives are interleaved with `@`-includes in config order, not separated into a second section.

### Warnings

Warnings are emitted to stderr AND surfaced in `--json` IR `warnings[]`:
- Missing skill paths
- Invalid global skill names
- Symlink escape attempts
- Runtime incompatibility for plugin-namespaced skills
- Malformed config values

## 7. Consumer Agents

The 22 agents that consume `agent_skills` (tests/agent-skills.test.cjs:1327-1350):

| Agent | Agent |
|-------|-------|
| gsd-advisor-researcher | gsd-nyquist-auditor |
| gsd-assumptions-analyzer | gsd-phase-researcher |
| gsd-code-fixer | gsd-plan-checker |
| gsd-code-reviewer | gsd-planner |
| gsd-codebase-mapper | gsd-project-researcher |
| gsd-debugger | gsd-research-synthesizer |
| gsd-doc-writer | gsd-roadmapper |
| gsd-eval-auditor | gsd-security-auditor |
| gsd-executor | gsd-ui-auditor |
| gsd-integration-checker | gsd-ui-checker |
| | gsd-ui-researcher |
| | gsd-verifier |

All 22 declare `Skill` in their `tools:` frontmatter (tests/agent-skills.test.cjs:1326-1405) so they can invoke plugin-provided skills. A drift guard enforces this set exactly.

## 8. Security Notes

### Path Validation (security.cjs:46-135)

- **Traversal rejection** — `../` sequences, null bytes, and absolute paths (unless `allowAbsolute: true`) are rejected.
- **Symlink resolution** — All paths undergo `realpathSync` to resolve symlinks before validation.
- **Dangling symlink detection** — `lstatSync` distinguishes dangling symlinks from genuinely absent paths, preventing existence-oracle attacks.
- **Ancestor resolution** — For non-existent paths, walk up to nearest existing ancestor and canonicalize that, ensuring consistent comparisons on non-canonical cwds (macOS /var vs /private/var).

### Symlink Handling for Global Skills

Global skills can be symlinks. By default, the symlink target must be within the runtime's skills directory (`~/.claude/skills/`). If a symlink points outside:

1. `validatePath` returns `{ safe: false }`
2. `buildAgentSkillsBlock` checks each `trusted_global_roots` entry
3. If any root contains the resolved target, accept with a NOTE on stderr
4. Otherwise, reject with WARNING

### Trusted Global Roots Configuration

```json
{
  "agent_skills_security": {
    "trusted_global_roots": [
      "/absolute/path/to/shared-skills",
      "~/relative/to/home"
    ]
  }
}
```

- Only absolute paths after `~/` expansion are accepted
- Non-existent paths are silently skipped
- The filesystem root `/` and homedir `~` are rejected as too broad
- Canonical paths are de-duplicated

### Why Trusted Roots Exist

A symlinked global skill may legitimately point to a shared location (e.g., a monorepo's shared skills dir). Without trusted roots, such symlinks would be rejected as "escape attempts." Trusted roots allow explicitly authorizing these escape hatches while maintaining the default boundary.

## 9. Diagnostics

### Resolution Provenance (#1415)

The `--json` IR includes:
- `source` — Config provenance (`root`, `deprecated`, etc.)
- `degraded` — Whether config loading fell back to defaults
- `configured` — Whether agent type is in `agent_skills` map
- `reason` — Resolution outcome (`not_configured`, `configured_empty`, `configured_unresolved`, `resolved`)

### Empty-Resolution Diagnostics

When configured paths all fail to resolve:
- Aggregate WARNING on stderr naming the agent
- Each skipped path listed in `warnings[]`
- Aggregate diagnostic: "none resolved to a valid skill"

Partial resolution (at least one skill resolves) suppresses the aggregate warning; only individual skipped paths appear in `warnings[]`.

## 10. Implementation Notes

### buildAgentSkillsBlock (init.cjs:2865-2988)

- Returns empty string for unconfigured agents, empty arrays, or all-skipped paths
- Emits warnings to stderr AND collects in `diagnostics.warnings[]`
- Hoists `trustedGlobalRoots` computation before loop (one I/O operation, not one per failing skill)
- Emits `kind: 'include'` for path-resolvable skills, `kind: 'directive'` for plugin-namespaced
- Output is single `<agent_skills>` section with interleaved entries

### cmdAgentSkills (init.cjs:2989-3097)

- Anchors to project root via `findProjectRoot` before loading config (#1415/#1366 cwd-drift fix)
- Falls back to reading agent persona file for non-Claude runtimes when block is empty (#2454)
- Routes plain output through synchronous-flush `output()` to avoid truncation on Windows (#1400)
- Normalizes empty strings and all-blank arrays as `configured_empty`
- Builds Resolution envelope for `--json` output (#1416)

### Runtime Skills Directories

Each runtime has its own skills directory layout, defined in `runtime-homes.cjs`:

- **Claude** — `~/.claude/skills/`
- **Codex** — `~/.agents/skills/` (home override, independent of `$CODEX_HOME`)
- **Kimi-Code** — No config home (Marketplace extension) — `global:` prefix unsupported

Use `getGlobalSkillsBase(runtime)` to resolve; it returns `null` for runtimes without a skills directory, and callers must guard.
